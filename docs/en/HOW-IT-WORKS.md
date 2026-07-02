# How it works

A plain-English explanation of what `ai` actually does under the hood. If
[ARCHITECTURE.md](ARCHITECTURE.md) felt too abstract, start here.

## The one idea

CLI AI tools (Claude Code, Codex) keep **all** of their state — your login, chat
history, installed plugins, skills, settings — inside **one folder**. Which folder
they use is decided by a single environment variable:

- Claude Code reads `CLAUDE_CONFIG_DIR`
- Codex reads `CODEX_HOME`

That's the whole trick. The `ai` router just sets that variable to a different folder
depending on which account you asked for, then launches the tool. Nothing magical.

```
ai claude company   →   export CLAUDE_CONFIG_DIR=~/.claude-company   →   claude
ai claude personal  →   export CLAUDE_CONFIG_DIR=~/.claude-personal  →   claude
```

Think of each folder as a separate drawer. `personal` and `company` are two drawers.
The tool only ever looks in the one drawer you point it at, so nothing leaks between
them: personal billing stays personal, work history stays at work.

## One command = a few independent choices

Every `ai` command is really you picking a few knobs that don't affect each other:

| Knob | Values | Decides | Set by |
|------|--------|---------|--------|
| **tool** | `claude` / `codex` | which AI CLI runs | the subcommand |
| **account** | `personal` / `company` | login, plugins, skills, history (= which folder) | `CLAUDE_CONFIG_DIR` / `CODEX_HOME` |
| **workspace** | `personal` / `company` | which project folder you land in + where logs go | `cd` into it |
| **surface** | terminal / app / browser | *how* you talk to the AI | which subcommand (`claude` vs `gui`) |

`ai codex company --account personal` = "run Codex, work in the company project folder,
but log in with the personal account." Every knob is independent.

## The three ways to open "Claude" (this is the part that trips people up)

There are **three different things** called Claude, and they do not share plugins.

1. **Terminal Claude Code** — `ai claude personal`
   Runs in your terminal. Reads a config folder, so it has your plugins and skills, and
   the `/plugin`, `/skills`, `/mcp` commands work here.

2. **Desktop app** — `ai gui personal`
   Opens the Claude **app** (the window you'd open by clicking the icon), isolated per
   account via `--user-data-dir=~/.claude-app-personal`. This is the chat app. It does
   **not** use CLI plugins at all — there is no `plugins/` folder in its data, and
   `/plugin` will say *"isn't available in this environment."* That message just means
   "you're in the app, not the terminal."

3. **Browser** — `ai gui personal --browser` (or the personal Edge / company Chrome path)
   Just opens claude.ai / chatgpt.com in a browser with the right identity.

**Rule of thumb:** plugins and skills live in the **terminal** (`ai claude`). The app and
the browser can't use them.

## Where plugins / skills / MCP actually live

- **Plugins and skills** are files inside the account folder:
  `~/.claude-<account>/plugins/` and `~/.claude-<account>/skills/`. So they are
  **per-account**. Switch account → different folder → different plugins. If a plugin
  "disappeared," it usually means you're looking at an account whose folder doesn't have
  it — not that anything was deleted.
- **MCP servers are not stored as plain config here.** They come from two places: plugins
  that bundle an MCP server, and claude.ai connectors that are tied to your logged-in
  account on the server side. That's why a connector can need re-authentication per
  account — it was never a local file to lose.

## Does the terminal's current directory matter?

- **`ai gui` — no.** It never looks at where you are. The app's data folder is a fixed
  absolute path (`~/.claude-app-company`), and which app opens depends only on the
  `personal` / `company` argument. Run it from anywhere; same result.
- **`ai claude` / `ai codex` — a little.** They `cd` into the workspace for you (picked by
  the argument, e.g. `personal` → `~/dev/personal`). If you started *outside* that
  workspace, you get a warning first, then it moves you in anyway.

## A concrete walkthrough

```
$ ai claude company
```

1. tool = `claude`, workspace = `company`, account defaults to `company`
2. warns if your current dir is outside the company workspace; warns on secret-looking files
3. `export CLAUDE_CONFIG_DIR=~/.claude-company`
4. `cd ~/dev/work`
5. records a transcript under `~/dev/work/.ai-logs/claude/company-account/`
6. launches `claude` — which now sees the company login, company plugins, company skills

## Cheat sheet

| I want to… | Command |
|------------|---------|
| Terminal Claude, work account | `ai claude company` |
| Terminal Claude, personal account | `ai claude personal` |
| Terminal Codex, work account | `ai codex company` |
| Open the Claude **app** (work) | `ai gui company` |
| Install/use a plugin | terminal only: `ai claude <acct>` then `/plugin …` |
| Check everything is wired right | `ai doctor` |

## Common confusions

- **"`/plugin isn't available`"** → You're in the **app** (`ai gui`). Plugins only work in
  the **terminal** (`ai claude`).
- **"My plugin vanished in the other account"** → Different account = different folder.
  Install it there too, or it lives only in the account you built it in.
- **"Which account am I actually on?"** → On macOS, Claude's login lives in the Keychain,
  not the folder, so run `ai doctor` (auth section) or check `/status` inside a session.
