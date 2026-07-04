---
id: postmortem-001-raspberrypi-tailnet-dropout
seq: 1
title: '라즈베리파이가 테일넷에서 사라지고, doctor는 Tailscale을 못 찾았다'
type: postmortem
date: 2026-07-04
context: 폰→맥 원격 접속 셋업(REMOTE-ACCESS 시나리오 A·D) 도중 홈서버로 쓰려던 라즈베리파이가 tailnet에 안 보임. v0.2.0 릴리즈로 이어진 세션.
audience: 주니어 개발자
length: 작업 단계별 풀어쓰기
created_at: 2026-07-04
created_by: dorito
updated_at: 2026-07-04
updated_by: dorito
last_verified_at: 2026-07-04
last_verified_by: dorito
audit_log:
    - action: created
      at: 2026-07-04
      by: dorito
      note: '폰→맥 원격 셋업 + v0.2.0 릴리즈 직후 세션 회고로 작성'
    - action: updated
      at: 2026-07-04
      by: dorito
      note: '사용자 액션 2건(키 만료 끄기·전원 어댑터) 완료 확인, uptime 11h15m 무중단 검증'
status: active
tags: [postmortem, tailscale, raspberry-pi, remote-access, hardware]
relations:
    - docs/en/REMOTE-ACCESS.md          # §6.4 홈서버 워크플로우, §8.6/§8.12 증상 문서화
    - docs/en/FAQ.md                    # Q1 라즈베리파이 한계
    - CHANGELOG.md                      # v0.2.0
code_refs:
    - file: bin/ai
      note: 'cmd_remote_doctor — GUI 앱 Tailscale 폴백 + sshd TCP 프로브 추가'
---

## 사건 한 줄 요약

집 라즈베리파이를 홈서버로 붙이려는데 **불은 들어오지만 tailnet에서 계속 offline**
이었고, 원인은 하나가 아니라 **세 층(Tailscale 키 만료 → 전원 부족 재부팅 루프 →
인증 URL이 재부팅마다 무효화)** 이 겹친 것이었다. 곁가지로, 맥의 `ai remote doctor`
는 Tailscale이 멀쩡히 돌고 있는데도 `tailscale: NOT FOUND` 라고 오진했다.

## 0. 사전 지식

이 글을 읽는 데 필요한 최소 개념만.

| 용어 | 한 줄 설명 |
|------|-----------|
| **tailnet** | 내 기기들만 모인 사설 메시 네트워크 (Tailscale 계정 단위) |
| **node key 만료** | Tailscale이 각 기기 인증키에 거는 유효기간(기본 ~180일). 지나면 그 기기는 tailnet에서 조용히 빠진다 |
| **CGNAT/NAT** | 집 공유기 뒤 기기는 밖에서 직접 접속 불가. Tailscale은 양쪽이 바깥으로 나가 만나는 방식이라 이걸 우회한다 |
| **브라운아웃(brownout)** | 전압이 순간적으로 기준 밑으로 떨어지는 것. 완전 정전(블랙아웃)과 달리 기기가 "리셋"만 된다 |
| **mDNS (`*.local`)** | 같은 LAN 안에서 호스트 이름으로 서로 찾는 방식. tailnet과 무관하게 동작 |

핵심 원리 하나만 먼저(ELI5): Tailscale은 **"출입증(node key)"** 으로 굴러간다.
출입증이 만료되면 건물(tailnet) 입구에서 막힌다 — 기기가 켜져 있든 말든. 오늘 파이는
출입증이 만료된 상태에서, 재발급받으려 할 때마다 **정전으로 쓰러졌다.**

## 1. 증상

- `tailscale status` 에서 파이만 죽어 있었다:

  ```
  100.117.91.34    raspberrypi     baksohyeon@  linux  offline, last seen 166d ago
  ```

- 사용자 관찰: **"불도 들어와있는데"** 안 보임. 즉 전원은 공급되는 것으로 보였다.
- 곁가지 증상: 맥에서 `ai remote doctor` 가

  ```
  tailscale: NOT FOUND
  ```

  라고 했지만, `tailscale status` 자체는 잘 돌고 있었다 (모순).

## 2. 첫 의문 + 가설

파이가 왜 안 보이나. 확인은 **싸고 신호가 센 것부터.**

| id | 가설 | 왜 그럴 수 있는지 | 어떻게 확인할지 |
|----|------|------------------|-----------------|
| H1 | 파이가 LAN에는 살아있다 (tailnet만 문제) | 불이 들어온다니 전원은 됨. mDNS로 찾아지면 OS는 부팅된 것 | `ping raspberrypi.local`, `ssh dorito@raspberrypi.local` |
| H2 | Tailscale node key 만료 | "166일 전"이 기본 만료 ~180일에 근접 | `tailscale ping raspberrypi` 의 에러 문구 확인 |
| H3 | tailscaled 데몬만 죽음 | 서비스만 꺼졌을 수 있음 | 파이에서 `tailscale status` 직접 |
| H4 | 맥 doctor의 오진은 별개 버그 | GUI 앱은 CLI를 PATH에 안 깔음 | `command -v tailscale` vs 앱 번들 경로 |

## 3. 진단: 실제 상태 확인

**H1 — 파이는 LAN에 살아있다: 지지됨.**

```
$ ping -c 2 raspberrypi.local
2 packets transmitted, 2 packets received, 0.0% packet loss
$ ssh dorito@raspberrypi.local 'echo OK: $(whoami)@$(hostname)'
OK: dorito@raspberrypi
```

OS는 부팅됐고 SSH 키도 그대로다. 문제는 tailnet 계층에 한정된다.

**H2 — node key 만료: 지지됨 (결정적 증거).**

```
$ tailscale ping raspberrypi
peer's node key has expired
```

문구가 정확히 만료를 가리킨다. "166일 전 마지막 접속"과 일치.

**H3 — 데몬은 살아있다 (키만 문제): 지지됨.**

```
$ ssh dorito@raspberrypi.local 'tailscale status'
Logged out.
Log in at: https://login.tailscale.com/a/1ff3f18239c3ec
```

데몬은 돌고 있고 로그인 URL까지 내준다. 서비스 다운(H3의 원래 추측)이 아니라
**인증 만료**임이 확정.

**H4 — 맥 doctor 오진은 별개 버그: 지지됨.**

```
$ command -v tailscale        # (비어 있음 — PATH에 없음)
$ ls /Applications/Tailscale.app/Contents/MacOS/Tailscale
/Applications/Tailscale.app/Contents/MacOS/Tailscale   # 앱 번들 안에는 있음
```

GUI 앱은 CLI 바이너리를 PATH에 심지 않는다. doctor는 `command -v tailscale` 하나만
보고 "없음"으로 단정했다. 사건의 원인은 아니지만 같이 고칠 진짜 결함.

### 3.1 재부팅 루프 — 예상 못 한 두 번째 층

키를 재발급하려고 파이에서 `tailscale up --ssh` 를 거는 순간부터, **SSH가 반복적으로
끊겼다.** 재접속해서 부팅 시각을 보니:

```
$ ssh dorito@raspberrypi.local 'uptime; last -x reboot | head -3'
 10:36:09 up 0 min
reboot   system boot   Sat Jul  4 10:28   still running
reboot   system boot   Sat Jul  4 10:16 - 10:28  (00:11)
reboot   system boot   Sat Jul  4 10:28   ...
```

**몇 분 간격으로 재부팅**되고 있었다. 열/전압/디스크를 즉시 확인:

```
$ ssh dorito@raspberrypi.local 'vcgencmd measure_temp; vcgencmd get_throttled; df -h / | tail -1'
temp=35.0'C
throttled=0x0
/dev/mmcblk0p2   29G  8.8G  19G  33% /
```

온도 정상(35°C), **저전압 플래그도 0x0**, 디스크 33%. 소프트웨어·발열·용량 다 무죄.
남는 건 전원 하드웨어. 사용자 확인 결과 **맥북 USB-C 충전기로 파이에 급전 중**이었다.
→ Pi 4는 5V/3A 전용인데, 노트북 PD 충전기는 부하가 걸리면 브라운아웃으로 조용히
리셋된다. **`throttled=0x0` 인 채로도** 죽는 게 이 실패의 특징이라 오해하기 쉽다.

### 3.2 인증 URL이 재부팅마다 무효화 — 세 번째 층

파이가 재부팅되면서 `tailscale up` 의 로그인 세션이 초기화됐고, **매번 새 URL이
발급**됐다. 사용자가 처음 승인한 URL은 그 사이 stale이 되어, "승인했는데 여전히
offline" 이 반복됐다. 파이에서 직접 최신 URL을 뽑아 전달하고 나서야 인증이 붙었다:

```
$ tailscale status | grep rasp
100.117.91.34   raspberrypi   baksohyeon@   linux   active; direct 192.168.219.110:41641
```

`direct` = P2P 직결(릴레이 경유 아님), 12ms. tailnet 복귀 확정.

## 5. 결론 / 해결

세 층을 순서대로 걷어냄:

1. **키 만료** → 파이에서 `tailscale up --ssh --operator=dorito` 로 재인증.
   (기존 non-default 플래그를 전부 다시 적어야 함 — Tailscale이 그렇게 요구한다.)
2. **재부팅 루프** → 근본 원인은 전원. 임시로는 버텼지만, 진짜 해결은
   **정품 5V/3A 어댑터**. 사용자는 15W+ 충전기로 교체 예정.
3. **stale URL** → 항상 **가장 최근** `tailscale status`/`up` 출력의 URL만 사용.
4. **재발 대비** → 파이에 영구 저널 활성화:
   `sudo mkdir -p /var/log/journal && sudo systemctl restart systemd-journald`.
   다음 크래시는 `journalctl -b -1 -e` 로 사후 분석 가능.

곁가지(맥 doctor 오진)도 같이 수정: `command -v tailscale` 실패 시
`/Applications/Tailscale.app/Contents/MacOS/Tailscale` 로 폴백. **트레이드오프**:
경로 하드코딩이라 앱 위치를 바꾸면 못 찾지만, GUI 앱의 표준 설치 경로라 실용적으로
안전하다. 심볼릭 링크는 안 됨 — 바이너리가 번들 밖에서 실행되면
`bundleIdentifier is unknown to the registry` 로 죽는다(그래서 alias 방식).

## 6. 재발 방지 / 운영 메모

- [x] **서버 역할 기기는 Tailscale 키 만료를 끈다.** 관리 콘솔 → Machines →
      raspberrypi → Disable key expiry. (2026-07-04 완료 — 안 했으면 180일 뒤 재발)
- [x] **파이 전원 여유 확보.** 15W+ 충전기로 전환(2026-07-04). 상시 켜둘 기기가
      상시 안 켜져 있으면 전원부터 의심.
- [x] **영구 저널 활성화** (이번에 적용). 크래시가 증거를 남기게.
- [x] **doctor가 GUI 앱 Tailscale을 인식.** `bin/ai` 수정 완료.
- [x] **증상을 문서화.** REMOTE-ACCESS §8.6(만료 URL), §8.12(파이 전원 루프),
      FAQ Q1(파이 한계)에 반영.

## 6.5 승격 (promotion)

§6의 각 항목이 사람 기억이 아니라 **durable home** 에 자리 잡도록:

| §6 항목 | 승격처 | 상태 |
|---------|--------|------|
| doctor의 GUI 앱 Tailscale 폴백 | `bin/ai` `cmd_remote_doctor` + smoke 21/21 | ✅ 코드로 졸업 (v0.2.0) |
| sshd 감지 오탐(비루트 lsof) | `bin/ai` `_sshd_listening` TCP 프로브 폴백 | ✅ 코드로 졸업 |
| 만료 URL / stale URL 함정 | `docs/*/REMOTE-ACCESS.md §8.6` | ✅ 문서로 졸업 |
| 파이 전원 재부팅 루프 | `docs/*/REMOTE-ACCESS.md §8.12` + `FAQ Q1` | ✅ 문서로 졸업 |
| **서버 기기 키 만료 끄기** | 관리 콘솔은 코드 밖 → 문서 §1.6/§7.2에 근거 명시 | ✅ 사용자 완료 (2026-07-04, 콘솔에서 key expiry 비활성화) |
| **파이 전원 어댑터 교체** | 물리 작업 | ✅ 사용자 완료 (2026-07-04, 15W+ 충전기로 전환) |

두 줄(키 만료 끄기 · 어댑터)은 **사용자만 할 수 있는 물리/콘솔 작업**이라 코드/문서로
못 내리는 항목이었고, 같은 날 사용자가 직접 실행해 닫혔다. 검증: 어댑터 교체 후
**uptime 11시간 15분 무중단**(`load average 0.00`, 유휴 구간)으로 재부팅 루프 종료를
확인. 단, 브라운아웃은 부하 순간에만 드러나는 실패이므로 유휴 uptime은 필요조건이지
충분조건은 아니다 — 실사용 부하에서의 안정성은 영구 저널(§6)이 다음 크래시 때 판정한다.

## 7. 타임라인

- **10:16** — 파이 첫 재부팅 흔적 (`last -x reboot`).
- **10:22경** — 폰→맥 원격 셋업 시작. `tailscale status`에서 파이 `offline 166d`.
- **10:27** — `tailscale ping` → `peer's node key has expired` (H2 확정).
- **10:28~10:36** — `tailscale up` 시도할 때마다 파이 재부팅. 열/전압/디스크 정상 확인 → 전원 의심.
- **10:36** — 파이에서 직접 최신 인증 URL 확보, 사용자에게 전달.
- **이후** — 사용자 승인 → `active; direct ... 12ms` 로 tailnet 복귀. 첫 승인은 stale URL이라 1회 재시도 필요했음.
- **같은 세션 후반** — doctor 수정·문서 재구성·FAQ·`ai pick` 추가 → **v0.2.0 릴리즈**.
