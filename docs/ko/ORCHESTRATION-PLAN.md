# Orchestration Plan — multi-machine · multi-account · multi-agent (draft)

**Language:** [English](../en/ORCHESTRATION-PLAN.md) · 한국어

> 상태: **리뷰용 초안** (2026-07-02, `main`에 커밋됨). [ARCHITECTURE.md](ARCHITECTURE.md)의 연장선이다.
> 조사 근거: 1차 자료(Claude Code / Codex CLI 문서, GitHub)를 2026년 중반에 살펴본 내용.
> 정확한 플래그와 모델 ID는 *호출 시점에 다시 확인*할 것 — 두 CLI 모두 자동 업데이트된다.

## 0. 실제로 요청한 것

"멀티 머신 멀티 계정 멀티 에이전트 멀티 서브에이전트 … 리모트·로컬 다, 가능하면 Codex↔Claude Code 오케스트레이션." 이를 독립된 축으로 분해했다(v1 라우터와 같은 방식):

| 축 | 값 | v1 상태 | 이 계획 |
|------|--------|-----------|-----------|
| **machine** | 이 Mac, 다른 Mac, 원격 머신 | 진입만 지원 (`ai remote doctor` + Tailscale) | 라우팅 차원으로 승격 |
| **account** | personal · company | ✅ `CLAUDE_CONFIG_DIR` / `CODEX_HOME` | **Claude/macOS 인증 강화** (§4 참고) |
| **tool** | claude · codex | ✅ 둘 중 하나 실행 | 하나가 다른 하나를 **몰게** 함 (§3) |
| **workspace** | personal · company 트리 | ✅ `cd` + 로그 | 변경 없음; worktree 추가 |
| **agents** | 1 → N 병렬 (+ 서브에이전트) | 없음 | 네이티브 fleet + 오케스트레이터 (§2, §5) |

라우터의 v1 명제(세션 = 직교하는 축들, 각 축을 env var로 고정)는 **1차 자료로 검증됐다**. 이 계획은 그 코어를 건드리지 않고 세 축 — *fleet*, *cross-tool*, *machine-as-target* — 을 더한다.

## 1. v1을 작성한 이후 달라진 것 (지렛대)

1. **Claude Code에 이제 네이티브 fleet 인터페이스가 들어왔다.** `claude agents [--json]`(병렬 백그라운드 세션 모니터/디스패치), `claude --bg/--background` + `attach/logs/stop/respawn/rm <id>`, `claude daemon status|stop`(수퍼바이저), `--worktree/-w` + `--tmux`, **agent teams**(`--teammate-mode {in-process|auto|tmux|iterm2}`, 공유 task-list), 그리고 **Remote Control**(`claude remote-control` — claude.ai / 모바일에서 로컬 세션을 조종). → *fleet 매니저를 새로 만들지 말고, 네이티브를 둘러싸도록 라우팅하라.*
2. **Codex↔Claude 상호 오케스트레이션은 실제로 되고, MCP가 접착제다.** 둘 다 구조화된 JSON으로 헤드리스 실행되고, 둘 다 MCP 클라이언트이며, **둘 다 MCP 서버로 노출될 수 있다**. 그래서 ARCHITECTURE §6("MCP는 범위 밖")은 이제 다시 봐야 할 대목이다.
3. **현재 설계에서 짚어둘 만한 macOS 세부 하나:** ARCHITECTURE §3은 `CLAUDE_CONFIG_DIR`로 "계정 = 어느 폴더냐"를 정한다고 말한다. macOS에서 Claude Code는 OAuth를 config 디렉터리가 아니라 **Keychain**에 저장한다(`~/.claude-*/.credentials.json`은 존재하지 않고, Keychain이 `Claude Code-credentials[-<hash>]`를 갖고 있다). `CLAUDE_CONFIG_DIR`별 격리는 **동작한다** — 서비스 이름이 `Claude Code-credentials-<hash>`이고 hash = `sha256(절대 config-dir 경로)[:8]`(뒤에 슬래시 없음), 기본값 `~/.claude`는 접미사 없는 이름을 쓴다. Claude Code v2.1.198에서 확인: `~/.claude-personal` → `0414a328`, `~/.claude-company` → `98bf7d2c`, 둘 다 별개 항목으로 존재. 주의: 이 메커니즘은 **문서화돼 있지 않고 버전에 의존한다** — 업그레이드 후 다시 확인할 것, 보장된 계약이 아니다. Codex는 깔끔하다(`auth.json`은 `CODEX_HOME` 아래의 평문 파일). → §4에서 이를 확인한다.

## 2. Codex ↔ Claude Code 상호 오케스트레이션 (구체적으로)

두 방향 모두 지금 동작한다:

- **Claude가 Codex를 몬다:** `codex mcp-server`(Codex를 stdio로, `codex()` / `codex-reply()` 도구 노출, `threadId`로 상태 유지)를 Claude의 `--mcp-config`에 등록한다.
- **Codex가 Claude를 몬다:** 커뮤니티 래퍼 `steipete/claude-code-mcp`(`permissionMode` 인자를 받는 단일 `claude_code` 도구 노출)를 `codex mcp add` 한다. 아직 퍼스트파티 "Claude as MCP server" 플래그는 없다.

헤드리스 구성 요소:
- **Codex:** `codex exec "task" --json -o out.txt --output-schema s.json`, `--sandbox {read-only|workspace-write|danger-full-access}`, `-a {untrusted|on-request|never}`, `codex exec resume`.
- **Claude:** `claude -p --output-format stream-json --json-schema '…'`, `--allowedTools`, `--permission-mode`, `--mcp-config`, `--bare`(재현 가능한 스크립트 호출을 위해 자동 탐색을 건너뜀 — `--bare`는 `CLAUDE_CODE_OAUTH_TOKEN`을 무시하니 `ANTHROPIC_API_KEY`를 쓸 것).
- **Claude Agent SDK**("Claude Code SDK"에서 개명): TS `@anthropic-ai/claude-agent-sdk`, Py `claude-agent-sdk`.
- 참고: OpenAI Cookbook "Building Consistent Workflows with Codex CLI & Agents SDK"(오케스트레이터가 `codex mcp-server`를 동시에 호출하고, 각각 자기 cwd/profile을 가짐 — 라우터가 이미 하는 것과 같은 격리).

**라우터와의 궁합:** 이미 강제하고 있는 계정별 격리가 바로 *"personal 계정 오케스트레이터가 company 계정 워커를 몬다"*를 안전하게 만드는 요소다. 이건 새 동사가 된다(§5).

## 3. 멀티 머신 (원격 + 로컬)

표준적이고 검증된 스택 — [REMOTE-ACCESS.md](REMOTE-ACCESS.md)에 이미 절반쯤 문서화돼 있다:
- **Tailscale**(메시 + Tailscale SSH, 공개 SSH 없음) + **tmux/zellij**(연결이 끊겨도 살아남음) + 노트북/폰 클라이언트.
- 조율 기반 옵션들: **공유 task 파일/큐**(Claude agent teams의 라이브 리스트), **락 기반**(`claude_code_agent_farm`), **에이전트별 git 브랜치 + PR/체크포인트 머지**(uzi / claude-squad / crystal).
- **git worktree** = 지배적인 격리 기본기(이제 네이티브: `claude -w`). 주의: worktree는 *런타임이 아니라 파일*을 격리한다(포트/DB/캐시는 공유되고, 디스크는 금방 불어난다) — 필요할 땐 `dagger/container-use`(에이전트/브랜치마다 새 컨테이너)가 그 틈을 메운다.

만들기 전에 살펴볼 만한 OSS 오케스트레이터들(모두 repo로 확인함): `smtg-ai/claude-squad`, `devflowinc/uzi`, `Dicklesworthstone/claude_code_agent_farm`, `dagger/container-use`, `stravu/crystal`, `mco-org/mco`(멀티 CLI). 탐색: `andyrewlee/awesome-agent-orchestrators`.

## 4. 계정 축 강화 (fleet 계획과 무관하게 먼저 할 것)

라우터에서 가장 많이 쓰이는 보장 — 계정 격리 — 은 macOS에서 유지되지만, 메커니즘이 문서화돼 있지 않다. 그래서 강화의 핵심은 그걸 가정하지 말고 **확인**하는 것이다.

- **Claude (macOS): 격리는 동작이 확인됐다.** 각 `CLAUDE_CONFIG_DIR`는 `Claude Code-credentials-<hash>`라는 이름의 자기 Keychain 항목을 갖는다. hash = `sha256(절대 config-dir 경로)[:8]`(뒤에 슬래시 없음), 기본값 `~/.claude`는 접미사 없는 이름을 쓴다. v2.1.198에서 확인(`~/.claude-personal` → `0414a328`, `~/.claude-company` → `98bf7d2c`, 둘 다 별개 항목으로 존재). 이건 **문서화돼 있지 않고 버전에 의존한다** — 계약이 아니라 업그레이드 후 다시 확인할 대상으로 다뤄라.
- **여기서 예전에 거론됐던 "튼튼한 해법" 둘은 모두 macOS에선 막다른 길이다 — 어느 쪽도 추진하지 말 것:**
  1. **루트별로 파일 기반 `.credentials.json` 강제** — 이걸 위한 *지원되는 macOS 스위치가 없다*(기능 요청은 아직 열려 있음). Linux/Windows만 creds를 파일에 쓰고, macOS에선 저장소가 항상 Keychain이다.
  2. **계정별 `CLAUDE_CODE_OAUTH_TOKEN`** — issue #37512를 유발한다: 토큰 env로 실행하면 프로세스 종료 시 공유 `Claude Code-credentials` Keychain 항목이 조용히 *삭제*되어, VS Code 확장과 다른 세션들이 깨진다. 별개로, `ANTHROPIC_API_KEY`는 Claude Code의 인증 우선순위 체인에서 구독 OAuth보다 **우선한다**. 그래서 키를 export하면 구독 요금제 대신 API 계정에 조용히 과금될 수 있다.
- **Codex:** `CODEX_HOME`으로 이미 완전히 격리돼 있다. 코드로 못 박아둘 규칙 하나: **루트끼리 `auth.json`을 절대 복제하지 말 것**(refresh 토큰은 일회용이라 복사본은 곧 쓸모없어진다). `ai doctor`는 두 루트가 같은 `auth.json` fingerprint를 공유하면 경고해야 한다.
- **출시된 것 — `ai doctor` 검증(가정이 아니라):** 각 Claude 계정마다 `sha256(config-dir)[:8]`을 계산하고, `security find-generic-password -s "Claude Code-credentials-<hash>"`를 **존재 여부만** 확인하는 용도로 실행하며(비밀 값은 절대 읽지 않음), `isolated ✓` 또는 `not logged in`을 보고하면서 메커니즘이 버전 의존적임을 표시한다. 또한 환경에 `CLAUDE_CODE_OAUTH_TOKEN`(#37512)이나 `ANTHROPIC_API_KEY`(과금 우선순위)가 설정돼 있으면 **경고**하고, 복제된 Codex `auth.json`에도 경고한다. 이건 "지금 대체 어느 계정이 활성인가?"라는 혼란의 재발을 곧바로 막아준다.

## 5. 목표 아키텍처 — 단계별

### Phase A — 라우터-런처 + 네이티브 fleet (가장 얇음, 단기 추천)
`ai`를 env-var/가드레일 런처로 유지한다. Claude Code의 네이티브 fleet로 진입하는 동사들을 추가하고, 계정×워크스페이스마다 pane 하나를 둔다:
- `ai fleet <ws> [--account X] [-n N]` → `claude agents` / `--bg` + tmuxp 레이아웃.
- `ai worktree <ws> <branch>` → 격리된 worktree에서 `claude -w`.
- 원격은 Tailscale SSH + tmux 그대로(문서화됨). 새 데몬 없음.
- 상호 오케스트레이션은 옵트인: `ai claude … --mcp-config <codex-mcp-server.json>`.

### Phase B — MCP 메시 컨트롤 플레인 (중간)
각 머신이 계정별 런타임(Claude Agent SDK / Codex-via-Agents-SDK)을 돌리고, 이 런타임은 MCP를 소비하는 동시에 노출한다(`codex mcp-server`, `claude-code-mcp`). 얇은 브로커(tailnet 위의 SQLite 큐 / NATS / Redis)가 task 봉투를 `machine × tool × account`로 라우팅한다. `ai`는 각 노드를 알맞은 `CLAUDE_CONFIG_DIR` / `CODEX_HOME` / 토큰으로 띄우는 **부트스트래퍼**가 된다. 재시도/중복 제거는 직접 책임진다.

### Phase C — 내구성 있는 컨트롤 플레인 (가장 무거움; 신뢰성이 요구할 때만)
노드 런타임은 B와 같지만, 밑에 **Temporal**을 깔아 크래시에 강하고 재개 가능한 장시간 원격 잡을 돌린다(머신별 워커가 원격+로컬 토폴로지에 매핑됨). "노트북이 잠들어도 잡이 살아남았다"가 반드시 필요할 때만 채택한다.

**추천:** 지금은 **A**를 출시하고(위험 낮음, 즉시 가치, 네이티브 기본기 재사용), **B**는 두 계정에 걸쳐 Claude 오케스트레이터 하나가 Codex 워커 하나를 모는 `ai orchestrate` 프로토타입으로 스파이크하며, **C**는 진짜 내구성 필요가 나타날 때까지 미룬다.

## 6. 구체적인 다음 단계

1. **✅ (출시됨)** `ai doctor`에 §4를 강화 — 계정별 존재 확인만 하는 Keychain 격리 체크 + `CLAUDE_CODE_OAUTH_TOKEN`/`ANTHROPIC_API_KEY`/복제된 `auth.json` 경고. 순수 진단이고, 동작 변경 없음.
2. **(작음)** ARCHITECTURE §3(macOS 인증 주의)과 §6(MCP를 이제 축으로서 범위 안에)을 개정.
3. **(Phase A)** 네이티브 Claude 플래그를 감싸는 `ai worktree`와 `ai fleet` 동사 추가; 계정×워크스페이스별 tmuxp 레이아웃 템플릿 추가.
4. **(Phase A)** 선택적 `share/mcp/codex-mcp-server.json`과 `ai claude … --orchestrate-codex` 슈가를 추가해 `codex mcp-server`를 Claude 세션에 연결.
5. **(Phase B 스파이크)** `ai orchestrate` PoC: Claude(personal, 오케스트레이터) → Codex(company, 워커)를 MCP로, task 하나, 구조화 JSON 왕복, 워크스페이스 transcript에 기록.

## 7. 열린 결정 (만들기 전에 당신의 판단이 필요)
- **인증 강화: 해결됨 (§4).** 예전 후보 둘(파일 기반 creds, env-token 래퍼)은 macOS 막다른 길이고, 네이티브 `CLAUDE_CONFIG_DIR` 격리는 동작이 확인됐으며 `ai doctor`가 이제 그걸 검증한다. 여기서 결정할 건 없다. (헤드리스/원격 무인 실행은 §5의 열린 질문으로 남지만, #37512 때문에 계정별 OAuth 토큰 방식은 아니다.)
- **Fleet 조율 기반:** 에이전트별 git 브랜치(가장 단순, PR 리뷰 친화) vs 공유 task 파일(더 밀착, Claude 네이티브) vs 에이전트별 컨테이너(가장 무겁고, 진짜 런타임 격리).
- **상호 오케스트레이션의 기본 정체성:** 어느 계정이 오케스트레이터이고 어느 쪽이 워커인가(과금/rate-limit에 영향).
- **v1에서 "멀티 머신"의 범위:** 이 Mac + 원격 머신 하나만인가, 아니면 진짜 N-노드 tailnet fleet인가?

## 8. 표시 / 의존하기 전에 확인할 것
- `Claude Code-credentials-<sha256(config-dir)[:8]>` hash 접미사: 동작 확인됨(v2.1.198)이지만 **문서화돼 있지 않고 버전에 의존한다** — 업그레이드 후 다시 확인, 계약 아님. `ai doctor`가 계정별로 존재를 확인한다.
- `codex mcp-server`는 더 신규/실험적으로 읽힌다 — Codex 버전을 고정하라.
- Conductor / Nimbalyst은 제품이지 확인된 OSS repo가 아니다; `vibe-kanban`은 종료 수순이다; `parruda/claude-swarm` URL은 죽었다.
- 정확한 모델 ID와 repo 스타 수는 특정 시점 기준이다.
