# 바닐라로 되돌리기 (teardown)

**Language:** [English](../en/TEARDOWN.md) · 한국어

`ai` 라우터를 머신에서 걷어내고 macOS를 설치 전 상태로 되돌리는 방법. 2026-07-08에
이 저장소를 보관하면서 실제로 돌린 절차를 그대로 기록한다. 세션 라우팅은 이제 Orca가 맡는다.

핵심 규칙 하나: **`install.sh`가 만든 것만 지운다.** 바닐라 설치(`~/.claude`, `~/.codex`)와
다른 도구가 함께 쓰는 설정은 건드리지 않는다.

## 지우는 것 / 남기는 것

| 지우는 것 | 남기는 것 |
|-----------|-----------|
| `~/.local/bin/ai` 심볼릭 링크 + `ai.bak.*` 백업 | `~/.claude`, `~/.codex` (바닐라) |
| 설정 `~/.config/ai-session-router/` | `~/.local/bin` PATH 한 줄 (claude·codex 등도 쓴다) |
| 로그 `<workspace>/.ai-logs/` | 기본 브라우저·데스크톱 앱 프로필 |
| 공유 저장소 `~/.ai-shared/` | |
| 계정 격리 디렉터리 `~/.claude-<id>` · `~/.codex-<id>` · `~/.claude-app-<id>` · `~/.ai-browser-<id>` | |
| Keychain의 `Claude Code-credentials-<hash>` 격리 항목 | Keychain의 기본 `Claude Code-credentials` (= `~/.claude`) |

`~/.ai-shared/`에는 계정별 `skills`가 심볼릭 링크로 걸려 있다. 계정 디렉터리를 함께 지울
때만 통째로 정리한다.

## 먼저: 대화 기록부터 지키기

계정 격리 디렉터리 안에는 세션 기록(`*.jsonl`)이 들어 있다. **지우기 전에 이게 바닐라에도
있는지 확인한다.** 없으면 옮기고 나서 지운다.

- Claude Code 세션은 `<config-dir>/projects/` 아래에 쌓인다. 오늘 작업이 바닐라
  `~/.claude/projects/`에 있으면 격리 디렉터리를 지워도 기록은 남는다. 확인:

  ```sh
  find ~/.claude/projects -name '*.jsonl' -newermt 'today' | wc -l
  ```

- Codex 세션은 `<CODEX_HOME>/sessions/` 아래에 쌓인다. Orca로 띄운 codex는 Orca 런타임
  홈에 있으니, 필요하면 바닐라로 합친다(누락·최신만 복사, 삭제 없음):

  ```sh
  rsync -a --update \
    "$HOME/Library/Application Support/orca/codex-runtime-home/home/sessions/" \
    "$HOME/.codex/sessions/"
  ```

- `ctx`(로컬 에이전트 기록 검색 도구)는 바닐라 경로만 인덱싱한다. 격리 디렉터리는 인덱싱한
  적이 없으므로, 거기에만 있던 예전 기록은 디렉터리를 지우면 되살릴 수 없다. 백업·스냅샷이
  없다면 지우기 전에 반드시 옮겨라.

## Keychain 정리 (macOS)

계정 인증은 파일이 아니라 Keychain 항목에 있다. 이름은 `Claude Code-credentials-<hash>`이고
hash는 config 디렉터리 경로에서 나온다. 먼저 목록을 보고, 사라진 디렉터리에 딸린 항목만
정리한다.

```sh
ai keychain list                 # default / active / orphan 분류
ai keychain prune --force --yes  # orphan만 삭제, default·active는 유지
```

`prune`은 사라진 config 디렉터리에 딸린 항목만 지운다. 계정 디렉터리를 먼저 지우면 그 항목이
active에서 orphan으로 바뀌므로, **Keychain 정리를 계정 디렉터리 삭제보다 먼저** 하거나, 남은
항목은 정확한 이름으로 직접 지운다:

```sh
security delete-generic-password -s "Claude Code-credentials-<hash>"
```

기본 `~/.claude`에 딸린 접미사 없는 `Claude Code-credentials`는 건드리지 않는다.

## 파일 삭제

```sh
# 배관
rm -f  ~/.local/bin/ai ~/.local/bin/ai.bak.*
rm -rf ~/.config/ai-session-router
rm -rf ~/dev/personal/.ai-logs ~/dev/work/.ai-logs   # 본인 워크스페이스 경로에 맞게
rm -rf ~/.ai-shared

# 계정 격리 디렉터리 (기록을 옮긴 뒤에)
rm -rf ~/.claude-*    # ~/.claude 는 글롭에 안 걸린다 (하이픈 없음)
rm -rf ~/.codex-* ~/.ai-browser-*
```

`~/.claude-*` 글롭은 `~/.claude`(바닐라)를 건드리지 않는다. 하이픈이 없으니 매칭되지 않는다.
불안하면 디렉터리를 하나씩 이름으로 지운다.

## 실행 중인 앱 주의

데이터 디렉터리를 여전히 열고 있는 프로세스가 있으면 그 디렉터리를 지우지 마라. 먼저 종료한다.

```sh
lsof -w | grep -E '\.claude-app-|\.ai-browser-'   # 무엇이 잡고 있는지
osascript -e 'quit app "Claude"'                  # 데스크톱 앱 정상 종료
```

## `.zshrc`

이 라우터는 `.zshrc`에 아무것도 자동으로 넣지 않는다. `ai guard install` / `ai prompt install`을
직접 돌려 넣은 줄이 있으면 그 줄만 지운다. `export PATH="$HOME/.local/bin:$PATH"`는 다른
도구도 쓰니 남겨둔다.

## 확인

```sh
command -v ai || echo "ai 없음 (정상)"
ls -d ~/.claude ~/.codex                 # 바닐라는 그대로 있어야 함
ls -d ~/.claude-* ~/.codex-* 2>/dev/null # 아무것도 안 나오면 정리 완료
```

## 마지막으로

저장소 자체(`~/dev/personal/ai-session-router`)는 심볼릭 링크가 사라진 순간부터 아무 일도
하지 않는다. 필요 없으면 `rm -rf`로 지우거나 GitHub에서 archive 처리하면 된다.
