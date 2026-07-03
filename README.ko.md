# ai: AI 세션 라우터

[![release](https://img.shields.io/github/v/release/baksohyeon/ai-session-router?label=release&sort=semver)](https://github.com/baksohyeon/ai-session-router/releases/latest)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

**Language:** [English](README.md) · 한국어  |  **릴리스:** [최신](https://github.com/baksohyeon/ai-session-router/releases/latest) · [전체](https://github.com/baksohyeon/ai-session-router/releases)

명령 한 줄로 **Claude Code** 또는 **Codex**를 맞는 **계정**, 맞는 **워크스페이스**, 맞는
**브라우저 신원**으로 실행합니다. 개인용과 업무용 AI 사용이 서로 섞이지 않게요.

```sh
ai claude company              # 회사 계정, 회사 워크스페이스
ai codex  personal             # 개인 계정, 개인 워크스페이스
ai codex  company --account personal   # 회사 워크스페이스 + 개인 계정 (자유롭게 조합)
ai gui    company              # 회사 GUI를 격리된 브라우저/앱 인스턴스로 열기
ai doctor                      # 전체 설정 진단
```

## 왜

개인용과 업무용 둘 다 AI CLI를 쓰면, 모든 게 전역 상태 디렉토리 하나를 공유하려 듭니다.
같은 계정, 같은 결제, 같은 대화 기록, 같은 로그로요. `ai`는 "세션"을 **직접 고르는 직교 축들의
조합**으로 다뤄서 이것들을 깔끔하게 분리합니다.

| 축            | 정하는 것                     | 방식                                        |
|---------------|-------------------------------|---------------------------------------------|
| **워크스페이스** | 파일 + 로그 위치              | 그 폴더로 `cd`; 로그는 `<ws>/.ai-logs/` 아래 |
| **계정**      | 인증 / 결제 / 세션            | `CLAUDE_CONFIG_DIR` · `CODEX_HOME`          |
| **브라우저**  | GUI 채팅 신원                 | 신원마다 격리된 브라우저 인스턴스 하나 (`--user-data-dir`) |
| **Tailscale** | 원격 진입 (보고만 함)         | `ai remote doctor`                          |

공용 개발 도구(`ssh`, git, 에디터, 시크릿 매니저)는 전역 그대로 두고 건드리지 않습니다.

## 원리 (한 문단)

Claude Code와 Codex는 상태를 **전부**(토큰, 세션, 설정, 에이전트) 환경변수 하나
(`CLAUDE_CONFIG_DIR` / `CODEX_HOME`)가 가리키는 디렉토리 하나에서 읽습니다. "계정 전환"은
실행 전에 그 변수를 다른 폴더로 가리키는 것뿐입니다. `ai`는 여기에 기본 규칙, 가드레일, 로깅,
OS별 브라우저/tmux 헬퍼를 얹습니다. [docs/ko/ARCHITECTURE.md](docs/ko/ARCHITECTURE.md) 참고.

## 퀵스타트

```sh
git clone <this-repo> ~/dev/personal/ai-session-router
cd ~/dev/personal/ai-session-router
./install.sh           # 디렉토리·설정 생성 + ~/.local/bin/ai 심볼릭 링크
ai doctor              # 확인
```

그다음 계정마다 한 번씩 로그인합니다. 예: `ai codex company -- login` → Codex 로그인 흐름.
OpenAI/Codex 세부(인증 방식, API 키 프로필, ChatGPT 웹 계정 전환이 Codex 계정 전환이 **아닌**
이유)는 [docs/ko/CODEX-AUTH.md](docs/ko/CODEX-AUTH.md)를 보세요.

## 설정

`install.sh`가 언제든 편집 가능한 설정 파일을 씁니다:

```
${XDG_CONFIG_HOME:-~/.config}/ai-session-router/router.env
```

모든 오버라이드(워크스페이스 경로, config-root 접두사, 신원별 브라우저/URL/프로필)는
[examples/router.env.example](examples/router.env.example) 참고. 아니면 `ai gui setup`을 한 번
돌려 설치된 브라우저를 자동 감지하고 신원별 매핑을 대신 써주게 하세요.

## 명령어

전체 레퍼런스: [docs/ko/COMMANDS.md](docs/ko/COMMANDS.md). 요약:

```
ai gui|shell|tmux   <personal|company>
ai zellij           <personal|company>                         # 선택: 현대적 멀티플렉서 (tmux = 폴백)
ai gui setup [--print]                                         # 브라우저 감지, 신원별 매핑을 router.env에 기록
ai claude|codex     <personal|company> [--account personal|company] [-- tool-args...]
ai resolve <claude|codex> <personal|company> [--account ...]   # dry-run 미리보기
ai profiles [list | show <personal|company>]                   # 계정 인벤토리 (비밀 없이)
ai doctor | ai remote doctor | ai logs
```

계정은 설정 기반입니다. 내장 `personal`/`company`를 `AI_PROFILES`로 임의 이름까지 확장할 수
있습니다 ([docs/ko/COMMANDS.md](docs/ko/COMMANDS.md) 참고).

## 플랫폼 지원

zsh 필요. macOS는 완전히 테스트됨. Linux는 제공·스모크 테스트됨. **Windows는 파워쉘 말고 WSL +
zsh로 실행하세요**(`bin/ai`는 zsh 스크립트라 파워쉘로는 안 돌아감). 어떤 도구·표면·OS 조합이
격리되고 왜 그런지는 [docs/ko/SUPPORT.md](docs/ko/SUPPORT.md)
([English](docs/en/SUPPORT.md))에 있습니다. OS 빌드 매트릭스는
[docs/ko/PORTABILITY.md](docs/ko/PORTABILITY.md).

## 원격 접속

한 머신에서 `ai`를 돌리고 폰·다른 랩탑·어디서든 붙되, 네트워크가 끊기거나 뚜껑을 닫아도 세션이
살아있게 하는 방법은 [docs/ko/REMOTE-ACCESS.md](docs/ko/REMOTE-ACCESS.md)
([English](docs/en/REMOTE-ACCESS.md))에 정리했습니다. Tailscale·SSH·tmux·절전 제어·모바일
클라이언트·엔드투엔드 워크플로까지.

## 보안

이 리포는 **시크릿을 담지 않습니다**. 계정 config 루트(`~/.claude-*`, `~/.codex-*`)와 로그는
추적되지 않습니다([.gitignore](.gitignore) 참고). 토큰은 각 계정의 config 루트 안에만 있습니다.
라우터는 워크스페이스 근처의 secret처럼 생긴 파일을 경고할 때 이름만 읽지 내용은 절대 안 읽습니다.
`ai doctor`는 Codex `auth.json`을 *존재*·파일 *모드*·비가역 *지문*으로만 보고(내용은 절대 안 봄),
느슨한 권한이나 복제된(만료 토큰) 사본을 경고합니다. Codex 인증 세부:
[docs/ko/CODEX-AUTH.md](docs/ko/CODEX-AUTH.md).

## 라이선스

MIT. [LICENSE](LICENSE) 참고.
