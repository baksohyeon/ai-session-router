# 명령어 레퍼런스

**Language:** [English](../en/COMMANDS.md) · 한국어

```
ai gui     <personal|company> [--browser] [--dry-run]      # 네이티브 Claude 앱, 없으면 격리된 브라우저 인스턴스
ai gui     setup [--print]                                 # 브라우저 감지, 신원 → router.env 매핑
ai shell   <personal|company>                              # 워크스페이스로 cd된 서브셸
ai claude  <personal|company> [--account p|c] [-- args]    # Claude Code 실행
ai codex   <personal|company> [--account p|c] [-- args]    # Codex 실행
ai tmux    <personal|company>                              # ai-<ws> 세션 attach/생성
ai keychain <list|prune> [--force] [--keep DIR]            # 남은 Claude 키체인 인증 정보 점검/정리 (macOS)
ai doctor                                                  # 로컬 진단
ai remote doctor                                           # tailscale / sshd / tmux / 호스트
ai logs                                                    # 저장된 트랜스크립트 목록
ai resolve <claude|codex> <ws> [--account p|c]             # DRY-RUN 미리보기 (실행 안 함)
```

## 규칙

- **`ai gui <personal|company>`** 는 계정별 `--user-data-dir`(`~/.claude-app-<account>`)로
  네이티브 Claude 데스크톱 앱을 실행한다. 그래서 personal과 company가 따로, 동시에
  로그인 상태를 유지한다. `Claude.app`이 없으면(또는 macOS가 아니면) **브라우저 신원 경로**로
  넘어간다. `--browser`는 이 경로를 강제하고, `--dry-run`은 실행하지 않고 정확한 실행
  명령만 출력한다. 앱 데이터 디렉터리는 CLI 루트(`~/.claude-<account>`)와 별개다. 네이티브
  격리는 Electron에서만 되고, ChatGPT(네이티브 AppKit)는 이 방식으로 격리할 수 없어서
  브라우저 경로를 쓴다.
- **브라우저 신원 경로(일반).** 신원 하나당 격리된 브라우저 인스턴스 하나. 데스크톱 앱이
  쓰는 것과 같은 `--user-data-dir` 방식으로 실행한다. 특정 브라우저나 미리 만든 프로필이
  꼭 필요하지는 않고, 격리된 데이터 디렉터리는 자동으로 만들어진다. 방식은 두 가지다:
  - **격리된 데이터 디렉터리**(기본) — `--user-data-dir=${AI_BROWSER_DATA_PREFIX}<id>`.
    설정이 없어도 되고 깨끗한 상태로 시작한다. 그 안에서 브라우저 계정에 로그인하면
    Chromium 동기화가 걸려서, 한 번 로그인하면 북마크/확장/비밀번호가 채워진다.
  - **기존 프로필**(신원별로 켜서 씀) — `AI_GUI_PROFILE_<id>`를 지정하면 `--profile-directory=<name>`으로
    기존 프로필의 로그인/북마크를 재사용한다.

  아이콘을 눌러 여는 평소 쓰는 브라우저(기본 데이터 디렉터리)는 건드리지 않는다.
  `ai gui`는 항상 별도의 격리된 인스턴스를 실행한다. 브라우저를 못 찾으면 OS 기본 브라우저로
  URL을 열고 `ai gui setup`을 실행하라고 알려준다.
- **`ai gui setup [--print]`** 은 한 번만 돌리는 도우미다. 설치된 Chromium 브라우저(Edge,
  Chrome, Brave, Arc, Chromium)를 감지하고, 각 브라우저의 기존 프로필을 나열한 다음,
  신원마다 (브라우저, 격리 | 프로필, URL)을 매핑하도록 물어보고, 관련된 `AI_*` 줄만
  `router.env`에 쓴다(무관한 줄은 절대 덮어쓰지 않음). `--print`는 아무것도 바꾸지 않고
  무엇을 쓸지 보여준다. setup은 편의 기능이지 필수 관문이 아니다. 한 번도 안 돌려도
  기본값(자동 감지된 브라우저로 격리된 데이터 디렉터리)이 그대로 동작한다. 런타임에서
  `ai gui`를 실행할 때는 항상 비대화식이다. 설정 변수: `AI_BROWSER`,
  `AI_BROWSER_DATA_PREFIX`, `AI_GUI_BROWSER_<id>`, `AI_GUI_URLS_<id>`, `AI_GUI_PROFILE_<id>`.
  예전 방식인 `AI_CHROME_COMPANY_PROFILE` / `AI_COMPANY_*_URL`도 폴백으로 여전히 인정하므로
  기존 설정은 그대로 동작한다. 마이그레이션을 강제하지 않는다.
- **기본 계정**은 워크스페이스를 따른다: `personal`→personal, `company`→company.
- **덮어쓰기**는 `--account personal|company`로 한다.
- **`--` 패스스루**: `--` 뒤에 오는 것은 전부 그대로 도구에 넘긴다.
  예: `ai codex company --account personal -- doctor` 는 실제 래퍼 경로를 거쳐 `codex doctor`를
  비대화식으로 실행한다(테스트할 때 편함).

## 예시

| 명령어 | 워크스페이스 | 계정 환경 변수 | 로그 |
|---------|-----------|-------------|------|
| `ai claude personal` | `~/dev/personal` | `CLAUDE_CONFIG_DIR=~/.claude-personal` | `~/dev/personal/.ai-logs/claude/personal-account/` |
| `ai codex company` | `~/dev/work` | `CODEX_HOME=~/.codex-company` | `~/dev/work/.ai-logs/codex/company-account/` |
| `ai codex company --account personal` | `~/dev/work` | `CODEX_HOME=~/.codex-personal` | `~/dev/work/.ai-logs/codex/personal-account/` |

## 키체인 관리 (macOS)

macOS의 Claude Code는 각 `CLAUDE_CONFIG_DIR`의 OAuth를 키체인 서비스
`Claude Code-credentials-<sha256(dir)[:8]>`에 저장한다(기본값 `~/.claude`는 접미사 없는
그냥 이름을 쓴다). 한 번이라도 로그인한 설정 디렉터리는 항목을 하나 남기는데, 이게
정리되지 않고 계속 쌓인다.

- **`ai keychain list`** 는 모든 `Claude Code-credentials*` 항목을 *default*(그냥 `~/.claude`),
  *active*(해시가 기존 설정 디렉터리와 일치), *orphan*(일치하는 디렉터리 없음)으로 분류한다.
  존재 여부와 라벨만 본다 — **비밀 값은 절대 읽지 않는다**.
- **`ai keychain prune`** 은 **기본이 dry-run**이다: 지울 orphan 항목을 출력만 하고 전부
  그대로 둔다. 실제로 지우려면 **`--force`**를 붙인다 — 그래도 지우는 것은 *orphan* 항목뿐이고,
  그냥 항목이나 active 계정의 항목은 건드리지 않는다.
- **`--keep DIR`**(여러 번 쓸 수 있음)은 항목을 active로 취급할 설정 디렉터리를 화이트리스트에
  넣는다 — `~/.claude*` 밖에 있는 devcontainer/worktree 루트에 쓴다. 안 그러면 orphan처럼
  보이기 때문이다.

권장 순서: `ai keychain list`로 orphan을 눈으로 확인하고, `ai keychain prune`(dry-run)으로
한 번 더 확인한 뒤, 그때 `ai keychain prune --force`를 돌린다.

## 진단

- `ai doctor` — OS, 셸, PATH, 도구 가용성, 브라우저, 워크스페이스 경로, 설정 루트(존재/없음),
  계정별 인증 격리(macOS에서는 키체인 항목 검증), 키체인 스킴 버전 가드, 예시 로그 해석,
  사용 중인 설정 파일. GUI에 대해서는 신원별로 해석된 브라우저, 방식(데이터 디렉터리 vs
  프로필), 해석된 데이터 디렉터리 / 프로필과 존재/없음 상태도 알려준다.
- `ai remote doctor` — 호스트명, 사용자, Tailscale 상태/IP, sshd 리슨 확인, tmux 세션.
  **Tailscale을 설정하지는 않는다.**
- `ai resolve …` — 실행하면 무엇을 할지(환경 변수, cwd, 로그)를 **실행하지 않고** 정확히
  출력한다. 헷갈릴 때마다 쓰면 된다.

## 종료 코드

`2` = 사용법/검증 오류 · `127` = 도구가 PATH에 없음 · `1` = 알 수 없는 명령 / cd
실패 · 그 외에는 감싼 도구 자신의 종료 코드.
