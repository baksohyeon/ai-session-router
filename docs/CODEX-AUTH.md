# Codex accounts & auth (OpenAI)

How the router keeps two OpenAI Codex identities (`personal`, `company`) separate, how
to log into each, and what OpenAI's account model does — and does **not** — do for you.

> Facts below track OpenAI's public docs as of **2026-07-02**. Both the Codex CLI and
> the desktop app auto-update; treat exact flags as *verify-at-invocation*.
> Sources: [Codex auth](https://developers.openai.com/codex/auth),
> [config](https://developers.openai.com/codex/config-advanced),
> [CLI reference](https://developers.openai.com/codex/cli/reference),
> [ChatGPT account switching](https://help.openai.com/en/articles/20001068-use-multiple-accounts-with-account-switching).

## The one thing to internalize

**ChatGPT web "account switching" is not Codex account switching.**

- ChatGPT **web** lets you keep up to **2** accounts active and toggle between them; chats,
  memory, billing, and workspaces stay separate per account.
- OpenAI states this is **web-only** — it is **not** supported in the Codex desktop app or
  the native ChatGPT mobile app.

So switching accounts in your browser does nothing for Codex. Codex resolves its identity
from **`CODEX_HOME`** — a directory of state (`config.toml`, `auth.json`, `history.jsonl`,
logs). The router gives each account its own `CODEX_HOME` and launches Codex against it:

```
ai codex personal      # CODEX_HOME=~/.codex-personal
ai codex company        # CODEX_HOME=~/.codex-company
ai codex company --account personal   # personal identity, company workspace
```

That process-level directory isolation *is* the account separation. It works identically
for the CLI. (The desktop app and CLI share the same underlying agent/config but may ship
different bundled versions; the app does not currently honor an arbitrary per-launch
`CODEX_HOME`, so the router is **CLI-first** — see [Not supported](#not-supported).)

## Auth modes per profile

Codex caches login locally and can back credentials three ways. The router does not choose
for you; it only **reports** what each root uses (`ai doctor`) and never reads token bytes.

| Mode | Where creds live | How to select | Router isolation |
|------|------------------|---------------|------------------|
| **File** (default) | `$CODEX_HOME/auth.json` (plaintext — treat like a password) | default, or `cli_auth_credentials_store = "file"` in `config.toml` | **Full** — each account's `auth.json` is under its own root |
| **Keyring** | OS credential store | `cli_auth_credentials_store = "keyring"` | Partial — `CODEX_HOME` isolates config/history, but the OS keyring entry **may be shared**; confirm the active account with `ai codex <acct> -- login status` |
| **API key** | `auth.json` (from `--with-api-key`) | see below | Full (file-backed) |
| **Auto** | file or keyring, tool's choice | `cli_auth_credentials_store = "auto"` | Treated as file if `auth.json` appears, else as keyring |

For **robust, verifiable isolation, prefer file-backed** (the default on this machine). If
you set `keyring`, isolation depends on the OS keyring keying entries per `CODEX_HOME`,
which is not guaranteed — `ai doctor` flags this so you verify in-session.

## Logging in to each profile

Everything after `--` is passed straight to the real `codex`, run under the right
`CODEX_HOME`:

```sh
# Subscription / ChatGPT sign-in (most common)
ai codex personal -- login
ai codex company  -- login
ai codex company  -- login --device-auth     # headless / remote box

# API-key-backed profile (CLI/IDE; not for Codex cloud, which requires ChatGPT sign-in)
printenv OPENAI_API_KEY | ai codex company -- login --with-api-key

# Access-token-backed
printenv CODEX_ACCESS_TOKEN | ai codex company -- login --with-access-token

# Check status WITHOUT leaking tokens (safe to run anytime)
ai codex personal -- login status
ai doctor                                     # per-account mode + isolation summary
```

The router **never** takes your key as an argument, prints it, or writes it to a
transcript — pipe secrets straight into `codex` as shown, so they never touch the router.
Your auth method affects which admin controls, data retention, residency, RBAC, and billing
apply — that is between you and OpenAI; the router only pins *which* identity is active.

## Gotchas the router protects against

- **Never clone `auth.json` between roots.** Refresh tokens are single-use; a copied file
  goes stale and silently breaks. `ai doctor` fingerprints both files and warns if they
  are identical. To seed a second account, run a fresh `login` — do **not** `cp`.
- **CLI and IDE extension share cached login.** Logging out from one can force a re-login
  in the other next time. This is expected OpenAI behavior, not a router bug.
- **`--profile` is a config profile, not an account.** `codex --profile foo` selects a
  `$CODEX_HOME/foo.config.toml` config block; it does **not** isolate auth. Account
  isolation is `CODEX_HOME` (what the router pins). Also note project-level
  `.codex/config.toml` cannot override auth/provider-sensitive keys (`openai_base_url`,
  `chatgpt_base_url`, `model_provider(s)`, `profile(s)`), by design.
- **`auth.json` permissions.** It is password-equivalent; `ai doctor` warns if it is not
  `600`/`400` and prints the exact `chmod` to fix it.

## Not supported

Deliberately out of scope, to keep the router correct and credential-safe:

- **Desktop-app account isolation for Codex.** The router is CLI-first. It does not attempt
  to make `Codex.app` honor a per-launch `CODEX_HOME`; drive multi-account Codex from the
  CLI. (For Claude, the desktop app is isolated via `--user-data-dir`; Codex has no
  equivalent verified path here.)
- **ChatGPT web cookie/session hijacking.** No browser-cookie manipulation. Web account
  switching stays in the browser and is unrelated to Codex.
- **Reading, printing, copying, committing, or logging** raw `auth.json`, access/refresh
  tokens, API keys, cookies, or browser session data. `ai doctor` reads only file
  *presence*, *mode*, a non-reversible *fingerprint*, and one *config key name*.
- **Managing the OS keyring.** If you choose keyring mode, isolation guarantees are the
  OS's; the router reports the limitation rather than papering over it.
- **Codex cloud / Remote Control provisioning.** Codex cloud requires ChatGPT sign-in and
  a signed-in host; the router pins local identity only and does not orchestrate remote
  hosts (see [ORCHESTRATION-PLAN.md](ORCHESTRATION-PLAN.md) for that future work).
