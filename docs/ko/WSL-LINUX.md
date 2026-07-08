# WSL 및 Linux 설정

**Language:** [English](../en/WSL-LINUX.md) · 한국어

> **[보관됨]** 이 프로젝트는 deprecated이며 세션 라우팅은 Orca로 옮겨갔습니다. 되돌리기: [TEARDOWN.md](TEARDOWN.md). 참고용으로 남겨둡니다.

Linux에서, 그리고 WSL을 통해 Windows에서 라우터를 실행하는 방법이다. 정확한 설정 절차,
읽기 전용 스모크 배터리 실행 방법, 그리고 무엇이 실제로 검증됐고 무엇이 코드 정적 검토에만
그쳤는지를 솔직하게 정리한다. 도구별 표면별 OS 지원표는 [SUPPORT.md](SUPPORT.md)를,
`bin/ai` 내부의 플랫폼 추상화 지점은 [PORTABILITY.md](PORTABILITY.md)를 참고하라.

## 어디까지 검증됐나

라우터는 macOS에서 개발하고 실행한다. Linux 경로는 코드에서 분기 처리돼 있고 스모크
스크립트로 커버되지만, 관리자의 호스트가 macOS라서 Linux와 WSL은 여기서 실제 하드웨어로
돌려보지 못했다. 이 점을 알고 사용하라.

| 플랫폼 | 상태 | 의미 |
|---|---|---|
| macOS | 검증됨 | 매일 개발하고 실행함. 모든 명령을 실제로 돌려봄 |
| Linux | 정적 감사 + 스크립트 제공 | 모든 Linux 분기를 코드에서 검토함. 실제 기기에서 스스로 확인하도록 `scripts/smoke.sh` 제공. 이 호스트에서 Linux로 실행하지는 않음 |
| WSL을 통한 Windows | 정적 검토 + 스크립트, 여기서 실행 안 함 | WSL 안에서 동일한 Linux 코드 경로 사용. 설정 문서화됨. 이 호스트에서 Windows로 부팅하지 않음 |

Linux나 WSL에서 라우터를 돌린다면, 아래의 `scripts/smoke.sh`를 실행하는 것이 내 기기에서
플랫폼 분기가 제대로 동작하는지 확인하는 방법이다.

## Linux 설정

1. `zsh`를 설치한다. 라우터는 zsh 스크립트다(`#!/usr/bin/env zsh`).

   ```sh
   sudo apt install zsh      # Debian / Ubuntu
   sudo dnf install zsh      # Fedora
   sudo pacman -S zsh        # Arch
   ```

2. 사용하는 CLI(`claude`, `codex`)를 각자의 안내대로 설치하고 `PATH`에 올라와 있는지
   확인한다.

3. 라우터를 클론하고 설치한다:

   ```sh
   git clone <this-repo> ~/dev/personal/ai-session-router
   cd ~/dev/personal/ai-session-router
   ./install.sh
   ```

4. 확인한다:

   ```sh
   ai doctor
   ```

   Linux에서 `doctor`는 `/etc/os-release`로 배포판을 보고하고, `zsh`, `claude`,
   `codex`, `tmux`, `tailscale`을 점검하고, 설정 루트를 나열한다. Linux에서는 자격 증명이
   파일로 저장되므로(Claude는 `~/.claude-<account>/.credentials.json`, Codex는
   `~/.codex-<account>/auth.json`) 격리는 `CLAUDE_CONFIG_DIR`과 `CODEX_HOME`로 곧바로
   이뤄진다. Linux에는 Keychain이 없으므로 `ai keychain` 명령은 해당 없음을 보고하고 아무
   일도 하지 않는다.

5. 브라우저 GUI(선택): Chromium 계열 브라우저(Chrome, Chromium, Edge, Brave)를 설치하고
   `ai gui setup`을 실행한다. 라우터는 Linux 바이너리(`google-chrome`, `chromium`,
   `microsoft-edge` 등)를 아이덴티티별로 격리된 `--user-data-dir`와 함께 실행한다.
   Chromium 브라우저가 없으면 `ai gui`는 `xdg-open`으로 기본 브라우저에서 URL을 열고
   경고한다.

## WSL을 통한 Windows: PowerShell 말고 WSL을 쓰라

`bin/ai`는 zsh 스크립트다. PowerShell과 CMD로는 아예 실행할 수 없다. Windows에서는 WSL
안에서 실행하며, 거기서는 Linux처럼 동작한다.

1. 관리자 권한 PowerShell에서 WSL과 Linux 배포판을 설치하고, 요청되면 재부팅한다:

   ```powershell
   wsl --install
   ```

   기본으로 WSL 2와 Ubuntu가 설치된다. PowerShell에서 하는 일은 이 한 단계뿐이고, 이후는
   전부 WSL 터미널 안에서 한다.

2. **WSL 터미널**을 연다(Ubuntu 앱, 또는 일반 터미널에서 `wsl`). 나머지는 전부 여기서
   하고, PowerShell이나 CMD에서는 하지 않는다.

3. WSL 안에서 `zsh`를 설치한다:

   ```sh
   sudo apt update && sudo apt install zsh
   ```

4. WSL 안에서 CLI(`claude`, `codex`)를 설치하고 `PATH`에 있는지 확인한다.

5. Linux와 똑같이 라우터를 클론하고 설치한다:

   ```sh
   git clone <this-repo> ~/dev/personal/ai-session-router
   cd ~/dev/personal/ai-session-router
   ./install.sh
   ai doctor
   ```

6. WSL 터미널에서 계정마다 한 번씩 로그인한다:

   ```sh
   ai codex company -- login
   ai claude company            # 세션 안에서 /login
   ```

### WSL에서 되는 것과 안 되는 것

- **CLI 세션**(`ai claude`, `ai codex`)은 WSL 안에서 동작한다. Linux와 똑같이
  `CLAUDE_CONFIG_DIR` / `CODEX_HOME`로 격리한다.
- **자격 증명**은 계정별 설정 루트 아래 파일로 저장되며 환경 변수로 격리된다. Windows 자격
  증명 관리자는 관여하지 않는다.
- **GUI 격리는 넘어오지 않는다.** 라우터는 macOS나 Linux 앱을 실행하지 Windows `.exe`
  앱을 실행하지 않는다. WSL 안의 `ai gui`는 Linux 브라우저 바이너리를 대상으로 하는데,
  기본 WSL 이미지에는 보통 설치돼 있지 않다. Windows용 Claude 앱은 따로 열거나, 격리된
  브라우저 경로를 쓰고 싶으면 WSL에 Linux 브라우저를 설치하라.
- **`ai`는 항상 WSL 터미널에서 실행하라.** PowerShell이나 CMD에서 실행하면 동작하지
  않는다.

## 스모크 배터리 실행

`scripts/smoke.sh`는 안전한 읽기 전용 및 드라이런 배터리다. zsh나 bash에서 실행되며,
라우터의 비파괴적 표면을 전부 훑는다:

- 도구와 계정 조합별 `ai resolve`
- `ai profiles list`와 `ai profiles show`
- `ai doctor`, `ai remote doctor`, `ai logs`
- `ai gui <id> --dry-run`과 `ai gui setup --print`(아무것도 실행하지 않음)
- `ai keychain list`(속성만 읽고, 절대 prune하지 않음)
- 어떤 출력에도 토큰 모양 문자열이 나오지 않는지 확인하는 시크릿 유출 검사

대화형 세션을 절대 실행하지 않고, 브라우저나 앱을 절대 열지 않으며, `keychain prune`을 절대
돌리지 않는다. 검사가 하나라도 실패하거나 시크릿 패턴이 발견되면 0이 아닌 코드로 종료한다.

```sh
cd ~/dev/personal/ai-session-router
zsh scripts/smoke.sh       # 또는: bash scripts/smoke.sh
echo $?                     # 0이면 모든 검사 통과
```

스크립트는 자기 위치를 기준으로 `bin/ai`를 찾으므로, `PATH`의 `ai`가 무엇을 가리키든 자신이
들어 있는 체크아웃을 테스트한다.

정상 실행은 `summary: 21 passed, 0 failed` 같은 줄과 종료 코드 0으로 끝난다. Linux와
WSL에서는 개수가 macOS와 다르지만(Keychain이 없고 GUI 경로가 Linux 브라우저로 해석됨),
해당하는 검사는 모두 통과해야 한다.

## 관련 문서

[SUPPORT.md](SUPPORT.md), [PORTABILITY.md](PORTABILITY.md),
[ARCHITECTURE.md](ARCHITECTURE.md), [REMOTE-ACCESS.md](REMOTE-ACCESS.md).
