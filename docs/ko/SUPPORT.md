# 지원 현황: 도구, 표면, 플랫폼

**Language:** [English](../en/SUPPORT.md) · 한국어

라우터가 무엇을, 어느 표면에서, 어느 OS에서 격리하는지 정리한 페이지다. "내 조합이 되나?"를
여기서 확인하면 된다. 명령어 문법은 [COMMANDS.md](COMMANDS.md), 설치와 첫 실행은
[퀵스타트](../../README.md#quick-start)를 봐라.

## 소개

`ai`는 Claude Code, Codex, 그리고 그 채팅 GUI를 개인 신분과 회사 신분이 섞이지 않게 실행한다.
도구, 계정, 표면(터미널·데스크톱 앱·브라우저)을 고르면, 라우터가 실행 전에 그 도구를 계정별
위치로 물려준다. 이 "위치"가 도구와 표면마다 달라서, 어떤 조합은 깔끔하게 격리되고 한두 개는
안 된다. 이 페이지가 그 조합을 전부 적어두고 이유도 밝힌다.

## 퀵스타트

```sh
git clone <this-repo> ~/dev/personal/ai-session-router
cd ~/dev/personal/ai-session-router
./install.sh                 # 디렉토리+설정 생성, ~/.local/bin/ai 심볼릭 링크
ai doctor                    # 전체 설정 점검
ai codex company -- login    # 계정마다 한 번 로그인
ai gui setup                 # 브라우저 감지 후 신분별 매핑 작성
```

## 명령어 (요약)

```
ai claude|codex  <personal|company> [--account personal|company] [-- tool-args...]
ai gui           <personal|company> [--browser] [--dry-run]
ai gui setup     [--print]
ai shell|tmux    <personal|company>
ai resolve <claude|codex> <personal|company> [--account ...]    # dry-run 미리보기
ai profiles      [list | show <personal|company>]              # 계정 인벤토리 (비밀 없이)
ai doctor | ai remote doctor | ai logs
```

전체 레퍼런스: [COMMANDS.md](COMMANDS.md).

## 지원 현황: 도구·표면별

| 도구 / 표면 | 격리 | 방식 | 비고 |
|---|---|---|---|
| **Claude Code (CLI)** | 됨 | `CLAUDE_CONFIG_DIR` | 계정마다 설정·세션·플러그인·스킬 분리 |
| **Claude 데스크톱 앱** | 됨 | `--user-data-dir` (Electron) | `ai gui`. 앱이 Claude Code를 임베드해서 데스크톱 GUI와 CLI가 같은 엔진으로 돈다 |
| **브라우저 속 Claude** | 됨 | 전용 프로필 또는 격리 user-data 디렉토리 | `ai gui --browser` |
| **Codex (CLI)** | 됨 | `CODEX_HOME` | 로그인이 그 디렉토리 안 평문 `auth.json`이라 격리가 완전히 확실하다 |
| **Codex 데스크톱 앱 (Electron)** | 됨 | `--user-data-dir` (Electron) | Electron 확인(`app.asar` 포함). `ai gui`가 Claude와 함께 격리 실행 |
| **ChatGPT 데스크톱 앱** | 안 됨 | 방법 없음 | 네이티브 macOS(AppKit) 앱이라 `--user-data-dir`을 무시한다. 브라우저 프로필로 대신하라 |
| **브라우저 속 ChatGPT** | 됨 | 전용 프로필 | `ai gui company`가 회사 프로필로 chatgpt.com을 연다 |

## 지원 현황: OS별

| | macOS | Linux | Windows |
|---|---|---|---|
| CLI (`claude` / `codex`) | 됨 | 됨 | WSL 안에서만 됨 |
| 데스크톱 앱 격리 | 됨 (`open -n -a --user-data-dir`) | 해당 없음 | 안 됨: 라우터가 Windows 앱을 못 부린다 |
| 브라우저 격리 | 됨 (Edge / Chrome) | 됨 (chrome / chromium) | WSL에서 Windows 브라우저로 넘기는 브리지 필요 |
| 셸 | zsh (기본) | zsh 설치 | **WSL + zsh (파워쉘 금지)** |
| 상태 | 완전 테스트 | 제공, 스모크 테스트 | 정적 검토만, 여기선 실측 안 함 |

## Windows: 파워쉘 말고 WSL

`bin/ai`는 zsh 스크립트(`#!/usr/bin/env zsh`)다. 파워쉘과 CMD로는 아예 못 돌린다.
Windows에서는:

1. WSL과 리눅스 배포판을 설치한다.
2. WSL 안에 zsh를 깔고, **WSL 터미널**에서 `ai`를 실행한다(파워쉘·CMD 아님).
3. CLI 세션(`ai claude`, `ai codex`)은 거기서 잘 된다.
4. GUI 격리는 안 넘어온다: 라우터는 macOS나 Linux 앱을 부르지 Windows `.exe` 앱을 못 부른다.
   Windows용 Claude 앱은 따로 열어라.

## 각 방식이 되는 이유

도구는 저마다 계정 상태를 한곳에서 읽고, 라우터는 그 한곳을 계정별 폴더로 물려준다. 레버는
도구마다 다르다. (벤더 문서는 자주 바뀌니 쓰는 버전에서 플래그를 확인하라.)

- **Claude Code, `CLAUDE_CONFIG_DIR`.** Claude Code는 상태를 전부 설정 디렉토리 하나에서
  읽는다. macOS에서는 OAuth 토큰이 그 디렉토리 경로로 만든 서비스 이름 아래 Keychain에 들어가서,
  설정 디렉토리마다 Keychain 항목이 따로 생긴다. 문서:
  [authentication](https://code.claude.com/docs/en/authentication),
  [CLI reference](https://code.claude.com/docs/en/cli-reference).
- **Codex, `CODEX_HOME`.** Codex는 설정·`auth.json`·기록·세션을 `CODEX_HOME`에서 읽는다.
  로그인이 그 안 평문 파일이라 두 홈이 로그인을 공유하지 않는다(refresh 토큰은 1회용이라
  `auth.json`을 홈 사이에 복사하면 안 된다). 문서:
  [Codex auth](https://developers.openai.com/codex/auth),
  [config](https://developers.openai.com/codex/config-advanced).
- **Electron 데스크톱 앱, `--user-data-dir`.** Electron은 Chromium을 품고, Chromium은 프로필
  데이터를 전부 `--user-data-dir` 아래 둔다. 계정별 디렉토리를 넘기면 실행마다 로그인이 따로
  잡힌다. Claude 데스크톱 앱이 격리되는 이유이고, Codex 데스크톱 앱도 되는 이유다(Electron이라).
  참고: [Chromium command-line switches](https://peter.sh/experiments/chromium-command-line-switches/).
- **네이티브 AppKit 앱(ChatGPT.app), 레버 없음.** 네이티브 macOS 앱은 Chromium 플래그를
  무시해서 `--user-data-dir`이 아무 일도 안 한다. ChatGPT 자체의 웹 계정 전환은 브라우저 안에
  머물고 Codex까지 닿지 않는다. 문서:
  [ChatGPT account switching](https://help.openai.com/en/articles/20001068-use-multiple-accounts-with-account-switching).
- **브라우저, `--profile-directory` / `--user-data-dir`.** Chrome과 Edge는 프로필마다 또는
  user-data 디렉토리마다 로그인을 따로 둬서, 신분 하나에 프로필 하나면 깨끗하게 유지된다.

## 알려진 갭과 동작 메모

- **Codex 데스크톱 앱**: 격리된다(Electron). `ai gui`가 Claude.app과 Codex.app을 함께,
  각각 계정별 `--user-data-dir`로 연다. 하나만 열려면 `AI_GUI_APPS`에 이름 하나만 넣는다.
- **ChatGPT 데스크톱 앱**: 격리 불가(AppKit). `ai gui --browser`를 쓴다.
- **Windows GUI**: 범위 밖. 라우터는 WSL CLI를 다루지 Windows 네이티브 앱은 안 다룬다.
- **Windows와 Linux**: 코드를 읽어 검토했고 macOS 호스트에서 실측하진 않았다.
- **시작 디렉토리**: `ai claude`와 `ai codex`는 현재 위치가 선택한 워크스페이스 안이면 그
  자리에서 시작하고, 워크스페이스 밖에서 실행할 때만 루트로 옮긴다(경고와 함께). `ai gui`는
  현재 위치를 안 본다.

관련: [ARCHITECTURE.md](ARCHITECTURE.md), [PORTABILITY.md](PORTABILITY.md),
[CODEX-AUTH.md](CODEX-AUTH.md), [SURFACES.md](SURFACES.md), [THREAT-MODEL.md](THREAT-MODEL.md).
