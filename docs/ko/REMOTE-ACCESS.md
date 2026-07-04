# 원격 접속 완전 가이드 (한국어판)

**Language:** [English](../en/REMOTE-ACCESS.md) · 한국어

한 컴퓨터에서 AI CLI 세션을 띄워놓고, 다른 노트북·기차에서 휴대폰·호텔 Wi-Fi 등
어디서든 그 세션에 붙는 법. 네트워크가 끊겨도, 노트북 덮개를 닫아도 세션이 살아있게.

이 문서는 **Tailscale 우선**입니다. 요즘 정석 — mesh VPN + SSH + 세션
멀티플렉서 — 이 맨 앞에 옵니다. 실제로 해야 할 게 그거니까요. 각 섹션은 여전히
*어떻게* 전에 *왜*부터 짚지만, 네트워크 이론과 pre-Tailscale 도구 상자(포트
포워딩, DDNS, reverse tunnel)는 이제 원래 있어야 할 자리인
[부록 C](#부록-c-네트워크-기초--pre-tailscale-도구-상자)로 옮겼습니다. 필수
선행지식이 아니라 배경 독서 자료입니다.

> **TL;DR** — 모든 기기에 Tailscale을 깔고 (§1), 호스트에 SSH를 켜고 (§2),
> 작업은 tmux 안에서 돌리고 (§3), 호스트를 잠들지 않게 하세요 (§4). 이게 시스템
> 전부입니다. 2015년식 가이드처럼 포트 포워딩도, DDNS도, VPS 릴레이도 왜 필요
> 없는지 궁금하다면, 부록 C가 그 레거시 도구 상자 전체를 표 하나로 요약해줍니다.

### 표기 규칙

- 셸 명령 안의 `$USER`: 실행 시점에 본인 사용자 이름으로 자동 확장. 예제를
  그대로 복사해서 쓰면 됩니다.
- 설정 파일 (SSH config, ACL JSON 등) 안의 `<your-username>`, `<your-host>` 등은
  수동 placeholder. 본인 값으로 바꿔서 저장하세요. 이 파일들은 셸 확장이 안 됩니다.
- `home-mac`, `home-server`, `work-laptop`: 호스트네임 일반 placeholder.
  `tailscale set --hostname`으로 본인이 정한 이름을 쓰세요.
- `~/dev/personal`, `~/dev/work`: [`install.sh`](../../install.sh)의 기본 워크스페이스.
  `router.env`로 덮어쓰기 가능 (예시: [examples/router.env.example](../../examples/router.env.example)).

---

## 목차

0. [이 문서가 해결하는 시나리오](#0-이-문서가-해결하는-시나리오)
1. [Tailscale: mesh VPN 백본](#1-tailscale-mesh-vpn-백본)
2. [SSH: 만능 원격 셸](#2-ssh-만능-원격-셸)
3. [세션 영속성: tmux와 그 대안들](#3-세션-영속성-tmux와-그-대안들)
4. [맥 잠 못 자게 하기](#4-맥-잠-못-자게-하기)
5. [휴대폰 클라이언트](#5-휴대폰-클라이언트)
6. [실전 통합 워크플로우](#6-실전-통합-워크플로우)
7. [보안 & 회사 정책](#7-보안--회사-정책)
8. [트러블슈팅](#8-트러블슈팅)
9. [`ai` 라우터와의 통합](#9-ai-라우터와의-통합)
- [부록 A: 빠른 명령어 치트시트](#부록-a-빠른-명령어-치트시트)
- [부록 B: 추천 자료](#부록-b-추천-자료)
- [부록 C: 네트워크 기초 & pre-Tailscale 도구 상자](#부록-c-네트워크-기초--pre-tailscale-도구-상자)
- [부록 D: 한국 환경에서 자주 만나는 함정](#부록-d-한국-환경에서-자주-만나는-함정)

---

## 0. 이 문서가 해결하는 시나리오

| # | 시나리오 | 사용 도구 |
|---|----------|-----------|
| A | 출퇴근 길 휴대폰 → 집 맥, 긴 Claude 작업 돌리기 | Tailscale + SSH + tmux + caffeinate |
| B | 회사 노트북 → 집 맥, 가끔 야근 | Tailscale + SSH + tmux |
| C | 집 맥 → 회사 노트북 *(보통 막혀있음, §7 참조)* | 회사 정책상 보통 불가 |
| D | 항상 켜진 집 서버(미니PC/라즈베리파이)가 Claude 돌리고, 모든 기기는 거기 붙음 | 서버에 Tailscale + SSH + tmux (caffeinate 불필요) |
| E | 카페에서 Wi-Fi 끊겨도 세션이 그대로 살아있게 | mosh OR tmux + SSH 재접속 |

위로 갈수록 쉽고 아래로 갈수록 큼지막한 셋업이 필요. 본인 문제를 해결하는 가장
가벼운 걸 고르세요.

---

## 1. Tailscale: mesh VPN 백본

### 1.1 뭐임

[Tailscale](https://tailscale.com)은 **WireGuard 위에 만든 mesh VPN**입니다. 내 모든
기기에 깔고 같은 계정으로 로그인하면, 어디서든 모든 기기가 같은 LAN에 있는 것처럼
서로 이름으로 닿습니다.

### 1.2 왜 포트 포워딩 없이 동작하나

고전적인 문제부터: 집 기기들은 NAT 뒤에 있어서, 인터넷에서 들어오는 연결은
버려집니다 (자세한 원리는 [부록 C](#c2-nat-왜-집-컴퓨터에-외부에서-접속하기-어려운가)).
Tailscale은 이 문제를 통째로 우회합니다. 양쪽 기기가 Tailscale 코디네이션
서비스로 **나가는** 연결을 만듭니다. 그다음 NAT 트래버설 기법(STUN, hole
punching)으로 대부분은 두 기기가 **직접** 연결됩니다. 직접이 안 되면(일부
symmetric NAT, 회사 방화벽) **DERP 릴레이**가 TCP/443으로 폴백하는데, 웹
브라우징만 되는 네트워크면 다 통과합니다.

여기서 짚고 갈 만한 결과 두 가지:

- **CGNAT는 문제조차 안 됩니다.** 일부 ISP(모바일망, 아시아권 여러 광케이블
  사업자)는 공인 IP를 아예 안 줍니다. 거기선 포트 포워딩이 *불가능*합니다.
  Tailscale은 그래도 잘 도는데, 양쪽 다 들어오는 연결이 필요 없기 때문입니다.
- **회사 방화벽도 대체로 살아남습니다.** 회사 네트워크는 보통 나가는 HTTPS
  (443)만 허용하고 나머지는 다 막습니다. DERP 폴백이 정확히 그 포트를 탑니다.

공유기에서 포트를 열 일이 없고, "들어오는 연결" 문제가 통째로 사라집니다.

### 1.3 알아야 할 개념

| 개념 | 뜻 |
|---------|-----------|
| **Tailnet** | 본인의 사설 기기 네트워크 (계정/조직당 하나) |
| **Node** | tailnet 위 기기 |
| **Tailscale IP** | `100.x.x.x`, 노드마다 하나 받음. 안 바뀜. |
| **MagicDNS** | DNS 관리 없이 호스트 이름 (`home-mac`, `work-laptop`)으로 노드 접근 |
| **ACL** | `acl.hujson` 안 규칙. 누가 누구한테 어느 포트로 접근할 수 있는지 |
| **Tag** | 노드 라벨 (예: `tag:server`). ACL에서 사용 |
| **Node key expiry** | 인증 키에 만료가 있음 (기본 ~180일); 만료된 노드는 재인증 전까지 tailnet에서 빠짐 |
| **Subnet router** | LAN 대역을 광고하는 노드. 다른 기기들이 LAN-only 기기에 접근 가능 |
| **Exit node** | *모든* 트래픽을 라우팅하는 노드. 일반 VPN처럼 씀 |
| **Tailscale SSH** | tailnet 신원으로 SSH 인증 (키 관리 안 해도 됨) |
| **Funnel** | 노드의 포트를 Tailscale 통해 **공개 인터넷**에 노출 (HTTPS만) |
| **Serve** | 노드 포트를 tailnet *내부*에만 노출 (공개 인터넷 X) |

### 1.4 설치 & 연결

macOS에는 **설치 경로가 두 가지** 있고, 그 차이가 중요합니다:

1. **GUI 앱** (앱스토어 또는 별도 다운로드). 메뉴바 UI, 가장 쉬운 로그인,
   대부분이 결국 이걸 쓰게 됩니다. CLI도 들어있긴 한데 **PATH엔 없습니다** —
   바이너리가 앱 번들 안에 있고, *symlink를 통해서는 실행을 거부합니다*
   (`bundleIdentifier` 레지스트리 에러를 내며 죽음). 대신 alias를 쓰세요:

   ```sh
   # ~/.zshrc — 이 바이너리는 symlink로는 안 됩니다
   alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
   ```

2. **Homebrew** (`brew install tailscale`): 오픈소스 `tailscaled` 데몬 변종.
   CLI 중심, 메뉴바 앱 없음, 그리고 macOS에서 **Tailscale SSH 서버**를 돌릴 수
   있는 유일한 변종 (§1.5 참조). 셋업이 더 들지만 할 수 있는 게 더 많습니다.

어느 쪽이든, 로그인 후:

```sh
tailscale status
tailscale ip -4    # 본인 100.x.x.x 주소
```

iOS / Android: 앱스토어 / 플레이스토어, 로그인.

Linux:

```sh
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

이러면 같은 계정 기기들이 서로 보임. 시도:

```sh
ssh user@home-mac           # MagicDNS 사용
ssh user@100.x.x.x          # DNS 없이도 항상 됨
```

`ai remote doctor` (이 레포)는 macOS 설치 경로 두 가지 모두, GUI 앱 번들
바이너리까지 포함해서 감지합니다.

### 1.5 Tailscale SSH: authorized_keys 죽이기

Tailscale SSH를 켜면 서버가 인증을 Tailscale에 위임합니다:

```sh
sudo tailscale up --ssh
```

이제 tailnet에 로그인된 기기라면 어디서든 `ssh user@home-server`가 키 관리 없이
됩니다. 인증은 어드민 콘솔에서 짜는 ACL이 결정합니다. 여기에 Tailscale 계정 2FA를
얹으면(`check` ACL 규칙에 필요) 현실적으로 가장 튼튼합니다.

플랫폼 주의점: Tailscale SSH의 **서버 쪽**은 Linux와 macOS의
Homebrew/`tailscaled` 변종에서만 동작합니다 — macOS GUI 앱에서는 **안 됩니다**.
라즈베리파이나 리눅스 박스는 키 없는 경험을 온전히 누리고, GUI 앱 맥은 여전히
§2에서 설명하는 고전적인 `authorized_keys` (또는 비밀번호) SSH가 필요합니다.

기존 SSH를 같이 써도 됩니다.

### 1.6 노드 키 만료: 180일짜리 지뢰

모든 노드의 인증 키는 **만료됩니다**. 기본은 약 180일. 만료된 노드는 조용히
tailnet에서 빠지고, `tailscale ping <peer>`는
`peer's node key has expired`라고 하고, 그 머신에서 `tailscale status`를 치면
`Logged out.`이 나옵니다.

노트북·휴대폰한테는 이게 보안 기능입니다 — 재인증은 브라우저 한 번이면 끝.
하지만 **서버 역할 머신**(워크플로우 D의 집 서버)한테는 시한폭탄입니다: 몇 달
잘 돌다가 어느 날 갑자기 원격에서 안 닿습니다. 해결책 둘:

- 터졌을 때 재인증: 그 머신에서 `sudo tailscale up`을 치면 로그인 URL이
  출력됩니다. 로그인돼 있는 아무 브라우저에서나 열면 됩니다 (휴대폰도 OK).
- 예방: 어드민 콘솔 → Machines → 해당 노드 → **Disable key expiry**. 항상
  닿아있어야 하는 게 일인 모든 머신에 해두세요.

### 1.7 MagicDNS

켜두면 (어드민 콘솔 → DNS → Enable MagicDNS), 모든 노드를 `<hostname>` 그리고
`<hostname>.<tailnet>.ts.net`으로 접근 가능. 기기 이름 바꾸기:

```sh
sudo tailscale set --hostname home-mac
```

짧고 알아보기 쉬운 이름 추천. Tailscale은 따로 안 바꾸면 머신의 로컬 호스트네임
(`hostname` 명령 결과)을 그대로 쓰는데, 보통 길고 지저분합니다. 명시적으로 짧게
바꿔두면 `ssh home-mac` 같은 명령이 깔끔합니다.

### 1.8 Subnet router: LAN 기기에 접근

NAS, 프린터, Tailscale 안 깔린 기기 (`192.168.1.50`) 같은 게 집에 있으면, 집 맥에
Tailscale 깔고 서브넷 광고:

```sh
sudo tailscale up --advertise-routes=192.168.1.0/24
# 그다음 어드민 콘솔에서 광고된 라우트 승인.
```

이제 기차에서 휴대폰으로 `192.168.1.50`을 집에 있는 것처럼 접근 가능.

### 1.9 Exit node: 전체 트래픽 VPN

```sh
# Exit으로 쓸 노드에서:
sudo tailscale up --advertise-exit-node

# 어드민 콘솔에서 승인 후, 클라이언트에서:
sudo tailscale set --exit-node=<node-name> --exit-node-allow-lan-access
```

내 모든 트래픽이 특정 위치(지오락 우회용 집 IP 같은)에서 나가는 것처럼 보이게
하고 싶을 때 유용합니다. **회사 기기를 개인 exit node로 쓰지 마세요.** 신원 간
트래픽이 섞입니다. 바로 `ai`가 막으려는 문제입니다.

### 1.10 ACL: 최소 예시

어드민 콘솔에 JSON 정책 에디터가 있음. 기본 ACL은 "아무 노드나 아무 노드에 아무
포트로 접근 가능". 태그로 조이기:

```jsonc
{
  "tagOwners": {
    "tag:laptop":  ["autogroup:admin"],
    "tag:server":  ["autogroup:admin"]
  },
  "acls": [
    // 노트북이 서버에 SSH, http, https로 접근
    { "action": "accept", "src": ["tag:laptop"], "dst": ["tag:server:22,80,443"] }
  ],
  "ssh": [
    { "action": "check",
      "src":    ["autogroup:member"],
      "dst":    ["tag:server"],
      "users":  ["<your-username>", "root"] }
  ]
}
```

`check`는 "허용하되 N시간마다 SSO 재인증 묻기"입니다. 켜둘 만합니다.

### 1.11 Funnel & Serve: 진짜로 노출하고 싶을 때

- `tailscale serve`: 로컬 포트를 tailnet에 HTTPS로 공유. 공개 인터넷 X.
- `tailscale funnel`: 같은 거지만 Tailscale 엣지 통해 **공개 인터넷**에 노출.
  웹훅 수신, 데모용으로 좋습니다.

예시:

```sh
# localhost:3000을 tailnet에 HTTPS로 공유:
tailscale serve --bg 3000

# 인터넷 전체에 노출 (보안 경고 먼저 읽으세요):
tailscale funnel 3000
```

SSH나 Claude CLI는 funnel 하지 **마세요**. funnel은 공개 웹 엔드포인트용.

### 1.12 회사 노트북에 Tailscale

§7 먼저 읽으세요. 요약:

- 회사 노트북에 개인 Tailscale 계정 = 섀도우 IT. 대부분 보안 정책 위반.
- 일부 회사는 사내 Tailscale 테넌트를 운영함. 있다면 **그거** 쓰세요.
- 꼭 섞어야 한다면, *개인* 기기에 Tailscale 깔아서 다리 (subnet router) 역할
  시키고, 회사 기기는 개인 tailnet에서 빼두세요.

---

## 2. SSH: 만능 원격 셸

### 2.1 SSH가 뭐임

**Secure Shell.** TCP 프로토콜 (기본 22번 포트). 원격 머신에 암호화·인증된 터미널
을 줍니다. 파일도 옮김 (`scp`, `sftp`, `rsync`), 포트도 포워드, 임의의 TCP도
터널링.

네트워크 도구 딱 하나만 깊게 익힌다면 이거.

### 2.2 공개키 인증

비밀번호는 약한 데다 무차별 대입에 뚫립니다. 그래서 SSH는 **키 쌍**을 지원합니다:

- **개인키 (private key)**: 클라이언트(내 노트북, 휴대폰)에만 둠. 절대 안 나감.
- **공개키 (public key)**: 서버의 `~/.ssh/authorized_keys`에 추가.

로그인할 때는 개인키를 *보내지 않고*, 그 키를 가지고 있다는 것만 증명합니다.

요즘 방식으로 키 생성:

```sh
ssh-keygen -t ed25519 -C "you@example.com"
# 패스프레이즈: 꼭 거세요. ssh-agent가 캐시해줌.
```

`~/.ssh/id_ed25519` (개인키), `~/.ssh/id_ed25519.pub` (공개키)가 생김.

서버에 공개키 복사:

```sh
ssh-copy-id user@host
# 또는 수동:
cat ~/.ssh/id_ed25519.pub | ssh user@host 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'
```

현실적인 메모: **Tailscale 전용** 호스트(22번 포트가 공개 인터넷을 절대 안
보는)라면, macOS 기본값인 비밀번호 인증으로 새 기기에서 *첫* 접속을 하는 것도
괜찮습니다 — 로그인 비밀번호로 붙은 다음, 키를 설치하고 넘어가면 됩니다. 키가
목표인 건 변함없지만, 첫날부터 그것 때문에 막혀 있을 이유는 없다는 뜻입니다.
공개 노출이 있는 호스트에는 이런 여유가 없습니다 (§2.8 참조).

### 2.3 ssh-agent: 패스프레이즈 한 번만 치기

`ssh-agent`는 복호화된 개인키를 메모리에 들고 있는 백그라운드 프로세스입니다.
덕분에 세션당 패스프레이즈를 한 번만 치면 됩니다.

macOS에서:

```sh
ssh-add --apple-use-keychain ~/.ssh/id_ed25519   # 패스프레이즈를 키체인에 저장
```

`~/.ssh/config`:

```
Host *
    UseKeychain yes
    AddKeysToAgent yes
    IdentityFile ~/.ssh/id_ed25519
```

이러면 `ssh user@host`가 조용함. 비밀번호·패스프레이즈 묻는 거 없음.

### 2.4 `~/.ssh/config`: 내 주소록

긴 명령어 그만 치세요. 호스트를 정의:

```
Host home
    HostName home-mac
    User <your-username>
    Port 22
    ForwardAgent yes

Host work-laptop
    HostName work-laptop
    User <your-username>
    ProxyJump bastion.example.com

Host bastion.example.com
    User myname
    IdentityFile ~/.ssh/id_ed25519_work
```

이제 `ssh home`이면 끝입니다. `ProxyJump`는 점프 박스를 알아서 거쳐 갑니다.

### 2.5 macOS에서 SSH 켜기

`시스템 설정 → 일반 → 공유 → 원격 로그인` 체크. 특정 사용자에게 접근 허용.
확인:

```sh
sudo systemsetup -getremotelogin
ssh localhost
```

몸으로 배운 함정 세 가지:

- **본인이 켜려던 그 머신에서 켰는지 확인하세요.** 계정에 맥이 두 대 이상이면
  엉뚱한 쪽 토글을 켜는 게 놀랄 만큼 흔합니다. 그 박스에서 먼저 `hostname`을
  치고, *다른* 기기에서 확인하세요: `nc -z <host> 22`가 `succeeded`를 찍어야
  합니다.
- 요즘 macOS에서 **`systemsetup -setremotelogin on`은 Full Disk Access가
  필요**해서, 스크립트(그리고 원격에서 손 봐주는 사람)는 못 쓰는 경우가
  많습니다. 이건 FDA 없이 됩니다:
  `sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist`.
- **권한 없는 `lsof`는 root의 sshd 리스너를 못 봅니다.** 그래서 "켜져 있나?"
  체크가 거짓 음성이 날 수 있습니다. 그냥 TCP로 찔러보는 게
  (`nc -z 127.0.0.1 22`) 믿을 만한 테스트고, `ai remote doctor`가 정확히
  그렇게 합니다.

기본 포트 22. 22222 같은 큰 숫자로 바꾸면 인터넷 봇 스캔 노이즈가 줄긴 하는데,
이건 **SSH 포트가 공개 인터넷에 노출돼 있을 때만** 의미가 있습니다. Tailscale을
쓰면 포트 자체가 사설이라 바꿔봤자 얻는 게 없습니다.

### 2.6 포트 포워딩: 세 종류

SSH는 임의의 TCP를 터널링할 수 있음:

```sh
# 로컬 포워드: 내 localhost:8080 → 원격 타깃
ssh -L 8080:localhost:3000 home
# 내 노트북 localhost:8080을 치면 home의 3000번에 도달

# 리모트 포워드: 원격의 localhost:9000 → 내 타깃
ssh -R 9000:localhost:3000 home
# home에서 localhost:9000 치면 내 노트북 3000번에 도달

# 다이내믹 포워드 (SOCKS 프록시): 임의 트래픽을 home 통해 보냄
ssh -D 1080 home
# 브라우저 SOCKS 프록시를 localhost:1080으로 설정
```

요즘 셋업에선 Tailscale이 이걸 손으로 할 이유 대부분을 없애주지만, 알아둘
가치는 있음.

### 2.7 Mosh: 불안정한 망을 위한 SSH

[Mosh](https://mosh.org/)는 SSH 세션을 UDP 기반으로 대체합니다 (첫 로그인만 SSH로
합니다). IP가 바뀌든, 기기가 잠들다 깨든, 패킷이 좀 깨지든 세션이 버팁니다.
휴대폰 모바일 데이터에서 SSH 쓸 거면 일반 SSH보다 훨씬 낫습니다. 양쪽에
`brew install mosh` 하고, 방화벽은 UDP 60000–61000을 열어주면 됩니다.

모바일에선 Tailscale + mosh + tmux 조합이 제일 셉니다.

### 2.8 하드닝

SSH가 공개 인터넷에 노출된 경우 (즉 Tailscale 전용이 아닌 경우), 서버의
`/etc/ssh/sshd_config`:

```
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
```

리로드: macOS는 `sudo launchctl kickstart -k system/com.openssh.sshd`, Linux는
`sudo systemctl restart sshd`.

옵션: `fail2ban`으로 무차별 대입 IP 차단. Tailscale 전용 접근이면 이 짓 다
안 해도 됨 (포트가 공개 인터넷에 절대 안 나가있으니).

---

## 3. 세션 영속성: tmux와 그 대안들

### 3.1 tmux가 해결하는 문제

`ssh user@host` 들어가서 뭔가 오래 돌리면 연결이 깨지기 쉬움:

- 터미널 창 닫음 → 프로세스 죽음.
- 네트워크 끊김 → 프로세스 죽음.
- 노트북 잠 → 연결 끊김 → 프로세스 죽음.

tmux는 SSH 연결보다 *오래 사는* **서버 위 영속 세션**을 만들어줍니다. 거기에
attach해서 작업하다 detach하면, 셸과 그 안의 모든 게 계속 돌고 있습니다.

### 3.2 모델: 서버, 세션, 윈도우, 페인

```
tmux server  (사용자당 하나)
└── session  (예: "claude"): 내가 attach 하는 단위
    ├── window 0 (탭 같은 거)
    │   └── pane (윈도우 분할)
    │       └── pane
    └── window 1
```

세션 안에 윈도우 여러 개, 윈도우 안에 페인(분할) 여러 개.

### 3.3 Prefix 키

모든 tmux 명령은 **prefix** 키로 시작. 기본은 `Ctrl-b`. 많은 사람들이 `Ctrl-a`로
리바인드 (빠름, 단 screen이랑 충돌).

필수만:

| 키 | 동작 |
|------|--------|
| `tmux new -s work` | "work" 세션 생성 |
| `tmux ls` | 세션 목록 |
| `tmux attach -t work` | "work"에 attach |
| `tmux kill-session -t work` | 죽이기 |
| `prefix d` | Detach (세션은 계속 돔) |
| `prefix c` | 새 윈도우 |
| `prefix n` / `prefix p` | 다음/이전 윈도우 |
| `prefix ,` | 현재 윈도우 이름 바꾸기 |
| `prefix "` | 가로 분할 |
| `prefix %` | 세로 분할 |
| `prefix 화살표` | 페인 간 이동 |
| `prefix x` | 현재 페인 죽이기 |
| `prefix [` | 스크롤/복사 모드 (`q`로 나옴) |
| `prefix ?` | 모든 바인딩 목록 |

### 3.4 최소 `~/.tmux.conf`

```tmux
# 좀 더 편한 prefix
set -g prefix C-a
unbind C-b
bind C-a send-prefix

# 마우스 (스크롤, 리사이즈, 페인 클릭)
set -g mouse on

# 큰 히스토리
set -g history-limit 100000

# 인덱싱 (1부터)
set -g base-index 1
setw -g pane-base-index 1

# 재시작 없이 설정 리로드
bind r source-file ~/.tmux.conf \; display "reloaded"

# 분할 시 현재 디렉토리 유지
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"

# 24-bit 컬러 (Claude/Codex TUI가 제대로 보이려면 필요)
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:RGB"
```

### 3.5 SSH + tmux 패턴

"연결 끊겨도 살아남는 긴 작업"의 정석:

```sh
ssh home
tmux new -s claude
# tmux 안에서: 아무거나 (claude, codex, npm run dev 등) 실행
# detach: prefix-d
exit   # ssh 나옴; tmux는 계속 돔

# 나중에 어디서든:
ssh home
tmux attach -t claude
```

원샷도 가능:

```sh
ssh -t home 'tmux new -As claude'
# -t는 TTY 할당; new -As는 "있으면 attach, 없으면 생성"
```

### 3.6 사람들이 자주 놀라는 것들

- 호스트가 **재부팅**되면 tmux 세션은 다 사라집니다. 디스크에 저장되는 게 아니거든요.
  이게 곤란하면 [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect)를 쓰세요.
- 부모 터미널을 닫아도 tmux는 안 죽습니다. 애초에 그러라고 있는 거니까요.
- tmux 세션은 `tmux`를 실행한 **사용자**에 묶입니다. 권한 없이 다른 사용자 세션엔
  못 들어갑니다.
- tmux ≠ screen. 2010년대 `screen` 쓰던 분이라면, tmux가 그 후속이라고 보면 됩니다.

### 3.7 대안들: zellij, Herdr — 그리고 mosh의 자리

이제 멀티플렉서가 tmux 하나만 있는 게 아닙니다. 트레이드오프:

| | **tmux** | **zellij** | **Herdr** | **mosh** |
|---|---|---|---|---|
| 정체 | 멀티플렉서 | 현대적 멀티플렉서 | *에이전트 인지형* 멀티플렉서 | 로밍 트랜스포트 |
| 연결 끊김 생존 | ✓ | ✓ | ✓ (백그라운드 서버) | ✓ (로밍), 단 detach는 없음 |
| 휴대폰에서 SSH 너머로 사용 | ✓ | ✓ | ✓ | 그 자체가 SSH 대체 |
| 페인 *안*에 뭐가 있는지 앎 | ✗ | ✗ | ✓ — 에이전트 상태: blocked / working / done / idle | 해당 없음 |
| 성숙도 / 보급 | 15년+, 모든 배포판 저장소에 있음 | 안정적, 성장 중 | 신생 (2026), 빠르게 변화 중 | 10년+, 안정적 |
| 추가로 도는 것 | 없음 | 없음 | 자체 백그라운드 서버 | UDP 60000–61000 열려야 함 |
| 배우기 쉬움 | man 페이지 고고학 | 훌륭한 내장 힌트 | 사이드바 UI, 마우스 네이티브 | 해당 없음 |

- **[zellij](https://zellij.dev/)**: 더 친절한 기본값, 코드로 정의하는 레이아웃,
  내장 힌트. tmux 학습 곡선이 걸림돌이면 여기서 시작하세요. 라우터에 `ai zellij`
  래퍼가 들어있고, 원격 폴백은 여전히 tmux입니다.
- **[Herdr](https://herdr.dev/)**: tmux식 영속성에 *에이전트 시맨틱 상태*를
  얹은 것. 페인에 claude/codex가 돌고 있다는 걸 알고, 모든 에이전트를
  🔴 blocked / 🟡 working / 🔵 done / 🟢 idle로 요약해줍니다. 그래서 휴대폰에서도
  에이전트 다섯 개 중 진짜 입력이 필요한 게 어느 쪽인지 한눈에 보입니다.
  claude, codex를 비롯한 대부분의 에이전트 CLI 공식 연동; Rust 바이너리 하나;
  스크립트 가능 (`herdr session list --json`). 트레이드오프: 신생 프로젝트라는
  점, 자체 백그라운드 서버를 돌린다는 점 (믿고 업데이트해야 할 게 하나 더),
  기본 prefix `ctrl+b`가 tmux 손버릇과 충돌한다는 점, 어디에도 기본 설치돼
  있지 않다는 점.
- **mosh는 경쟁자가 아닙니다** — 멀티플렉서가 아니라 *네트워크 트랜스포트*를
  대체합니다. mosh + 위 셋 중 아무거나가 모바일 최강 조합입니다.

추천: 원격 영속성의 **기본 레이어는 tmux로** 유지하세요 — 앞으로 만질 모든
서버의 최소 공통분모이고, (이 문서를 포함한) 모든 가이드가 tmux를 전제합니다.
**동시에 에이전트 여러 개를 일상적으로 굴려서** "어느 페인이 날 기다리지?"
문제가 실감 나기 시작하면 그때 Herdr를 잡으세요. 둘은 겹치지만 같지는 않은
문제를 풉니다. 워크플로우는 tmux 모양으로 두고 호스트에서 Herdr를 시험해보는
것도 아무 문제 없습니다.

`ai remote doctor`는 셋 다 (tmux, zellij, herdr) 세션을 보고합니다.

---

## 4. 맥 잠 못 자게 하기

### 4.1 macOS 잠자기 종류 (간단히)

- **디스플레이 잠**: 화면만 꺼짐, 머신은 동작 중.
- **시스템 잠** ("sleep"): RAM은 유지, CPU 정지, 네트워크 거의 꺼짐. 기존 TCP
  연결은 죽음.
- **Hibernation / safe sleep**: RAM을 디스크에 쓰고 완전히 꺼짐.
- **덮개 닫음 잠 (MacBook)**: 외부 디스플레이 + 전원 + 키보드/마우스가 연결돼있지
  않으면 (clamshell 모드) 덮개를 닫으면 *강제로* 잠.

잠든 맥은 tmux 세션을 못 돌립니다. CPU가 아예 명령을 실행하지 않으니까요.

### 4.2 `caffeinate`: 쉬운 방법

내장 명령어. `man caffeinate`에서:

| 플래그 | 막아주는 것 |
|------|----------|
| `-d` | 디스플레이 잠 |
| `-i` | 시스템 idle 잠 |
| `-m` | 디스크 idle 잠 |
| `-s` | 시스템 잠 (AC 전원일 때만) |
| `-u` | 사용자 활동 선언 (기본 5초) |
| `-w PID` | PID 종료될 때까지 잠 차단 |
| `-t SEC` | SEC초 동안 잠 차단 |

흔한 레시피:

```sh
# 명령어 도는 동안만 잠 차단, 끝나면 풀림:
caffeinate -i ./long-job.sh

# 무한히 (Ctrl-C 칠 때까지):
caffeinate -dims

# 분리 실행 — 띄운 터미널을 닫아도 살아남음:
nohup caffeinate -is >/dev/null 2>&1 &

# 특정 프로세스 (예: tmux 서버)가 살아있는 동안 잠 차단:
caffeinate -i -w $(pgrep -x tmux | head -1)
```

분리 실행 형태가 바로 "지금 집 나가야 하는데 터미널 창이랑 같이 세션이 죽으면
안 될 때" 쓰는 겁니다. 잘 걸렸는지는 `pmset -g assertions`로 확인하세요
(`caffeinate`가 잡고 있는 `PreventUserIdleSystemSleep`이 보여야 함).

### 4.3 `pmset`: 더 센 망치

`pmset`은 전원 관리 설정을 시스템 전체로 읽고 바꿈. 자주 쓰는 것들:

```sh
pmset -g                          # 현재 설정 보기
pmset -g assertions               # 지금 잠 막고 있는 게 뭔지
pmset -g batt                     # 배터리/전원 상태

# AC 전원일 때 시스템 잠 끄기 (sudo 필요):
sudo pmset -c sleep 0

# AC에서 30분 idle 후 잠 다시 켜기:
sudo pmset -c sleep 30
```

`pmset` 설정은 재부팅해도 유지됩니다. AC 전원에서는 절대 안 자는 *서버 같은* 맥을
원하면 이걸 쓰고, 딱 한 번 특정 작업 동안만 막고 싶으면 `caffeinate`를 쓰세요.

### 4.4 MacBook 덮개 닫음 문제

기본적으로 덮개 닫으면 `caffeinate`나 `pmset` 무시하고 강제로 잠. 의도된 예외는
**clamshell 모드**: 외부 전원 + 디스플레이 + 키보드/마우스 연결돼있으면 덮개 닫아도
켜져 있음.

`sudo pmset -a disablesleep 1` 같은 꼼수로 다 우회할 수도 있지만 권하진 않습니다.
가방 안에서 노트북이 뜨거워지고 배터리도 훅 빠집니다. 더 나은 선택지는:

- 덮개 열어둔다 (스탠드 써서).
- 데스크 셋업 + clamshell 모드.
- 긴 작업은 덮개 없는 데스크탑/미니PC/라즈베리파이로 옮긴다.

### 4.5 Power Nap & Wake on LAN

- **Power Nap**은 잠자는 동안 백그라운드 작업 (Time Machine, Mail) 하게 해줌.
  임의 사용자 프로세스를 살려주지 *않음*. 의존하지 마세요.
- **Wake on Network access**는 특수 패킷 받으면 맥이 깨어남. `ssh` 들어가면 맥이
  깨어나도록 할 때 유용. 단 같은 LAN에서만 동작 (인터넷 너머에서 깨우려면
  Wake-on-WAN 프록시 따로 셋업).

### 4.6 GUI 대안: Amphetamine

메뉴바 UI로 조건 ("화면 미러링 중일 때 잠 안 자기", "밤 11시까지 잠 안 자기") 걸고
싶으면 [Amphetamine](https://apps.apple.com/app/amphetamine/id937984704).
`caffeinate`와 같은 일을 하면서 규칙 UI를 씌운 거라고 보면 됩니다. CLI가 하는 건
다 되지만, 한 번 쓰고 말 거면 CLI가 빠릅니다.

---

## 5. 휴대폰 클라이언트

### 5.1 iOS

| 앱 | 비고 |
|-----|------|
| **Blink Shell** | 유료, 그리고 가장 강력한 선택지. mosh 내장, 키보드 지원, 스크립트 가능. |
| **Termius** | 무료 티어 됨; 키 클라우드 동기화; 크로스플랫폼. 단, 키가 자기네 클라우드에 저장될 수 있음. |
| **a-Shell** | 무료, 오픈소스. 한계 있지만 빠른 SSH엔 유용. |
| **Tailscale (iOS 앱)** | 휴대폰을 tailnet에 올리려면 필수. 항상 켜두는 토글 잘 됨. |

### 5.2 Android

| 앱 | 비고 |
|-----|------|
| **Termux** | 플레이스토어/F-Droid 앱 안에 진짜 리눅스 환경. `openssh`, `mosh`, `tmux` 깔고 네이티브로 씀. |
| **JuiceSSH** | GUI 친화, 클래식. |
| **Termius** | iOS와 동일. |
| **Tailscale (Android 앱)** | iOS와 동일 역할. |

### 5.3 휴대폰 키 관리

키를 **휴대폰에서** 만들고, 공개키만 서버로 복사하고, 개인키는 휴대폰에만
두세요. 반대로, 노트북 개인키를 클라우드 동기화되는 메모 앱에 붙여넣어 휴대폰으로
옮기는 건 절대 하지 마세요.

휴대폰을 잃어버려도, 서버 `authorized_keys`에서 그 휴대폰 공개키만 지우면(Tailscale
SSH면 tailnet에서 그 기기만 빼면) 다른 기기는 건드리지 않고 정리됩니다.

### 5.4 "휴대폰 키보드 안 좋잖아" 현실

30초 넘게 칠 일이면 블루투스 키보드 하나로 휴대폰이 제법 쓸 만한 미니 노트북이
됩니다. 자주 할 거면 작은 접이식 키보드 하나 가방에 넣어둘 만합니다.

---

## 6. 실전 통합 워크플로우

### 6.1 워크플로우 A: 휴대폰 → 집 맥, 긴 Claude 작업

**집 맥에서 1회 셋업:**

```sh
# 1. Tailscale 설치 (GUI 앱 또는 brew, §1.4) + tmux
brew install tmux
# GUI 앱: 메뉴바에서 로그인. brew 변종: sudo tailscale up
sudo tailscale set --hostname home-mac

# 2. 원격 로그인 켜기 (시스템 설정 → 일반 → 공유)
#    ...반드시 "이" 머신에서 — 맥이 여러 대면 먼저 `hostname` 치고,
#    다른 기기에서 확인: nc -z home-mac 22
# 3. AC 전원일 때 무한히 잠 안 자게
sudo pmset -c sleep 0 disksleep 0

# 4. (선택) 로그인 시 장수 tmux 세션을 launchd로 띄우거나 그냥 수동으로
tmux new -d -s claude
```

**휴대폰 1회 셋업:**

1. Tailscale 깔고 같은 계정 로그인.
2. Blink Shell (Android면 Termius / Termux) 설치.
3. 첫 접속은 맥 로그인 비밀번호로 해도 됩니다 (Tailscale 전용 호스트라면 괜찮음,
   §2.2). 그다음 SSH 클라이언트에서 키를 만들어 서버에 설치하면 이후로는 키로
   로그인.

**일상 사용:**

```sh
# 휴대폰에서:
ssh $USER@home-mac
tmux attach -t claude
# 작업; prefix-d로 detach
exit
```

지하철 터널에서 연결이 끊겼다면, 다시 붙어서 `tmux attach -t claude`만 치면 그대로
복귀합니다. *로밍* (Wi-Fi → LTE)까지 버티게 하려면 mosh를 얹으세요:

```sh
mosh $USER@home-mac -- tmux new -As claude
```

급하게 나가야 한다면? 진짜 중요한 건 딱 두 가지: **전원 연결, 덮개 열기**
(§4.4) — 그리고 `pmset` 셋업을 아직 안 했다면 분리 실행
`nohup caffeinate -is >/dev/null 2>&1 &` 하나.

### 6.2 워크플로우 B: 회사 노트북 → 집 맥, 야근

회사 노트북에 Tailscale 깔 수 있으면 (§7 확인) A와 동일. 안 되면:

- 휴대폰을 Tailscale 단 핫스팟으로 써서 회사 노트북을 셀룰러로. 회사 노트북은
  휴대폰을 통해 셀룰러에 있는 거고, 휴대폰을 개인 tailnet에 올려도 회사 노트북이
  tailnet에 있는 건 아님. (홉이 한 번 더 필요)
- 더 쉬움: 휴대폰 자체로 SSH 들어가고 회사 노트북은 그냥 보기용.
- 가장 깔끔: 별도 물리 머신. 워크플로우 D.

### 6.3 워크플로우 C: 집 → 회사 노트북

대부분의 회사가 일부러 막아두고, 우회는 해고 사유입니다. **하지 마세요.**
원격 근무가 공식적으로 허용이면 회사가 수단을 줍니다(회사 VPN, 가상 데스크탑).
그걸 쓰세요.

### 6.4 워크플로우 D: 항상 켜진 집 서버

가장 견고한 셋업. 작은 미니PC나 라즈베리파이를 24시간 켜둠:

- Tailscale, tmux, sshd 돌림.
- Claude / Codex 세션이 거기서 삶.
- 안 잠 (서버니까).
- 내 노트북이 열려있는지에 안 의존.

내 맥북, 회사 노트북, 휴대폰은 다 *클라이언트*. 서버의 tmux 세션에 붙음. 집 맥은
선택사항이 됨.

대략적 셋업:

```sh
# 서버 (Linux):
sudo apt install tmux openssh-server
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh --hostname home-server
# 리눅스는 Tailscale SSH 서버가 온전히 됨 (§1.5): 키 관리 자체가 없음.

# 리눅스 방식으로 Claude Code / Codex 설치, 그 다음
# 그걸 들고 있을 tmux 세션 생성:
tmux new -d -s ai 'ai claude personal'  # ai 라우터 셋업된 경우
```

그다음 어드민 콘솔에서 이 노드의 **키 만료를 꺼두세요** (§1.6). 180일 뒤에
조용히 tailnet에서 빠지는 서버라면 만든 의미가 없습니다.

어느 기기에서든:

```sh
ssh $USER@home-server
tmux attach -t ai
```

하드웨어 관련, 몸으로 배운 것들:

- **파이 전원은 제대로 주세요.** 라즈베리파이 4는 공식 5V/3A USB-C 어댑터를
  원합니다. 노트북용 USB-C PD 충전기는 *되는 것처럼 보이다가* 부하 걸리면
  전압이 훅 떨어져서 보드를 하드 리셋시킵니다 — 심지어 저전압 플래그도 안 남기는
  경우가 많고요 (`vcgencmd get_throttled`가 죽기 직전까지 `0x0`을 찍을 수 있음).
  증상: 불은 들어와 있는데 몇 분마다 재부팅 루프. 항상 켜져 있어야 할 박스가
  항상 켜져 있지 않다면, 소프트웨어보다 전원부터 의심하세요.
- **영속 로그를 켜두세요.** 사후에 크래시를 진단할 수 있게:
  `sudo mkdir -p /var/log/journal && sudo systemctl restart systemd-journald`,
  그다음 사고가 나면 `last -x reboot`와 `journalctl -b -1 -e`.

트레이드오프: 추가 하드웨어 ($), 관리 박스 +1 (보안 패치), 성능 한계 (Pi는 채팅엔
괜찮은데 거대 에이전트 부하엔 빡셀 수 있음).

### 6.5 워크플로우 E: 길에서 불안정한 망

```sh
mosh $USER@home-server -- tmux new -As road
```

네트워크 끊김·IP 변경·suspend/resume은 mosh가, 프로세스 영속성은 tmux가 맡습니다.
둘을 합치면 노트북 닫고, 터널 들어가고, Wi-Fi → LTE 갈아타고, 20분 뒤 카페에서
열어도 세션이 그대로 있습니다.

---

## 7. 보안 & 회사 정책

### 7.1 양보 못 하는 것들

- SSH 키엔 **패스프레이즈**. `ssh-agent` / 키체인이 캐시.
- Tailscale 계정에 2FA.
- 이 tailnet에 있는 어떤 거든 접근 권한을 주는 모든 클라우드 계정에 2FA (GitHub,
  Google 등).
- 개인용 vs 회사용 Tailscale 계정 분리. 섞지 마세요.
- 공개 인터넷에서 접근 가능한 호스트는 비밀번호 SSH 끄기.

### 7.2 Tailscale 위생

- ACL로 누가 뭐에 접근할지 제한. 기본 전체 허용은 편하지만 위험.
- 고가치 박스엔 `tailscale ssh`의 `check` 모드 쓰기.
- SSH나 셸 엔드포인트를 `funnel`하지 마세요.
- 주기적으로 `tailscale status` 돌려서 더 이상 안 갖고 있는 기기 빼기.
- 기기 분실 시 머신 인증 키 회전 (어드민 콘솔 → expire key).
- 키 만료 끄기는 서버 역할 머신에**만** (§1.6); 노트북·휴대폰은 켜둔 채로.

### 7.3 회사 기기: 허락 받으세요

흔한 회사 정책을 풀어쓰면:

- **개인 VPN 소프트웨어 금지.** Tailscale 포함.
- **승인 안 된 호스트로 나가는 SSH 금지.** 일부 네트워크는 22번 outbound를 막음.
- **회사 비밀이 있는 집 머신으로 원격 접근 금지.** 기술적으로 되더라도 유출
  리스크.

보안/IT 팀에 서면으로 물어보세요. "내 개인 노트북에 Tailscale"엔 대체로 *예*,
회사 노트북엔 *경우에 따라 다름*이라고들 하고, 그 대화를 나눴다는 사실 자체가
나중에 곤란해질 일을 막아줍니다.

VPN에 관대한 사무실에 대한 메모: "여기 다들 이미 VPN 쓰는데요"는 서면 질문을
*하기 쉽게* 만들어줄 뿐, 불필요하게 만들지는 않습니다. 분위기상 용인은 정책이
아니고, 뭔가 잘못되는 바로 그 순간에 증발하며, 그날이 오면 서면으로 물어봤던
사람과 안 물어봤던 사람의 처지는 다릅니다. 반대 면도 기억하세요: 회사가 관리하는
기기가 개인 tailnet에 올라오면 내 개인 머신들이 그 기기에 *보입니다*. 허락을
받았더라도, 태그로 범위를 좁힌 ACL (§1.10)로 회사 기기가 필요한 것에만 닿게
하는 편이 낫습니다.

### 7.4 `ai` 라우터와 보안

[ai-session-router](../../README.md)의 존재 이유는 신원 섞임 방지. 원격 접근은
위협 모델을 이렇게 바꿉니다:

- 휴대폰이 털리고 공격자가 SSH 잠금을 풀 수 있으면, 우리집 tailnet에 닿음.
- 따라서: SSH 키 패스프레이즈 + 휴대폰 생체 잠금 + 백그라운드 갔다 오면 재인증
  요구하는 SSH 클라이언트 (Blink, Termius 둘 다 지원).
- AI 도구는 로그를 자기가 돌아간 호스트의 **워크스페이스**에 씁니다. 즉 서버에
  남지 휴대폰엔 안 남습니다. 이게 의도한 올바른 동작입니다.

### 7.5 기기 털린 거 같으면

1. Tailscale 어드민 콘솔에서 그 기기 키 만료. 즉시 tailnet에서 빠짐.
2. 그 기기에 있던 SSH 공개키 전부 회전 (모든 서버 `authorized_keys`에서 교체).
3. 디스크에 있었을 API 토큰 회전 (Claude / Codex 계정 루트; `~/.claude-*`,
   `~/.codex-*`).
4. 회사 자격증명이 있었으면 보안팀에 알리세요. 1번보다 *먼저*.

---

## 8. 트러블슈팅

### 8.1 "Connection refused"

TCP 포트에 닿긴 했는데 듣고 있는 게 없음. 서비스가 안 떠있거나 포트가 틀림.
서버에서:

```sh
# sshd가 도나?
sudo launchctl list | grep ssh    # macOS
sudo systemctl status sshd        # Linux

# Listen 중이야?
sudo lsof -iTCP:22 -sTCP:LISTEN
```

### 8.2 "Connection timed out"

나랑 서버 사이 어딘가가 패킷을 버리고 있음: NAT, 방화벽, 라우팅. Tailscale이면
양쪽에서:

```sh
tailscale status               # 둘 다 온라인이야?
tailscale ping <peer>          # 직접 연결돼? DERP로 폴백돼도 동작은 함, 단지 느림
```

### 8.3 "Permission denied (publickey)"

서버가 키 거절. 진단 SSH:

```sh
ssh -vvv user@host  2>&1 | grep -E 'identity|publickey|Offering|Accepted|denied'
```

흔한 원인:

- 공개키가 서버 `~/.ssh/authorized_keys`에 없음.
- `~/.ssh`나 `authorized_keys` 권한이 너무 헐거움 (`700`, `600` 필수).
- 서버 설정이 pubkey auth 꺼둠 (`/etc/ssh/sshd_config` 확인).
- 사용자 잘못 (다른 계정용으로 키 등록했는데 `ssh root@host`).

### 8.4 "tmux 세션이 사라짐"

두 가지 주요 원인:

- 호스트가 재부팅됨 (예: 맥이 깊이 자다가 재시작). tmux 세션은 메모리에만 있음.
- 다른 사용자로 로그인함. `tmux ls`는 현재 사용자 세션만 보여줌.

완화: 데스크탑 맥엔 `pmset -c sleep 0`; 또는 진짜 서버; 또는 재시작 너머 세션
내용까지 살려야 하는 드문 경우엔
[tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect).

### 8.5 "Tailscale은 online인데 피어에 못 닿음"

```sh
tailscale status               # 피어가 online이야?
tailscale ping <peer>          # 레이턴시? direct vs DERP?
tailscale netcheck             # 로컬 네트워크 진단
```

`netcheck`에서 443 빼고 다 막혀있다고 나오면 본인이 엄격한 방화벽 뒤에 있는
거임. DERP 폴백이 동작은 하지만 느릴 거임.

### 8.6 "peer's node key has expired"

인증 키가 수명을 다해서 노드가 tailnet에서 빠진 겁니다 (§1.6). 그 머신에서
`sudo tailscale up`을 치면 로그인 URL이 출력됨 — 로그인돼 있는 아무 브라우저
(휴대폰 포함)에서 열어 승인하면 됩니다. **URL이 최신인지 주의하세요**: 인증 도중
머신이 재부팅되면 진행 중이던 로그인이 리셋되고 옛 URL은 조용히 무효가 됩니다.
URL은 항상 *가장 최근* `tailscale status` / `tailscale up` 출력에서 가져오세요.
그다음 서버 역할 노드는 키 만료를 꺼서 재발을 막으세요.

### 8.7 "tailscale: command not found (앱은 깔려있는데)"

macOS GUI 앱을 쓰고 있는 겁니다 (§1.4). CLI는 번들 안
`/Applications/Tailscale.app/Contents/MacOS/Tailscale`에 있고, 반드시 그 실제
경로로 실행하거나 셸 alias를 거쳐야 합니다 — **symlink는 안 됩니다**
(바이너리가 `bundleIdentifier` 레지스트리 에러를 내며 죽음). `ai remote doctor`는
이 위치를 알고 있어서 설치된 것으로 보고합니다.

### 8.8 "원격 로그인 켰는데 22번 포트가 여전히 닫혀있음"

거의 항상: 지금 찔러보고 있는 머신이 아니라 **다른 머신에서** 켠 겁니다
(맥 여러 대인 집에선 아주 흔한 일). 토글을 켠 곳에서 `hostname`을 치고 비교하세요.
`systemsetup`이 Full Disk Access 타령을 할 때, 올바른 머신의 셸에서 켜는 법:
`sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist`.

### 8.9 "MagicDNS가 안 풀림"

```sh
scutil --dns | grep -A2 'resolver #1'   # macOS: 100.100.100.100이 DNS 서버야?
tailscale set --accept-dns=true         # DNS 수락 켜두기
```

DNS 덮어쓰는 VPN 클라이언트가 끼어들 수 있음.

### 8.10 "SSH가 몇 분 idle하면 끊김"

클라이언트 `~/.ssh/config`:

```
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

또는 서버 `sshd_config`에 `ClientAliveInterval 60`.

### 8.11 "맥이 그래도 잠"

지금 잠 못 자게 막고 있는 게 뭐 있나:

```sh
pmset -g assertions
```

`PreventUserIdleSystemSleep`을 `caffeinate`나 본인 프로세스가 잡고 있어야 됨.
없으면 caffeinate가 종료됐거나 아예 안 띄워진 거.

### 8.12 "라즈베리파이가 재부팅 루프 / 부하 걸리면 죽음"

불은 들어와 있는데 몇 분마다 네트워크에서 빠지고 `uptime`이 리셋된다면:
소프트웨어보다 **전원**을 먼저 의심하세요. 노트북 USB-C 충전기와 싸구려
어댑터는 부하 걸리면 전압이 훅 떨어져서 보드를 하드 리셋시키는데, 저전압
플래그조차 안 남기는 경우가 많습니다 (`vcgencmd get_throttled` → `0x0`).
공식 5V/3A 어댑터로 바꾸세요. 그리고 *다음* 크래시가 증거를 남기게 영속
journald를 켜두세요 (§6.4): `last -x reboot`로 재부팅 이력을,
`journalctl -b -1 -e`로 직전 부팅의 마지막 순간을 볼 수 있습니다.

---

## 9. `ai` 라우터와의 통합

이 레포의 `ai` 명령어는 이미 계정/워크스페이스/브라우저를 분리해줍니다. 원격 접근은
그 위에 *어느 호스트인지*라는 축을 하나 더 얹을 뿐, 각 축은 서로 독립적입니다.

### 9.1 SSH 너머로 `ai` 돌리기

```sh
ssh home
tmux new -As claude
ai claude personal              # 맥 앞에 앉아있는 거랑 정확히 동일
```

라우터 로그는 늘 그렇듯 `<workspace>/.ai-logs/...`, 즉 *ai가 돌아간 호스트*에 남습니다.
집 맥에 남지 휴대폰엔 안 남는다는 뜻이고, 이게 의도한 동작입니다.

### 9.2 `ai remote doctor`

이 명령은 원격 접근 상태를 보고만 함 (절대 설정 변경 X):

- Tailscale 상태 / IP / 온라인 피어 — CLI가 앱 번들 안에 숨어있는 macOS
  **GUI 앱 설치** (§8.7)까지 포함
- sshd가 listen 중? — 권한 없는 `lsof`는 root의 리스너를 못 보니 (§2.5) TCP
  연결 찔러보기를 폴백으로 씀
- tmux, zellij, **그리고 herdr** 세션 있어?
- Hostname (지금 있는 호스트가 생각하는 그 호스트가 맞는지 — §8.8이 괜히 있는
  게 아닙니다)

변경 후 검증 시 돌리세요 (예: `sudo tailscale up --ssh` 다음).

### 9.3 깔끔한 셸 훅

**클라이언트** 쪽 (노트북 / 휴대폰 Termux) `.zshrc` 스니펫 유용:

```zsh
# 한 명령으로 집의 정해진 tmux 세션에 안착
home-ai() {
  ssh -t home "tmux new -As ai 'cd ~/dev/personal && ai claude personal'"
}
```

이제 `home-ai`만 치면 어디서든 집 맥에 들어가 알맞은 계정/워크스페이스로
Claude tmux 세션에 바로 붙습니다.

### 9.4 `ai`가 의도적으로 안 하는 것들

- Tailscale 설정 **안 함** (토큰 저장도, `tailscale up` 호출도 X).
- `ai claude/codex`가 tmux를 띄워주지도 **않음**. 그건 본인 셸 책임.
- 자격증명을 네트워크로 보내지 **않음**. 계정 인증은 각 계정의 config 루트가 있는
  곳, `ai`를 돌리는 호스트에 그대로 머묾.

일부러 그어둔 경계입니다. 라우터가 VPN 셋업이나 잠자기 정책, 원격 프로세스 관리까지
떠맡을 자리는 아닙니다. 그런 건 이 문서에서 다룬 도구들이 하고, `ai`는 신원 라우팅만 합니다.

---

## 부록 A: 빠른 명령어 치트시트

```sh
# SSH 키
ssh-keygen -t ed25519 -C "you@example.com"
ssh-copy-id user@host
ssh-add --apple-use-keychain ~/.ssh/id_ed25519

# Tailscale
brew install tailscale            # 또는 GUI 앱; GUI 앱이면 ~/.zshrc에:
alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"  # GUI 앱 전용
sudo tailscale up --ssh
tailscale status
tailscale ip -4
tailscale ping <peer>
tailscale netcheck
# 어드민 콘솔: 서버 역할 노드는 키 만료 끄기 (§1.6)

# tmux
tmux new -As ai
tmux ls
tmux attach -t ai
# prefix-d로 detach

# herdr (에이전트 인지형 대안, §3.7)
herdr session list

# 잠 제어
caffeinate -dims          # Ctrl-C 칠 때까지 모든 잠 차단
nohup caffeinate -is >/dev/null 2>&1 &   # 분리 실행; 터미널 닫아도 살아남음
caffeinate -i -t 3600     # 1시간 동안 idle 잠 차단
sudo pmset -c sleep 0     # AC 전원에선 절대 안 잠 (영구)
pmset -g assertions       # 지금 잠 막고 있는 게 뭐야

# 진단
ai remote doctor          # 이 레포 명령
ssh -vvv user@host        # verbose SSH
sudo lsof -iTCP -sTCP:LISTEN
```

## 부록 B: 추천 자료

- `man ssh`, `man ssh_config`, `man sshd_config`
- `man tmux` (길지만 유일한 공식 출처)
- `man caffeinate`, `man pmset`
- [Tailscale 공식 문서](https://tailscale.com/kb/)
- [Herdr 문서](https://herdr.dev/), [zellij 문서](https://zellij.dev/) (멀티플렉서 대안, §3.7)
- [WireGuard 백서](https://www.wireguard.com/papers/wireguard.pdf) (암호학 궁금하면)
- [mosh 논문](https://mosh.org/mosh-paper.pdf) (모바일 SSH는 왜 UDP여야 하나)
- 이 레포의 [ARCHITECTURE.md](../en/ARCHITECTURE.md), [COMMANDS.md](../en/COMMANDS.md),
  [PORTABILITY.md](../en/PORTABILITY.md)

## 부록 C: 네트워크 기초 & pre-Tailscale 도구 상자

여기 있는 건 전부 예전엔 이 가이드의 1장이었습니다. 이제 뭔가를 *하기 위해*
알아야 하는 건 아닙니다 — Tailscale이 이 문제들을 흡수하니까요 — 하지만 시스템이
마법처럼 보이지 않으려면, 그리고 언젠가 뭔가 깨진 날 디버깅하려면 한 번은 읽어둘
가치가 있습니다.

### C.1 IP 주소: 공인 vs 사설

네트워크에 있는 모든 기기는 **IP 주소**가 있습니다. 두 종류만 알면 됨:

- **공인 IP (Public IP)**: 전 세계에서 유일. 인터넷 어디서든 도달 가능. ISP가
  집 공유기에 하나 부여 (또는 0개, 아래 CGNAT 참조).
- **사설 IP (Private IP)**: 우리 집 내부 네트워크에서만 유효. 흔한 대역:
  - `10.0.0.0/8`
  - `172.16.0.0/12`
  - `192.168.0.0/16`
  - `100.64.0.0/10` (통신사 NAT 대역이자 Tailscale 대역)

집 Wi-Fi에 붙은 노트북은 보통 `192.168.x.x`를 받습니다. 이 주소는 집 밖에서
보면 아무 의미가 없습니다.

### C.2 NAT: 왜 집 컴퓨터에 외부에서 접속하기 어려운가

집에는 공인 IP 하나(ISP가 줌)와 그 뒤로 여러 기기가 있습니다. 공유기가 **NAT**
(Network Address Translation)을 합니다: 나가는 트래픽은 공인 IP에서 나가는 것처럼
바꾸고, 들어오는 응답은 기억해둔 포트 매핑으로 알맞은 내부 기기에 돌려줌.

그래서 이렇게 됩니다: **나가는 연결은 되는데, 들어오는 연결은 안 됩니다.** 인터넷
어딘가의 서버가 `너희집공인IP`로 패킷을 보내도 공유기는 이걸 어느 기기한테
넘겨야 할지 모르니 그냥 버립니다.

"기차에서 그냥 SSH 쳐서 집 컴퓨터 들어가야지"가 아무 설정 없이는 안 되는 게 이
때문이고 — Tailscale의 나가는-연결만 쓰는 설계 (§1.2)가 이 문제를 증발시키는
것도 이 때문입니다.

**CGNAT**, 더 가혹한 변종: 일부 ISP는 유일한 공인 IP조차 안 줍니다. *통신사
차원의* NAT 뒤에 묶어두죠. 이러면 포트 포워딩은 그냥 불가능합니다. mesh VPN은
그래도 잘 도는데, 양쪽 다 바깥으로 나가서 중간에서 만나기 때문입니다.

### C.3 포트: 주소의 나머지 절반

IP가 *어떤 기기*인지 정한다면, **포트** (0–65535)는 *그 기기 안 어떤 프로그램*인지
정합니다. 예:

| 포트 | 서비스 |
|------|--------|
| 22 | SSH |
| 80 | HTTP |
| 443 | HTTPS |
| 5900 | VNC |
| 3000 | 흔한 개발 서버 |

한 프로그램이 포트에서 **listen**하고, 다른 프로그램이 `(ip, 포트)` 쌍으로
**connect**합니다. 그 포트를 듣는 프로그램이 없으면 연결은 그 자리에서 거부됩니다.

### C.4 pre-Tailscale 도구 상자 (TL;DR)

mesh VPN 전에는 집 머신을 노출하려면 이 중 하나였습니다. 지금도 다 됩니다.
쓸 일은 거의 확실히 없겠지만, 지도는 이렇습니다:

| 방법 | 아이디어 | 왜 안 쓰는 게 좋은가 |
|--------|----------|-------------------------------|
| **포트 포워딩 + DDNS** | 공유기 규칙 "공인 :22 → 192.168.1.42:22" + 바뀌는 집 IP를 따라가는 `me.duckdns.org` | 공유기 접근 필요; CGNAT면 아예 불가; SSH 포트가 공개 인터넷에 앉아 봇들에게 24시간 두들겨 맞음 |
| **VPS로 reverse SSH tunnel** | 집 박스가 빌린 VPS로 나가는 연결을 유지; 나는 VPS에 SSH 들어가면 집으로 포워딩됨 | 돈 내고, 패치하고, 지켜야 할 VPS가 하나 생김 — 영원히 |
| **Cloudflare Tunnel / ngrok / frp** | 같은 reverse tunnel 아이디어의 제품판 | 벤더 종속, 서비스마다 설정, 조건 붙은 무료 티어 |
| **고전 VPN (OpenVPN / 수동 WireGuard / IPsec)** | 외부에서 집 LAN에 정식 멤버로 합류 | 방향은 맞음 — Tailscale이 곧 WireGuard니까 — 다만 인증서 의식과 설정 파일 고고학을 떠안게 됨 |

어느 행이든 mesh VPN보다 셋업이 더 들거나, 공격면이 더 넓거나, 유지보수가 더
듭니다. 그게 §1의 논지 전부입니다.

### C.5 회사 방화벽

회사 네트워크는 보통 나가는 HTTPS (443)만 허용하고 나머지는 별로 안 열어줍니다.
나가는 SSH (22)는 자주 막힘. 그래서 어떤 도구들은 SSH를 HTTPS 위에 터널하고,
Tailscale은 직접 UDP 연결이 안 되면 443의 DERP 릴레이로 폴백합니다.

### C.6 IPv6 각주

IPv6는 모든 기기에 글로벌 유일 주소를 주니 이론상 NAT가 필요 없어집니다.
현실은 가정용 IPv6 보급이 아직 들쭉날쭉이고, 방화벽이 어차피 들어오는 트래픽을
막습니다. IPv6가 C.2를 해결해줄 거라 기대하진 마세요.

## 부록 D: 한국 환경에서 자주 만나는 함정

한국 특화 메모. 본인 망/통신사/회사 환경에 따라 다를 수 있음.

### D.1 통신사별 공인 IP / CGNAT 상황

대략적인 현황 (정책은 자주 바뀌니 본인 확인 필요):

| 통신사 | 가정용 광케이블 | 모바일 |
|--------|---------------|--------|
| KT | 보통 공인 IP 부여 (정적은 별도 신청) | CGNAT 기본 |
| SK 브로드밴드 | 공인 IP 부여 (요청 시 변경/고정 가능) | CGNAT 기본 |
| LG U+ | 공인 IP 부여, 일부 회선 CGNAT | CGNAT 기본 |
| 알뜰폰 (MVNO) | 해당 없음 | CGNAT 거의 100% |

확인 방법:

```sh
# 본인 공유기에 들어가서 WAN IP 확인 후, whatismyip.com과 비교
# 둘이 다르면 CGNAT임 (또는 공유기가 라우터 모드가 아님)
curl -s https://api.ipify.org   # 외부에서 본 내 IP
ifconfig | grep "inet " | grep -v 127        # 공유기에서 본 내 IP
```

**CGNAT면 포트 포워딩 자체가 불가능**하니 Tailscale(또는 다른 mesh VPN)만 답입니다.
다행히 Tailscale은 CGNAT 뒤에서도 잘 돌아갑니다. 그게 §1.2의 핵심입니다.

### D.2 가정용 회선의 포트 차단

일부 통신사는 가정용 회선에서 **서버 운영을 막기 위해** 특정 포트의 inbound를
차단함:

- 흔히 차단되는 포트: 25 (SMTP), 80 (HTTP), 443 (HTTPS), 3389 (RDP)
- 22 (SSH)는 일반적으로 열려있음. 그래도 본인 ISP에 확인
- 8080 같은 비표준 포트로 우회하는 가이드들이 인터넷에 많지만, 약관 위반일 수
  있고 단속 시 회선 정지 가능

→ 결론: 가정용 회선에서 직접 서버 노출은 ISP 약관 살피고, 정 필요하면
Tailscale Funnel처럼 ISP 약관을 건드리지 않는 방식 쓰세요.

### D.3 망분리 회사 (대기업·금융·공공)

한국 대기업·금융·공공은 **망분리** (업무망 ↔ 인터넷망 물리/논리 분리)가 흔함.
이 환경에서는:

- 회사 노트북에서 외부 인터넷 자체가 제한됨 (가상 데스크탑 통한 우회 인터넷)
- 외부로 22번 outbound 차단이 거의 표준
- 외부 VPN 소프트웨어 설치 자체가 EDR/DLP에 잡혀서 IT 보안팀에 알람
- 개인 USB나 클라우드 연결도 막혀있음 → 키 파일 옮기는 것도 비공식 경로 불가

→ **회사 노트북에 Tailscale 깔 생각은 아예 하지 마세요.** 망분리 환경이면 IT
보안팀에 공식 요청해서 그쪽에서 주는 수단(회사 VDI, 회사 Tailscale 테넌트 등)을
쓰세요. 우회하다 걸리면 커리어에 좋을 게 없습니다.

### D.4 휴대폰 한글 입력 in SSH 앱

Hangul 입력 처리는 앱마다 다름:

| 앱 (iOS) | 한글 입력 |
|---------|---------|
| Blink Shell | OK (단, IME 조합 중 ESC 같은 키 누르면 입력 깨질 수 있음) |
| Termius | 가장 무난 |
| a-Shell | 한글 입력 한글 입력 잘 안 됨, 영어 명령용 |

| 앱 (Android) | 한글 입력 |
|------------|---------|
| Termux | OK (시스템 키보드 그대로 씀) |
| JuiceSSH | OK |
| Termius | OK |

→ Claude/Codex에 한글 프롬프트 칠 거면 **블루투스 키보드를 강력 추천**합니다. 화면
키보드로 긴 한글을 치는 건 정말 고역입니다.

### D.5 Tailscale 지연 시간 (한국)

Tailscale의 [DERP 릴레이](https://tailscale.com/kb/1118/custom-derp-servers/)는
한국에 직접 없음 (2026년 기준, 도쿄가 가장 가까움). 그래서:

- 직접 P2P 연결 잘 되면 → 지연시간 거의 없음 (같은 LAN 수준)
- DERP 폴백되면 → 도쿄 경유 → 일반적으로 30-50ms 추가
- SSH/터미널 작업엔 거의 무감각, 영상/스트리밍엔 체감됨

확인:

```sh
tailscale ping <peer>
# "direct" 나오면 P2P, "via DERP" 나오면 릴레이
```

직접 연결이 안 되면 보통 양쪽 NAT 종류(symmetric NAT)가 문제입니다. 공유기 UPnP를
켜거나 포트 포워딩을 한 줄(UDP 41641) 넣어주면 P2P 성공률이 올라갑니다.

### D.6 회사 컴퓨터 (BYOD): 자주 묻는 케이스

스타트업·중견·외국계는 대체로 BYOD 또는 회사 노트북에 어느 정도 자유도가
있음. 그런 환경이면:

- 본인 책임 하에 Tailscale 깔아도 보통 무방 (정책 먼저 확인)
- 단, **회사 데이터를 개인 tailnet의 다른 기기에 옮기는 행위**는 회사 자산
  유출. 그건 별개 문제.
- `ai` 라우터 본래 취지대로 *각 신원의 데이터는 그 신원의 워크스페이스에만*
  머물게 유지하면 됨.

### D.7 한국 인터넷 사용자 추천 셋업

본인이 일반적인 한국 직장인 + 집 인터넷 + 휴대폰 사용자라면 거의 항상 정답:

1. **집 맥에 Tailscale + tmux + `pmset -c sleep 0`**
2. **휴대폰에 Tailscale + Blink Shell (또는 Termux)**
3. **회사에서는 어떤 원격 접근도 시도하지 말기** (필요하면 공식 채널)
4. **mosh는 LTE/5G 자주 끊기는 환경이면 추가**

이 셋업이 레포 전체 워크플로우와 가장 잘 맞습니다.
