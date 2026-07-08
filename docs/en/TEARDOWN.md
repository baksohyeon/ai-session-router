# Reverting to vanilla (teardown)

**Language:** English · [한국어](../ko/TEARDOWN.md)

How to remove the `ai` router from a machine and return macOS to its pre-install state.
This records the exact procedure run on 2026-07-08 when the repo was archived. Session
routing is now handled by Orca.

One rule: **only delete what `install.sh` created.** The vanilla installs (`~/.claude`,
`~/.codex`) and anything other tools share are left untouched.

## Removed / kept

| Removed | Kept |
|---------|------|
| `~/.local/bin/ai` symlink + `ai.bak.*` backups | `~/.claude`, `~/.codex` (vanilla) |
| config `~/.config/ai-session-router/` | the `~/.local/bin` PATH line (claude, codex, etc. use it too) |
| logs `<workspace>/.ai-logs/` | default browser + desktop-app profiles |
| shared store `~/.ai-shared/` | |
| account dirs `~/.claude-<id>` · `~/.codex-<id>` · `~/.claude-app-<id>` · `~/.ai-browser-<id>` | |
| Keychain `Claude Code-credentials-<hash>` isolation entries | Keychain default `Claude Code-credentials` (= `~/.claude`) |

`~/.ai-shared/` holds per-account `skills` as symlinks. Only clear it wholesale when you
delete the account dirs as well.

## First: preserve conversation history

The account isolation dirs contain session transcripts (`*.jsonl`). **Check they also
exist in the vanilla locations before deleting.** If not, move them first.

- Claude Code sessions live under `<config-dir>/projects/`. If today's work is in vanilla
  `~/.claude/projects/`, deleting the isolation dir keeps that history. Verify:

  ```sh
  find ~/.claude/projects -name '*.jsonl' -newermt 'today' | wc -l
  ```

- Codex sessions live under `<CODEX_HOME>/sessions/`. Codex launched by Orca lands in the
  Orca runtime home, so merge into vanilla if needed (copy new/updated only, no delete):

  ```sh
  rsync -a --update \
    "$HOME/Library/Application Support/orca/codex-runtime-home/home/sessions/" \
    "$HOME/.codex/sessions/"
  ```

- `ctx` (a local agent-history search tool) indexes only the vanilla paths. It never
  indexed the isolation dirs, so history that lived only there cannot be recovered once
  the dir is gone. With no backup or snapshot, move it before deleting.

## Keychain cleanup (macOS)

Account auth lives in Keychain entries, not files. Each is named
`Claude Code-credentials-<hash>`, where the hash derives from the config dir path. List
first, then remove only entries whose dir is gone.

```sh
ai keychain list                 # classifies default / active / orphan
ai keychain prune --force --yes  # deletes orphans only; keeps default + active
```

`prune` only removes entries whose config dir no longer exists. If you delete the account
dirs first, their entries flip from active to orphan, so run **Keychain cleanup before
deleting the account dirs**, or remove the leftovers by exact name:

```sh
security delete-generic-password -s "Claude Code-credentials-<hash>"
```

Never touch the suffix-less `Claude Code-credentials` — that is the default `~/.claude`.

## Delete files

```sh
# plumbing
rm -f  ~/.local/bin/ai ~/.local/bin/ai.bak.*
rm -rf ~/.config/ai-session-router
rm -rf ~/dev/personal/.ai-logs ~/dev/work/.ai-logs   # adjust to your workspace paths
rm -rf ~/.ai-shared

# account isolation dirs (after moving history)
rm -rf ~/.claude-*    # does NOT match ~/.claude (no hyphen)
rm -rf ~/.codex-* ~/.ai-browser-*
```

The `~/.claude-*` glob does not touch vanilla `~/.claude`; it has no hyphen so it does not
match. If unsure, delete each dir by name.

## Watch for running apps

Do not delete a data dir a process is still holding open. Quit it first.

```sh
lsof -w | grep -E '\.claude-app-|\.ai-browser-'   # what is holding it
osascript -e 'quit app "Claude"'                  # graceful quit of the desktop app
```

## `.zshrc`

The router adds nothing to `.zshrc` on its own. If you ran `ai guard install` /
`ai prompt install`, remove only those lines. Keep
`export PATH="$HOME/.local/bin:$PATH"` — other tools rely on it.

## Verify

```sh
command -v ai || echo "no ai (good)"
ls -d ~/.claude ~/.codex                 # vanilla must still be there
ls -d ~/.claude-* ~/.codex-* 2>/dev/null # nothing printed = clean
```

## Finally

The repo itself (`~/dev/personal/ai-session-router`) does nothing once the symlink is
gone. Delete it with `rm -rf` if you don't need it, or archive it on GitHub.
