---
id: postmortem-002-codex-gui-isolation-mismatch
seq: 2
title: 'ai gui가 Codex를 격리 못 하고 dock만 어지럽힌 건 + 빈 codex-company'
type: postmortem
date: 2026-07-03
context: ai-session-router 라우터 유지보수 중, "회사 계정 스킬/플러그인이 다 나가리고 dock이 꼬였다"는 제보로 시작한 /investigate 세션
audience: 주니어 개발자
length: 작업 단계별 풀어쓰기
created_at: 2026-07-03
created_by: dorito
updated_at: 2026-07-03
updated_by: dorito
last_verified_at: 2026-07-03
last_verified_by: dorito
audit_log:
    - action: created
      at: 2026-07-03
      by: dorito
      note: 'Track A(gui에서 Codex 제거) + Track B(계정 채움/공유 스토어/dock 정리) 직후 작성'
status: active
tags: [postmortem, codex, gui-isolation, CODEX_HOME, shared-store]
relations:
    - CHANGELOG.md                 # [Unreleased] Changed/Removed 항목
    - BACKLOG.md                   # 승격된 후속: shared-store 명령 + ai gui prune
    - docs/en/SURFACES.md          # "무엇이 격리되나" 표 — Codex desktop = CLI-first
    - docs/en/SUPPORT.md           # 지원 현황 + "왜 되는가" 설명
code_refs:
    - file: bin/ai
      note: 'gui 네이티브-격리 레지스트리에서 codex 제거, AI_GUI_APPS 기본값 claude'
    - file: examples/router.env.example
      note: 'AI_CODEX_APP / AI_CODEX_APP_DATA_PREFIX 삭제, 주석 정정'
---

# ai gui가 Codex를 격리 못 하고 dock만 어지럽힌 건 + 빈 codex-company

## 사건 한 줄 요약

`ai gui`가 Codex 데스크톱 앱을 `--user-data-dir`로 계정별 격리하려 했지만, Codex는 그
플래그를 **읽지 않는다**(계정을 `CODEX_HOME`에서 읽음). 그래서 격리는 무효인 채 dock에는
유령 Codex.app 인스턴스만 쌓였고, 게다가 회사용 `~/.codex-company` 계정은 애초에 스킬·설정이
비어 있어서 "다 나가리"처럼 보였다.

---

## 0. 사전 지식

이 글을 읽는 데 필요한 개념 네 개만 먼저 짚는다.

| 용어 | 쉬운 풀이 |
|---|---|
| **환경변수 `CODEX_HOME`** | Codex CLI가 "내 계정·설정·스킬은 이 폴더에서 읽어라" 하고 보는 주소. 라우터는 계정마다 다른 폴더(`~/.codex-personal`, `~/.codex-company`)를 넣어줘서 계정을 갈라놓는다. |
| **`--user-data-dir`** | Chromium(크롬 엔진) 계열 앱한테 "네 프로필 데이터를 이 폴더에 둬라" 하고 주는 실행 옵션. 브라우저·Electron 앱한테만 통한다. |
| **Electron** | 웹 기술로 만든 데스크톱 앱 껍데기. 안에 Chromium을 품고 있어서 `--user-data-dir`을 이해한다. Claude.app, Codex.app 둘 다 Electron이다. |
| **심볼릭 링크(symlink)** | 실제 파일 대신 "저기를 봐라"라고 가리키는 바로가기. 링크 하나만 두고 원본은 한 곳에 모으면 디스크를 아끼고, 원본을 고치면 링크 쪽에도 그대로 반영된다. |

핵심 함정 하나: **Codex.app은 Electron이 맞지만, 정작 자기 계정은 `--user-data-dir`이 아니라
`CODEX_HOME`에서 읽는다.** 즉 껍데기(Electron)를 격리해도 알맹이(계정)는 안 갈라진다. 이 글의
절반은 이 한 문장에서 출발한다.

---

## 1. 증상

사용자 제보(원문 요지):

> "회사 계정, 개인 계정 gui 분리는 잘 되어 있는데 맥 dock 상태 꼬라지 봐라. 스킬 플러그인
> 다 나가리에 이게 뭐냐. `$HOME`에서 `ls` 해서 원인 파악 좀 해봐."

관측된 것:

1. **Dock 클러터** — Codex 아이콘이 여러 개 떠 있음.
2. **회사 Codex가 텅 빈 느낌** — 스킬/플러그인이 안 보임.
3. **상태가 꼬였다는 전반적 체감** — "다 나가리"(다 날아갔다).

이 시점에서 확정된 사실은 없다. "스킬이 안 보인다"가 곧 "스킬 파일이 삭제됐다"는 아니다.
관측(보인 것)과 해석(원인)을 분리하는 게 첫 단추다.

---

## 2. 첫 의문 + 가설

싼(빠르고 신호 강한) 검증부터 위에 오도록 정렬했다.

| id | 가설 | 왜 그럴 수 있는지 | 어떻게 확인할지 |
|---|---|---|---|
| **H1** | 스킬/플러그인 파일이 실제로 삭제됐다 | "다 나가리"의 가장 직역 | `ls`/`du`로 각 계정 폴더의 스킬·플러그인 개수·용량 확인 |
| **H2** | 계정 폴더가 서로 엉켜 있다(잘못된 심볼릭 링크 등) | 격리가 깨지면 한쪽 변경이 다른 쪽에 샌다 | 각 폴더가 실제 디렉토리인지 symlink인지 확인 |
| **H3** | 특정 계정(`~/.codex-company`)만 안 채워졌다 | 회사 계정만 비어 보인다는 제보 | 계정별로 스킬 수·`config.toml` 크기 비교 |
| **H4** | dock 유령은 gui 격리가 Codex엔 안 먹혀서 생겼다 | Codex는 `CODEX_HOME`을 읽지 `--user-data-dir`을 안 읽는다 | 실행 중 프로세스(`ps`)와 `bin/ai`의 gui 등록 코드 확인 |

---

## 3. 진단: 실제 상태 확인

### 3-1. 파일이 실제로 있나 (H1, H3)

`~`에서 계정별 인벤토리를 떴다.

Claude 쪽 (개수·용량):

```
=== .claude ===          skills: 256   size: 1.9G
=== .claude-personal === skills: 255   size: 2.1G
=== .claude-company ===  skills: 255   size: 1.8G
```

Codex 쪽:

```
=== .codex ===           size: 2.0G   skills: 161  agents: 127  config.toml: 621 lines  auth.json: present
=== .codex-personal ===  size: 2.6G   skills: 161  agents: 47   config.toml: 518 lines  auth.json: present
=== .codex-company ===   size: 98M    skills: 0    (agents 없음)  config.toml: 8 lines   auth.json: present
```

**해석:**
- **H1 기각.** Claude는 세 계정 다 255~256개 스킬이 멀쩡히 있고, Codex도 personal은 161개다.
  파일이 대량 삭제된 흔적이 없다. "다 나가리"는 삭제가 아니라 **한 계정이 안 보였던 체감**이었다.
- **H3 강하게 지지.** `~/.codex-company`만 스킬 0개, `config.toml` 8줄, 용량 98M로 유독 비어 있다.
  나머지는 다 2GB대. 범인은 "전부"가 아니라 **회사 Codex 계정 하나**다.

그 8줄짜리 `config.toml` 전문(verbatim):

```toml
[projects."/Users/cnai/work/cnai"]
trust_level = "trusted"

[projects."/Users/cnai/dev/work"]
trust_level = "trusted"

[tui.model_availability_nux]
"gpt-5.5" = 4
```

프로젝트 신뢰 설정과 UI 카운터뿐이다. 플러그인·MCP 서버·모델·에이전트 설정이 통째로 없다.
회사 Codex를 열면 아무 스킬도 안 뜨는 게 당연했다.

### 3-2. 폴더가 엉켜 있나 (H2)

각 폴더가 symlink인지 실제 디렉토리인지 확인:

```
=== symlink targets (if any) ===
(none listed above = all real dirs, not symlinks)
```

**해석: H2 기각.** 당시 여섯 계정 폴더는 전부 **독립된 실제 디렉토리**였다. 서로 엉킨 게 아니라,
오히려 완전히 따로 놀며 중복돼 있었다(뒤 §5에서 이걸 역이용한다).

### 3-3. Dock 유령의 정체 (H4)

실행 중인 Codex.app 프로세스 중 **격리 폴더에 묶인 메인 프로세스**만 추림:

```
26409 /Applications/Codex.app/Contents/MacOS/Codex --user-data-dir=/Users/cnai/.codex-app-company
84998 /Applications/Codex.app/Contents/MacOS/Codex --user-data-dir=/Users/cnai/.codex-app-personal
```

그리고 `bin/ai`는 이 앱들을 gui 격리 대상으로 등록하고 있었다(정정 전 코드):

```sh
: "${AI_CODEX_APP:=/Applications/Codex.app}"        # Electron (ships app.asar) -> honors --user-data-dir
: "${AI_CODEX_APP_DATA_PREFIX:=$HOME/.codex-app-}"
: "${AI_GUI_APPS:=claude codex}"
```

**해석: H4 지지.** `ai gui`가 `open -n -a Codex.app --args --user-data-dir=~/.codex-app-<account>`로
Codex.app을 **계정마다 새 인스턴스로** 띄우고 있었다. `open -n`은 "이미 떠 있어도 새로 하나 더
띄워라"라는 뜻이라, 계정 수만큼 dock 아이콘이 늘었다. 이게 dock 클러터의 정체다.

---

## 4. 추가 확인: 왜 Codex엔 `--user-data-dir`이 안 먹히나

H4를 "지지"에서 "확정"으로 올리려면, `--user-data-dir`이 Codex 계정을 실제로 못 가른다는 걸
근거로 대야 한다.

- Codex CLI는 계정·`auth.json`·설정·세션을 전부 **`CODEX_HOME`**에서 읽는다(공식 문서:
  [Codex auth](https://developers.openai.com/codex/auth),
  [config](https://developers.openai.com/codex/config-advanced)). `--user-data-dir`은 이 결정에
  개입하지 않는다.
- 그래서 Codex.app을 `--user-data-dir`만 바꿔 여러 개 띄워도, 전부 **같은 `CODEX_HOME`**(보통
  기본값)을 바라본다. 계정은 하나도 안 갈라지고 Electron 껍데기만 여러 개가 된다.
- 대조군: **Claude.app은 왜 격리가 되나?** Claude 데스크톱 앱은 Claude Code를 임베드하고, 그
  상태를 `--user-data-dir`이 가리키는 폴더에서 읽는다. 그래서 같은 트릭이 Claude엔 통하고
  Codex엔 안 통한다. 같은 "Electron"이라도 **계정 상태를 어디서 읽느냐**가 다르다.

**결론: 검증된 것과 안 된 것을 명시한다.**
- 검증됨: gui 격리가 Codex의 dock 인스턴스를 늘렸다(H4), 회사 Codex가 비어 있었다(H3).
- 검증 안 됨: `--user-data-dir`을 준 Codex 인스턴스가 어떤 `CODEX_HOME`을 실제로 물었는지는
  프로세스 인자만으로 단정하지 않았다. 다만 "격리가 무효"라는 결론은 Codex의 문서화된 계정
  결정 방식(`CODEX_HOME`)에서 곧바로 따라온다.

---

## 5. 결론 / 해결

두 갈래로 나눠 고쳤다. **Track A = 레포 코드 수정**(재발 원인 제거), **Track B = 이 머신의
실제 상태 정리**(증상 치료).

### Track A — `ai gui`에서 Codex 제거 (commit `f032e2b`)

Codex는 gui 격리가 무의미하므로 아예 대상에서 뺐다. 이제 Codex는 CLI-first
(`ai codex <account>`가 `CODEX_HOME`을 세팅 → 이게 진짜 격리). 정정 후 코드:

```sh
# Codex desktop app is intentionally NOT gui-isolated. Codex reads its account, config,
# plugins, and skills from CODEX_HOME, not from an Electron --user-data-dir ...
: "${AI_GUI_APPS:=claude}"
```

`bin/ai` 레지스트리에서 `codex)` 케이스 제거, `examples/router.env.example`에서
`AI_CODEX_APP`/`AI_CODEX_APP_DATA_PREFIX` 삭제, `docs/{en,ko}/SUPPORT.md`+`SURFACES.md`의
"Codex 데스크톱 앱" 행을 "격리 안 됨 / CLI-first"로 정정.

### Track B — 이 머신 상태 정리 (되돌림 가능하게)

**(1) 빈 `~/.codex-company` 채움.** `~/.codex-personal`을 원본 삼아 `skills/`(161),
`agents/`(47), `rules/`, `hooks/`, `bin/`, `scripts/`, `gsd-core/` 등을 복사. `config.toml`은
personal 것을 복사한 뒤 node_repl의 경로 두 곳만 `.codex-company`로 치환하고 회사 프로젝트
신뢰(`dev/work`)를 병합. **`auth.json`은 절대 건드리지 않았다** — Codex의 refresh 토큰은 1회용이라
계정 간 복사 금지이며, 회사는 자기 로그인을 유지해야 한다. 복사 전후 지문 동일:

```
=== company auth.json BEFORE === -rw------- Jun 26 13:54:18 2026 4509 bytes
=== company auth.json FINAL  === -rw------- Jun 26 13:54:18 2026 4509 bytes
```

**(2) Claude 공유 스토어(dedup + 업그레이드 일원화).** §3-2에서 확인한 "완전 중복"을 역이용.
붕괴 전 **내용이 정말 같은지** 먼저 증명했다:

```
personal files: 18661   company files: 18661
personal path+size hash: 7c59289d68f91e8f33b1002c4c0ceee4478c3dbbefb5bad09f7c19e9911f0038
company  path+size hash: 7c59289d68f91e8f33b1002c4c0ceee4478c3dbbefb5bad09f7c19e9911f0038
=> path+size MANIFEST IDENTICAL ✓
```

플러그인 마켓플레이스는 git 저장소라 저장소별 HEAD가 같은지로 확인(같으면 같은 버전):

```
ecc / karpathy-skills / pm-skills / ui-ux-pro-max-skill / temp_1782784512409  → ✓ 동일 HEAD
claude-plugins-official / gitkraken → git이 아님(양쪽 다) → 내용 매니페스트로 대조 → IDENTICAL ✓
```

그 뒤 `skills/`와 `plugins/marketplaces`를 `~/.ai-shared/claude/` 한 벌로 모으고, 개인·회사 계정은
그쪽을 가리키는 **symlink**로 교체. 계정별로 달라야 하는 것(`installed_plugins.json` 개인 16 /
회사 17, `plugins/cache`, `auth`, `sessions`, `projects`)은 **공유하지 않았다**. 결과: 스킬·플러그인을
한 계정에서 업그레이드하면 양쪽에 반영되고, 디스크는 개인 2.1G→753M / 회사 1.8G→494M로 약 2.5G 회수.

**(3) Dock 정리.** 유령 Codex.app 메인 프로세스(회사 26409, 개인 84998)에 graceful 종료(SIGTERM).
헬퍼까지 0개로 떨어진 걸 확인하고, 남은 빈 `~/.codex-app-*` 디렉토리를 백업 후 삭제.

**트레이드오프**
- 공유 스토어는 symlink라, 한 계정에서 스킬을 지우면 양쪽에서 사라진다. "업그레이드 일원화"의
  이면이다. 계정별로 다른 스킬 셋을 원하면 이 구조는 안 맞는다(지금은 셋이 동일해서 이득만 있음).
- `~/.codex-company`의 `config.toml`은 personal에서 왔으므로, 순수 회사 전용 설정이 필요하면
  추가 조정이 든다. 지금은 "빈 상태보다 낫다"가 목표라 personal 미러로 충분.
- 20G짜리 `~/.claude-app-*`(Electron 캐시)는 앱이 실행 중이라 **일부러 안 건드렸다**(§6에 후속).

---

## 6. 재발 방지 / 운영 메모

- [ ] **gui 격리 대상은 "계정을 그 폴더에서 읽는 앱"만.** Electron이냐 아니냐가 기준이 아니다.
      Codex처럼 계정을 `CODEX_HOME`에서 읽는 앱은 격리 대상이 아니다.
- [ ] **계정 채울 때 `auth.json`은 절대 복사 금지.** Codex refresh 토큰은 1회용.
- [ ] **대량 dedup 전엔 내용 동일성 증명 먼저.** 파일 개수 + path+size 매니페스트, git 저장소는
      HEAD 대조. 다르면 union, 같을 때만 collapse.
- [ ] **파괴적 라이브 작업은 삭제가 아니라 move-aside + 백업 후.** 검증 끝나고 회수.
- [ ] **`~/.claude-app-*` Electron 캐시(13G+7.4G) 정리** — 앱 껐을 때 `Cache`/`GPUCache`/
      `Service Worker` 만 비우면 대부분 회수. 지금은 실행 중이라 보류(BACKLOG 등재).

---

## 6.5 승격 (promotion)

§6 항목을 기억에 맡기지 않고 durable home으로 졸업시켰다.

| §6 항목 | 승격된 곳 | 양방향 링크 |
|---|---|---|
| gui 격리 기준 정정 | `bin/ai` 주석 + `docs/{en,ko}/SUPPORT.md`·`SURFACES.md` (commit `f032e2b`) | 이 문서 `code_refs` ↔ 해당 파일 |
| 공유 스토어를 명령으로 코드화 | `BACKLOG.md` "Shared-store command" (commit `44d02d0`) | 이 문서 `relations` ↔ BACKLOG |
| Electron 캐시 prune | `BACKLOG.md` "Electron cache prune" (commit `44d02d0`) | 상동 |
| 변경 기록 | `CHANGELOG.md` `[Unreleased]` Changed/Removed | 상동 |

아직 코드로 못 올린 것: 공유 스토어 셋업·계정 채우기·prune을 라우터 명령(`ai shared`, `ai gui prune`)과
`ai doctor` 체크로 구현하는 일. BACKLOG 후보로 등재되어 릴리스 때 졸업 예정.

---

## 7. 타임라인

- **제보** — dock 꼬라지 + 회사 계정 스킬/플러그인 "다 나가리".
- **진단** — `~`에서 계정별 `ls`/`du`. H1(삭제) 기각, H3(회사 Codex만 빔) 지지, `.codex-company`
  `config.toml` 8줄 확인.
- **원인 확정** — `ps`에서 `--user-data-dir=.codex-app-*` 인스턴스 발견 + `bin/ai`가 Codex를
  gui에 등록. Codex는 `CODEX_HOME`을 읽으므로 gui 격리는 무효(H4).
- **Track A** — `ai gui`에서 Codex 제거(CLI-first). 코드·예제·문서·CHANGELOG. `f032e2b`로 main 반영.
- **Track B** — `.codex-company` 채움(auth 불변), Claude 스킬·마켓플레이스 공유 스토어화(≈2.5G 회수),
  유령 Codex.app 종료 + 빈 디렉토리 제거. 전 단계 백업 보유.
- **후속** — BACKLOG 2건 등재(`44d02d0`), 계정 레이아웃 메모리 갱신, 본 postmortem 작성.
