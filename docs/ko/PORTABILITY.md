# Portability & OS support

**Language:** [English](../en/PORTABILITY.md) · 한국어

라우터는 환경을 가리지 않고 돌아가도록 만들었다. **핵심 기능**(환경 변수
리다이렉션, 워크스페이스 선택, 로깅, doctor/resolve)은 OS를 타지 않는다. 태생적으로
플랫폼에 묶이는 부분은 몇 군데뿐이고, 그런 것들은 헬퍼 함수 뒤에 몰아넣어서
OS를 하나 추가할 때 한 곳만 고치면 되게 했다.

## 지원 현황

| 기능                    | macOS (검증됨)             | Linux (제공됨, 스모크 테스트) | 비고 |
|------------------------|---------------------------|--------------------------------|-------|
| account/workspace/logs | ✅                         | ✅                              | 순수 env + fs |
| `ai resolve` / `doctor`| ✅                         | ✅                              | OS 표기는 `sw_vers` / `/etc/os-release` |
| transcript (`script`)  | ✅ BSD `script -q F cmd`   | ✅ util-linux `script -q -c "cmd" F` | `$AI_OS`로 분기 |
| `ai gui personal`      | ✅ `open -a "Microsoft Edge"` | ⚠️ `microsoft-edge[-stable]` | 기본 브라우저로 폴백 |
| `ai gui company`       | ✅ Chrome `--profile-directory` | ⚠️ `google-chrome`/`chromium --profile-directory` | PATH에 바이너리 필요 |
| sshd check             | ✅ `lsof`                  | ✅ `lsof` 또는 `ss`             | 권한 없이 최선 노력 |
| `ai tmux`              | ✅                         | ✅                              | tmux 필요 |

범례: ✅ 구현 및 검증 완료 · ⚠️ 구현했으나 해당 브라우저가 설치돼 있어야 하고,
실제 Linux 데스크톱에서는 아직 검증하지 않음.

## 플랫폼 추상화 지점 (`bin/ai` 안)

OS 분기는 스크립트 상단의 헬퍼 몇 개에 모여 있다:

- `AI_OS`: `uname -s`로 한 번만 설정 (`macos` / `linux` / `other`).
- `_open_url`: `open`(macOS) 대 `xdg-open`(Linux).
- `_has_browser` / `_launch_edge` / `_launch_chrome_profile`: 앱 감지 + 실행.
- `_os_label`: `sw_vers` 대 `/etc/os-release` 대 `uname`.
- `_sshd_listening`: `lsof` 먼저, 안 되면 `ss`로 폴백.
- `_run_with_transcript`: BSD 대 util-linux `script(1)` 문법.

새 OS(예: WSL, BSD)를 추가하려면 이 헬퍼들만 손보면 된다.

## 의존성

- **필수**: `zsh`(스크립트가 배열, `setopt`, `${x:t}`를 쓴다), coreutils
  (`date`, `find`, `sed`).
- **선택**: `tmux`(`ai tmux`용), `script`(transcript용, 없으면 직접
  실행으로 격하), `tailscale`(`ai remote doctor`용), Chromium/Edge 브라우저(`ai gui`용).

## 설정 재정의

머신마다 다른 값은 코드에 박아두지 **않았다**. 이 값들은
`${XDG_CONFIG_HOME:-~/.config}/ai-session-router/router.env`(또는 환경 변수)에서 오므로,
같은 스크립트라도 설정만 다르게 넣으면 어느 머신에서든 돌아간다:

```sh
AI_PERSONAL_WS="$HOME/dev/personal"
AI_COMPANY_WS="$HOME/work/acme"
AI_CODEX_ROOT_PREFIX="$HOME/.codex-"
AI_CHROME_COMPANY_PROFILE="Acme Work"
```

## 아직 이식되지 않은 것

- **브라우저 GUI**는 태생적으로 데스크톱 OS에 묶인다. 헤드리스/서버 호스트에서는
  `ai gui`가 경고만 내고 아무 동작도 하지 않는다. 의도된 동작이다.
- Windows는 범위 밖이다(Linux처럼 동작하는 WSL을 쓸 것).

## 이식성 테스트

```sh
zsh -n bin/ai                      # syntax (any OS with zsh)
shellcheck -s bash bin/ai || true  # heuristic lint (zsh not fully supported)
./bin/ai resolve codex company --account personal   # pure-logic, OS-agnostic
./bin/ai doctor                    # exercises OS label + browser detection
```
