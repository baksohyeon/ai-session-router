# 아키텍처

**Language:** [English](../en/ARCHITECTURE.md) · 한국어

> **[보관됨]** 이 프로젝트는 deprecated이며 세션 라우팅은 Orca로 옮겨갔습니다. 되돌리기: [TEARDOWN.md](TEARDOWN.md). 참고용으로 남겨둡니다.

## 1. 문제

한 대의 머신, 한 명의 사용자, 두 개의 AI 신원(개인 계정/프로젝트 vs 업무
계정/저장소). CLI AI 도구는 기본적으로 전역 상태 디렉터리 하나만 쓰기 때문에
서로 뒤섞이는 문제가 생긴다. 청구가 엉뚱하게 잡히고, 대화 기록이 섞이고, MCP
토큰이 잘못 물리고, 로그가 엉뚱한 트리에 쌓인다. `ai`는 어떤 신원을 쓸지 명시적으로,
그리고 매번 똑같이 고를 수 있게 해준다.

## 2. 핵심 아이디어: 직교하는 축

"세션"을 서로 독립적이면서 자유롭게 조합되는 축들로 나눈다:

| 축            | 결정하는 것                    | 방식                                        |
|---------------|-------------------------------|---------------------------------------------|
| **workspace** | 파일 + 로그 위치               | `cd`; 로그는 `<ws>/.ai-logs/` 아래           |
| **account**   | 인증 / 청구 / 세션             | `CLAUDE_CONFIG_DIR` · `CODEX_HOME`          |
| **browser**   | GUI 채팅 신원                  | 격리된 브라우저 인스턴스 (`--user-data-dir`) |
| **Tailscale** | 원격 진입 (리포트 전용)        | `ai remote doctor`                          |

한 축을 바꿔도 다른 축은 영향을 받지 않는다. `ai codex company --account personal` =
"개인 계정, 회사 워크스페이스, 회사 위치에 남는 로그"를 뜻한다. 여기서는 한 줄이지만,
다른 데서라면 지뢰가 될 조합이다.

## 3. 작동 방식

CLI AI 도구는 환경 변수 하나가 가리키는 루트 디렉터리에서 모든 상태를 읽어온다.
그래서 라우터의 핵심은 세 줄이다:

```zsh
export CODEX_HOME="$HOME/.codex-$account"   # account = which folder
cd "$workspace"                              # workspace = where you work
codex "$@"                                    # everything else inherits both
```

나머지(인자 파싱, 기본 규칙, 경고, 로깅, gui/tmux/doctor)는 전부 편의성과
안전장치다.

### 설정 루트

| Tool   | personal              | company              | env var             |
|--------|-----------------------|----------------------|---------------------|
| Claude | `~/.claude-personal`  | `~/.claude-company`  | `CLAUDE_CONFIG_DIR` |
| Codex  | `~/.codex-personal`   | `~/.codex-company`   | `CODEX_HOME`        |

(접두사는 `router.env`로 바꿀 수 있다.) 원본 `~/.claude`/`~/.codex`는 절대
옮기지 않는다. 새 루트는 복제하거나 새로 로그인해서 채운다.

### 워크스페이스와 로그

`<workspace>/.ai-logs/<tool>/<account>-account/session-<timestamp>.log`.
**로그는 워크스페이스가, 인증은 계정이 관리한다.** 터미널 기록은
`script(1)`로 남긴다. TTY를 보존하므로 인터랙티브 TUI도 그대로 동작한다.

### 브라우저 격리 (`ai gui`)

GUI 경로는 Claude 데스크톱 앱이 이미 쓰고 있는 격리 방식을 그대로 재사용한다.
Chromium 기반 앱과 브라우저는 `--user-data-dir=<path>`를 받는데, 이걸 주면
**자체 저장소를 가진 격리 인스턴스가 뜨고 디렉터리도 자동으로 만들어진다.**
미리 만들어둔 프로파일이 없어도 된다. 데스크톱 앱은
`--user-data-dir=~/.claude-app-<account>`를 넘긴다. 브라우저 경로는 같은
아이디어를 아무 Chromium 브라우저(Edge, Chrome, Brave, Arc, Chromium)에도
쓸 수 있게 일반화한 것이다:

> 신원 하나 = 격리된 브라우저 인스턴스 하나. 강제하는 건 없다. 특정 브라우저를
> 요구하지 않고, 프로파일을 미리 만들 필요도 없고, 실행할 때마다 묻지도 않는다.

신원마다 다음 두 방식 중 하나로 처리한다:

| 방식 | 플래그 | 준비 | 용도 |
|-----------|------|-------|-----|
| **격리 data-dir** (기본) | `--user-data-dir=${AI_BROWSER_DATA_PREFIX}<id>` | 없음, 자동 생성 | 준비 없이 깔끔한 격리 |
| **기존 프로파일** (선택) | `--profile-directory=<name>` | 프로파일이 있어야 함 | 기존 프로파일의 로그인/북마크 재사용 |

기본값은 아무것도 강제하지 않는다. 새 data-dir 안에서 브라우저 계정에 로그인하면
**Chromium 동기화**가 걸려서, 한 번 로그인한 뒤에는 북마크/확장/비밀번호/기록이
채워진다. 프로파일을 미리 만들지 않고도 프로파일과 같은 상태가 된다. 사용자가
평소에 아이콘을 눌러 여는 브라우저(*기본* data-dir)는 건드리지 않는다.

신원 `<id>`별 결정 순서: 브라우저 = `AI_GUI_BROWSER_<id>` → `AI_BROWSER` →
처음 감지된 Chromium 브라우저 → OS 기본값(URL만 열고 경고). URL = `AI_GUI_URLS_<id>`.
`AI_GUI_PROFILE_<id>`가 설정돼 있으면 `--profile-directory`로, 아니면
`--user-data-dir`로 실행한다. 예전 방식인 `AI_CHROME_COMPANY_PROFILE` /
`AI_COMPANY_*_URL`도 폴백으로 인정하므로 기존 설정이 계속 동작한다(마이그레이션은
문서로 안내할 뿐 강제하지 않는다). `ai gui setup`은 브라우저/프로파일을 감지해
이 신원별 매핑을 써주는 일회성 도우미이고, 실행 시점에는 아무것도 묻지 않는다.

## 4. 안전장치

- 개인 워크스페이스 + 회사 계정 → 경고
- 선택한 워크스페이스 밖의 cwd → 경고
- 워크스페이스 루트 근처의 비밀처럼 보이는 파일명 → **이름만 보고** 경고(내용은
  절대 읽지 않는다)
- 덮어쓰거나 파괴하는 동작이 아니라면 무엇도 강하게 막지 않는다

## 5. 알려진 한계

- **Codex 내부 로그**는 CLI 플래그로 위치를 바꿀 수 없다. `$CODEX_HOME/log/`
  아래에 쌓인다(계정을 따라감). 워크스페이스 기록이 이를 보완한다.
- **Claude**에는 범용 로그 디렉터리 플래그가 없다(`--debug-file`뿐). 같은
  방식으로 보완한다.
- **macOS의 Claude 인증**은 `CLAUDE_CONFIG_DIR` 아래가 아니라 Keychain에 있다.
  계정별로 격리되기는 하지만, **문서화되지 않은 데다 버전에 따라 달라지는**
  서비스 이름 `Claude Code-credentials-<sha256(config-dir)[:8]>`를 통해서다
  (Claude Code v2.1.198에서 확인했고, 공개 문서는 여전히 공유 항목 하나만
  설명한다). 그래서 `ai doctor`는 넘겨짚지 않고 항목이 있는지 **검증하며**
  (존재 여부만 보고 비밀 자체는 절대 보지 않는다), 업그레이드 후 재검증이
  필요하다고 표시한다. "고치는" 방법 두 가지는 macOS에서 막다른 길이라 일부러
  시도하지 않는다: 파일 기반 `.credentials.json` 강제(지원되는 스위치가 없음)와
  계정별 `CLAUDE_CODE_OAUTH_TOKEN`(이슈 \#37512를 유발하는데, 종료 시 공유
  Keychain 항목을 삭제한다). Codex에는 이런 문제가 없다. `auth.json`은
  `CODEX_HOME` 아래의 평범한 파일이다.
- **버전 드리프트**: 도구는 자동으로 업데이트되고, 래퍼는 버전을 하드코딩하지
  않는다. 위의 macOS Keychain 해시가 이게 발목을 잡을 수 있는 유일한 지점이라,
  그래서 doctor 검증을 둔다.

## 6. MCP: v1에서는 일부러 범위 밖

Claude(JSON)와 Codex(TOML)는 서로 다른 MCP 설정 포맷을 쓰고, 계정별 토큰은
어차피 각 설정 루트 안에 있어야 한다. 그래서 MCP는 핵심 기능이 **아니다**.
`share/mcp/` 자리표시자는 선택적이고 문서화된 확장 지점으로만 존재한다. MCP는
각 계정 자기 설정 루트에 직접 연결하면 된다.

## 7. 데이터 흐름

```
$ ai codex company --account personal -- doctor
        │        │              │          └── passthrough → `codex doctor`
        │        │              └── account override → CODEX_HOME=~/.codex-personal
        │        └── workspace → cd ~/dev/work ; logs under ~/dev/work/.ai-logs
        └── tool → codex
   ↓
   warnings (mismatch / cwd / secrets) → stderr
   ↓
   export CODEX_HOME ; cd workspace ; script -q <transcript> codex doctor
```

[PORTABILITY.md](PORTABILITY.md)와 [COMMANDS.md](COMMANDS.md)도 참고하라.
