# Surfaces: what isolates, and how

**Language:** [English](../en/SURFACES.md) · 한국어

제품마다 여러 개의 표면(surface)이 있다. 터미널, 데스크톱 앱, 브라우저, 모바일, 원격 제어.
라우터는 로컬 표면을 계정별 상태 루트로 가리키게 해서 격리한다. 서버 쪽 표면(웹과 모바일의
계정 상태)은 격리하지 못한다. 이런 표면은 격리가 벤더 계정 안에 있고, 잘해야 계정마다 별도
브라우저 프로필을 쓰는 정도다. 이 문서는 모든 표면을 나열하고, 라우터가 각각을 격리할 수
있는지, 그 방식이 무엇인지 정리한다. 여기 적은 사실은 2026-07-02 기준이다. 벤더 동작은
바뀌므로 사용 중인 버전에서 직접 확인하라.

## OpenAI / ChatGPT / Codex

| Surface | Router isolates? | How |
|---|---|---|
| ChatGPT web | 부분 | 서버 쪽 계정. ChatGPT 자체 전환기는 계정 2개까지 담고, 그 이상은 신원마다 별도 브라우저 프로필을 쓴다 |
| ChatGPT mobile | 안 됨 | 네이티브 앱, 한 번에 한 계정. 라우터가 손댈 수 없다 |
| Codex CLI | 됨 | 계정마다 `CODEX_HOME` (디렉터리 안 `auth.json` 평문) |
| Codex desktop app | 됨 | Electron. `ai gui`가 계정마다 `--user-data-dir`를 붙여 실행한다 |
| Codex Remote (phone drives host) | 안 됨, 호스트에 고정 | 호스트가 같은 ChatGPT 계정과 워크스페이스로 로그인돼 있어야 한다 |
| Codex `app-server` | 전송 계층, 격리 아님 | 리치 클라이언트를 구동한다. WebSocket 모드는 실험적이며, 인증 없이 절대 노출하지 말 것 |

- ChatGPT 웹 계정 전환은 채팅, 메모리, 청구, 파일, 워크스페이스를 계정별로 분리해 두지만, OpenAI는 Codex desktop이나 네이티브 ChatGPT mobile에서는 아직 지원하지 않는다고 명시한다: [account switching](https://help.openai.com/en/articles/20001068-use-multiple-accounts-with-account-switching).
- ChatGPT **Projects**는 프로젝트 전용 메모리를 줘서 컨텍스트를 프로젝트 안 대화로 격리한다: [Projects](https://help.openai.com/en/articles/10169521-projects-in-chatgpt).
- ChatGPT **Tasks**(예약 작업)는 웹이나 모바일에서 만들 수 있다: [Tasks](https://help.openai.com/en/articles/10291617-tasks-in-chatgpt).
- ChatGPT **Apps/connectors**는 MCP 기반 도구를 쓴다. 워크스페이스 관리자가 접근을 제어한다: [Connectors](https://help.openai.com/en/articles/11487775-connectors-in-chatgpt).
- ChatGPT **Agent**는 로그인된 세션으로 동작하므로, 에이전트, 브라우저, 앱 사용을 고위험으로 다뤄라: [Agent](https://help.openai.com/en/articles/11752874-chatgpt-agent).
- ChatGPT macOS **Work with Apps**는 코딩 앱의 내용을 읽을 수 있다: [Work with Apps](https://help.openai.com/en/articles/10119604-work-with-apps-on-macos).
- Codex 문서: [auth](https://developers.openai.com/codex/auth), [config](https://developers.openai.com/codex/config-advanced), [CLI reference](https://developers.openai.com/codex/cli/reference), [Remote](https://developers.openai.com/codex/remote-connections), [app-server](https://developers.openai.com/codex/app-server).

## Anthropic / Claude / Claude Code

| Surface | Router isolates? | How |
|---|---|---|
| Claude web | 부분 | 서버 쪽 계정. 개인 계정과 조직 계정이 한 이메일 아래 공존하며 계정 메뉴에서 전환하거나, 브라우저 프로필을 쓴다 |
| Claude mobile | 안 됨 | 네이티브 앱. 데이터 내보내기나 전체 세션 로그아웃을 시작할 수 없다 |
| Claude desktop app | 부분 | CLI 환경 변수가 아니라 OAuth를 쓴다. 내장된 Claude Code는 `ai gui`로 격리하고, 그 밖에는 앱 안에서 계정을 전환한다 |
| Claude Code CLI | 됨 | 계정마다 `CLAUDE_CONFIG_DIR`. macOS 로그인은 config-dir별 Keychain 해시로 격리된다(확인됨, 버전에 따라 다름) |
| Claude Code desktop app | 됨 | Claude desktop 앱이 Claude Code를 내장한다. `ai gui`가 `--user-data-dir`로 격리한다 |
| Claude Code Remote Control | 안 됨, 세션에 고정 | 웹이나 모바일이 아웃바운드 HTTPS로 로컬 세션 하나를 구동한다. 인바운드 포트 없음, Claude.ai 로그인만 쓰고 API 키는 안 쓴다. v2.1.51+ 필요 |

- Claude는 웹, 데스크톱, 모바일에서 돈다: [getting started](https://support.anthropic.com/en/articles/8114491-getting-started-with-claude).
- 한 이메일 아래 개인 계정과 조직 계정은 계정 메뉴에서 전환한다. 대화와 프로젝트는 분리된 채 유지된다: [profiles](https://support.anthropic.com/en/articles/9267400-can-i-migrate-or-merge-two-profiles-that-use-claude-ai).
- 데이터 내보내기: 웹과 데스크톱은 되고, 모바일은 안 된다([export](https://support.anthropic.com/en/articles/9450526-how-can-i-export-my-claude-ai-data)). 전체 세션 로그아웃: 웹만 된다([log out all](https://support.anthropic.com/en/articles/10310342-how-do-i-log-out-of-all-active-sessions)).
- **Projects**: 각자의 기록과 지식을 가진 독립 워크스페이스다. Team/Enterprise는 가시성 제어를 더한다: [projects](https://support.anthropic.com/en/articles/9517075-what-are-projects), [visibility](https://support.anthropic.com/en/articles/9519189-manage-project-visibility-and-sharing).
- **Artifacts**: 전용 창에 뜨는 독립 콘텐츠로, 버전 관리, 다운로드, 공유가 된다. Cowork live artifacts는 유료 플랜에서 작업 사이에도 유지된다. 서버 쪽에 사니 UI에서 내보내라: [artifacts](https://support.anthropic.com/en/articles/9487310-what-are-artifacts-and-how-do-i-use-them), [publish/remix](https://support.anthropic.com/en/articles/9547008-publishing-and-remixing-artifacts), [live artifacts](https://support.anthropic.com/en/articles/14729249-use-live-artifacts-in-claude-cowork).
- 모바일 파일 생성/편집과 iOS App Intents/Shortcuts/widgets: [files](https://support.anthropic.com/en/articles/12111783-create-and-edit-files-with-claude), [iOS intents](https://support.anthropic.com/en/articles/10263469-using-claude-app-intents-shortcuts-and-widgets-on-ios).
- Connectors: 웹 커넥터는 Claude, Cowork, Desktop, Mobile에서, 데스크톱 확장은 Desktop에서 쓴다: [connectors](https://support.anthropic.com/en/articles/11176164-pre-built-web-connectors-using-remote-mcp).
- Claude Code는 터미널, IDE, 데스크톱, 브라우저에서 돈다. Pro/Max는 표면 전체에서 구독 하나를 공유한다: [overview](https://docs.anthropic.com/en/docs/claude-code/overview), [Pro/Max](https://support.anthropic.com/en/articles/11145838-using-claude-code-with-your-pro-or-max-plan).
- 인증 저장과 우선순위(IAM): macOS Keychain. `apiKeyHelper`/`ANTHROPIC_API_KEY`/`ANTHROPIC_AUTH_TOKEN`은 CLI 표면에만 적용되고, Desktop과 클라우드 세션은 OAuth를 쓴다: [IAM](https://docs.anthropic.com/en/docs/claude-code/iam).
- 설정, 메모리, 트랜스크립트, devcontainer, remote control, 게이트웨이: [settings](https://docs.anthropic.com/en/docs/claude-code/settings), [memory](https://docs.anthropic.com/en/docs/claude-code/memory), [data usage](https://docs.anthropic.com/en/docs/claude-code/data-usage), [devcontainer](https://docs.anthropic.com/en/docs/claude-code/devcontainer), [remote control](https://docs.anthropic.com/en/docs/claude-code/remote-control), [LLM gateway](https://docs.anthropic.com/en/docs/claude-code/llm-gateway).

## Claude Code credentials, by OS

- macOS: Keychain. 서비스 이름이 config-dir 경로에서 나오므로, `CLAUDE_CONFIG_DIR`마다 각자의 항목을 갖는다(디렉터리별 격리 확인됨, 문서화되지 않았고 버전에 따라 다름).
- Linux: `~/.claude/.credentials.json`, 권한 0600, 또는 `CLAUDE_CONFIG_DIR`가 설정돼 있으면 그 아래.
- Windows: `%USERPROFILE%\.claude\.credentials.json`, 또는 `CLAUDE_CONFIG_DIR`가 설정돼 있으면 그 아래. 라우터는 PowerShell이 아니라 zsh를 쓰는 WSL에서 돌려라.

## Tailscale (remote reach)

- Serve: tailnet 안에서 비공개, ACL이 적용된다. 이 방식이나 SSH를 우선하라: [Serve](https://tailscale.com/docs/features/tailscale-serve).
- Funnel: 공개 인터넷. 옵트인 전용이며 고위험이다. 인증 없는 에이전트 제어 평면을 이걸로 절대 노출하지 말 것: [Funnel](https://tailscale.com/docs/features/tailscale-funnel).
- Auth key, OAuth client, 태그가 사용자 아닌 기기를 프로비저닝하고 통제한다: [auth keys](https://tailscale.com/docs/features/access-control/auth-keys), [OAuth clients](https://tailscale.com/docs/features/oauth-clients), [tags](https://tailscale.com/docs/features/tags).

See [THREAT-MODEL.md](THREAT-MODEL.md) and [SUPPORT.md](SUPPORT.md).
