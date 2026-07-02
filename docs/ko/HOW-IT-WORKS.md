# 원리 설명

**Language:** [English](../en/HOW-IT-WORKS.md) · 한국어

`ai`가 속으로 실제 뭘 하는지 쉬운 말로 풀었다. [ARCHITECTURE.md](../en/ARCHITECTURE.md)가
너무 추상적이었다면 여기부터 보면 된다.

## 핵심 한 가지

터미널 AI 도구(Claude Code, Codex)는 로그인·대화 기록·설치한 플러그인·스킬·설정을 **전부
폴더 하나**에 넣어둔다. 어느 폴더를 쓸지는 환경변수 하나가 정한다.

- Claude Code는 `CLAUDE_CONFIG_DIR`을 본다
- Codex는 `CODEX_HOME`을 본다

이게 전부다. `ai`는 네가 고른 계정에 맞게 이 변수만 다른 폴더로 바꿔놓고 도구를 실행한다.

```
ai claude company   →   export CLAUDE_CONFIG_DIR=~/.claude-company   →   claude
ai claude personal  →   export CLAUDE_CONFIG_DIR=~/.claude-personal  →   claude
```

폴더 하나가 서랍 하나라고 보면 된다. `personal`과 `company`는 서랍 두 개다. 도구는 네가
가리킨 서랍만 열어 보니까 둘이 안 섞인다. 개인 결제는 개인에, 회사 기록은 회사에 남는다.

## 명령어 하나 = 서로 무관한 선택 몇 개

`ai` 명령은 사실 서로 영향을 안 주는 손잡이 몇 개를 돌리는 일이다.

| 손잡이 | 값 | 정하는 것 | 무엇으로 |
|--------|-----|-----------|----------|
| **도구** | `claude` / `codex` | 어떤 AI CLI가 뜰지 | 서브커맨드 |
| **계정** | `personal` / `company` | 로그인·플러그인·스킬·기록 (= 어느 폴더) | `CLAUDE_CONFIG_DIR` / `CODEX_HOME` |
| **워크스페이스** | `personal` / `company` | 어느 프로젝트 폴더로 들어갈지 + 로그 위치 | 그 폴더로 `cd` |
| **표면** | 터미널 / 앱 / 브라우저 | AI와 *어떻게* 대화할지 | `claude`냐 `gui`냐 |

`ai codex company --account personal` = "Codex를 실행하고, 회사 프로젝트 폴더에서 작업하되,
로그인은 개인 계정으로." 손잡이 하나 바꿔도 나머지는 그대로다.

## "Claude" 여는 방법이 세 가지 (다들 여기서 헷갈린다)

Claude라고 부르는 게 **세 종류**고, 셋은 플러그인을 공유하지 않는다.

1. **터미널 Claude Code**: `ai claude personal`
   터미널에서 뜬다. config 폴더를 읽으니 플러그인·스킬이 다 있고, `/plugin`·`/skills`·`/mcp`
   명령도 여기서만 먹는다.

2. **데스크톱 앱**: `ai gui personal`
   아이콘 눌러 여는 그 **앱** 창을 계정별로 격리해서 띄운다
   (`--user-data-dir=~/.claude-app-personal`). 이건 채팅 앱이라 CLI 플러그인을 아예 안 쓴다.
   데이터에 `plugins/` 폴더 자체가 없고, `/plugin`을 치면 *"isn't available in this
   environment"*이라고 뜬다. 그 메시지는 "여긴 앱이지 터미널이 아니다"라는 뜻일 뿐이다.

3. **브라우저**: `ai gui personal --browser` (또는 개인 Edge / 회사 Chrome 경로)
   그냥 claude.ai / chatgpt.com을 맞는 신분으로 브라우저에 연다.

**기억할 것:** 플러그인·스킬은 **터미널**(`ai claude`)에 산다. 앱과 브라우저는 못 쓴다.

## 플러그인 / 스킬 / MCP는 실제로 어디 있나

- **플러그인과 스킬**은 계정 폴더 안의 파일이다: `~/.claude-<계정>/plugins/`,
  `~/.claude-<계정>/skills/`. 그래서 **계정마다 따로**다. 계정을 바꾸면 폴더가 바뀌고
  플러그인도 바뀐다. 플러그인이 "사라졌다"면 대개 그게 없는 폴더(계정)를 보고 있는 거지,
  뭐가 지워진 게 아니다.
- **MCP 서버는 여기 일반 설정으로 저장되지 않는다.** 두 군데서 온다. 하나는 MCP 서버를
  같이 담은 플러그인, 하나는 로그인한 계정에 서버 쪽으로 묶인 claude.ai 커넥터다. 커넥터가
  계정마다 다시 인증을 요구하는 이유가 이거다. 애초에 로컬 파일이 아니라 잃어버릴 것도 없다.

## 터미널 현재 위치가 영향을 주나

- **`ai gui`: 안 준다.** 지금 어디 있는지 아예 안 본다. 앱 데이터 폴더는 고정 절대경로
  (`~/.claude-app-company`)고, 어느 앱이 열리냐는 `personal`/`company` 인자만 정한다.
  아무 데서나 쳐도 결과가 같다.
- **`ai claude` / `ai codex`: 조금 준다.** 워크스페이스로 대신 `cd`해 준다(인자가 정함,
  예: `personal` → `~/dev/personal`). 그 워크스페이스 *밖*에서 시작했으면 경고부터 띄우고,
  그래도 안으로 옮겨 준다.

## 실제 흐름 한 번

```
$ ai claude company
```

1. 도구 = `claude`, 워크스페이스 = `company`, 계정은 기본값 `company`
2. 현재 위치가 회사 워크스페이스 밖이면 경고, secret처럼 생긴 파일 있으면 경고
3. `export CLAUDE_CONFIG_DIR=~/.claude-company`
4. `cd ~/dev/work`
5. `~/dev/work/.ai-logs/claude/company-account/` 아래에 기록(transcript) 남김
6. `claude` 실행. 이제 회사 로그인·회사 플러그인·회사 스킬이 보인다

## 빠른 참조

| 하고 싶은 것 | 명령 |
|--------------|------|
| 터미널 Claude, 회사 계정 | `ai claude company` |
| 터미널 Claude, 개인 계정 | `ai claude personal` |
| 터미널 Codex, 회사 계정 | `ai codex company` |
| Claude **앱** 열기 (회사) | `ai gui company` |
| 플러그인 설치/사용 | 터미널에서만: `ai claude <계정>` 후 `/plugin …` |
| 설정이 제대로 물렸나 점검 | `ai doctor` |

## 자주 헷갈리는 것

- **"`/plugin isn't available`"** → 지금 **앱**(`ai gui`)에 있다. 플러그인은 **터미널**
  (`ai claude`)에서만 된다.
- **"다른 계정에서 내 플러그인이 안 보여"** → 계정이 다르면 폴더가 다르다. 거기서도 설치하거나,
  아니면 만든 계정에만 있는 상태다.
- **"지금 내가 어느 계정이지?"** → macOS에선 Claude 로그인이 폴더가 아니라 Keychain에 있다.
  `ai doctor`의 auth 항목을 보거나 세션 안에서 `/status`로 확인한다.
