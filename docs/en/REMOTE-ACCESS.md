# Remote access: the complete guide

**Language:** English · [한국어](../ko/REMOTE-ACCESS.md)

> This repo is archived, but this guide stands on its own: a general remote-access reference largely independent of the router, and it reads fine without it. Only §10 covers `ai` integration.

How to run AI CLI sessions on one machine and reach them from anywhere (your other
laptop, your phone on the train, a hotel Wi-Fi) without losing the session when the
network drops or the lid closes.

This document is **Tailscale-first**. The modern path — mesh VPN + SSH + a session
multiplexer — comes first, because it is what you should actually do. Every section
still explains *why* before *how*, but the networking theory and the pre-Tailscale
toolbox (port forwarding, DDNS, reverse tunnels) now live in
[Appendix C](#appendix-c-networking-fundamentals--the-pre-tailscale-toolbox), where
they belong: background reading, not prerequisites.

> **TL;DR** — put Tailscale on every device (§1), enable SSH on the host (§2), run
> work inside tmux (§3), keep the host awake (§4). That's the whole system. If you
> are wondering why this needs no port forwarding, no dynamic DNS, and no VPS relay
> the way 2015-era guides did, Appendix C condenses that entire legacy toolbox into
> one table.

### Conventions

- `$USER` in shell commands expands automatically to your username at runtime, so
  examples are copy-paste-safe.
- `<your-username>`, `<your-host>` etc. in config files (SSH config, ACL JSON) are manual
  placeholders. Replace before saving; these contexts don't do shell expansion.
- `home-mac`, `home-server`, `work-laptop` are generic hostname placeholders. Use
  whatever names you set with `tailscale set --hostname`.
- `~/dev/personal`, `~/dev/work` are the router's default workspaces from
  [`install.sh`](../../install.sh). Override via `router.env` (see
  [examples/router.env.example](../../examples/router.env.example)).

---

## Table of contents

0. [Scenarios this document solves](#0-scenarios-this-document-solves)
1. [Tailscale: the mesh VPN backbone](#1-tailscale-the-mesh-vpn-backbone)
2. [SSH: the universal remote shell](#2-ssh-the-universal-remote-shell)
3. [Session persistence: tmux and its alternatives](#3-session-persistence-tmux-and-its-alternatives)
4. [Keeping the Mac awake](#4-keeping-the-mac-awake)
5. [Phone clients](#5-phone-clients)
6. [End-to-end workflows](#6-end-to-end-workflows)
7. [Security & corporate policy](#7-security--corporate-policy)
8. [Troubleshooting](#8-troubleshooting)
9. [Integration with `ai`](#9-integration-with-ai)
- [Appendix A: Quick command cheatsheet](#appendix-a-quick-command-cheatsheet)
- [Appendix B: Recommended reading](#appendix-b-recommended-reading)
- [Appendix C: Networking fundamentals & the pre-Tailscale toolbox](#appendix-c-networking-fundamentals--the-pre-tailscale-toolbox)
- [Appendix D: Gotchas specific to Korean networks](#appendix-d-gotchas-specific-to-korean-networks)

---

## 0. Scenarios this document solves

| # | Scenario | Tools used |
|---|----------|-----------|
| A | Phone → home Mac, run a long Claude task while commuting | Tailscale + SSH + tmux + caffeinate |
| B | Work laptop → home Mac, occasional after-hours work | Tailscale + SSH + tmux |
| C | Home Mac → work laptop *(usually blocked, see §7)* | Often not possible by policy |
| D | Always-on home server (mini PC / Raspberry Pi) runs Claude, every device attaches | Tailscale + SSH + tmux on server (no caffeinate needed) |
| E | Coffee shop laptop loses Wi-Fi mid-session, reattaches with everything intact | mosh OR tmux + SSH reconnect |

Difficulty increases down the list. Pick the lightest option that solves your problem.

---

## 1. Tailscale: the mesh VPN backbone

### 1.1 What it is

[Tailscale](https://tailscale.com) is a **mesh VPN built on WireGuard**. You install
it on every device you own and log into the same account, and every device can then
reach every other device by name, from anywhere, as if they shared a LAN.

### 1.2 Why it works without port forwarding

The classic problem: your home devices sit behind NAT, so inbound connections from
the Internet are dropped (the details are in [Appendix C](#c2-nat-why-your-home-computer-is-hard-to-reach)).
Tailscale sidesteps it entirely. Both devices initiate **outbound** connections to
Tailscale's coordination service. Tailscale uses NAT-traversal (STUN, hole punching)
to get the two devices talking **directly** in most cases. When a direct connection
fails (some symmetric NATs, corporate firewalls), traffic falls back to a **DERP
relay** on TCP/443, which any network that allows web browsing also allows.

Two consequences worth spelling out:

- **CGNAT is a non-issue.** Some ISPs (mobile networks, many APAC fiber providers)
  don't give you a public IP at all; port forwarding is *impossible* there. Tailscale
  works anyway, because neither end needs inbound connectivity.
- **Corporate firewalls are usually survivable.** Work networks tend to allow
  outbound HTTPS (443) and little else. The DERP fallback rides exactly that port.

You never open a port on your router, and the "incoming connection" problem
disappears.

### 1.3 Concepts you should know

| Concept | What it is |
|---------|-----------|
| **Tailnet** | Your private network of devices (one per account / org) |
| **Node** | A device on the tailnet |
| **Tailscale IP** | `100.x.x.x`, each node gets one. Stable. |
| **MagicDNS** | Resolve nodes by hostname (`home-mac`, `work-laptop`) without managing DNS |
| **ACLs** | Rules in `acl.hujson` controlling who can reach what, on which ports |
| **Tags** | Labels on nodes (e.g. `tag:server`) used by ACLs |
| **Node key expiry** | Auth keys expire (default ~180 days); expired nodes drop off until re-authenticated |
| **Subnet router** | Node that advertises a LAN range so others can reach LAN-only devices |
| **Exit node** | Node that routes *all* your traffic, used like a regular VPN |
| **Tailscale SSH** | SSH where Tailscale handles auth using your tailnet identity (no keys) |
| **Funnel** | Expose a node's port to the public Internet via Tailscale (HTTPS only) |
| **Serve** | Expose a node's port *within* the tailnet (no public Internet) |

### 1.4 Install & connect

macOS has **two install paths**, and the difference matters:

1. **The GUI app** (App Store or standalone download). Menu-bar UI, easiest login,
   what most people end up with. It ships a CLI, but **not on your PATH** — the
   binary lives inside the app bundle, and it *refuses to run through a symlink*
   (it aborts with a `bundleIdentifier` registry error). Use an alias instead:

   ```sh
   # ~/.zshrc — symlinks do NOT work for this binary
   alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
   ```

2. **Homebrew** (`brew install tailscale`): the open-source `tailscaled` daemon
   variant. CLI-first, no menu-bar app, and the only macOS variant that can run a
   **Tailscale SSH server** (see §1.5). More setup, more capability.

Either way, after login:

```sh
tailscale status
tailscale ip -4    # your 100.x.x.x address
```

iOS / Android: App Store / Play Store, sign in.

Linux:

```sh
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

After this, every device with the same account sees the others. Try:

```sh
ssh user@home-mac           # uses MagicDNS
ssh user@100.x.x.x          # always works, no DNS
```

`ai remote doctor` (this repo) detects both macOS install paths, including the
GUI-app bundle binary.

### 1.5 Tailscale SSH: kill your authorized_keys file

If you enable Tailscale SSH, the server delegates authentication to Tailscale:

```sh
sudo tailscale up --ssh
```

Now `ssh user@home-server` from any logged-in tailnet device succeeds without managing
keys. ACLs you write in the admin console govern auth. Add 2FA on your Tailscale
identity (required for `check` ACL rules) for the strongest practical setup.

Platform caveat: the **server side** of Tailscale SSH works on Linux and on the
Homebrew/`tailscaled` macOS variant — **not** in the macOS GUI app. A Raspberry Pi
or Linux box gets the full no-keys experience; a GUI-app Mac still needs classic
`authorized_keys` (or password) SSH as described in §2.

You can still use plain SSH alongside it.

### 1.6 Node key expiry: the 180-day landmine

Every node's auth key **expires**, by default after about 180 days. An expired node
silently drops off the tailnet; `tailscale ping <peer>` says
`peer's node key has expired`, and `tailscale status` on the machine itself says
`Logged out.`

For laptops and phones this is a security feature — re-auth is a quick browser
round-trip. For **server-role machines** (the home server in workflow D) it is a
time bomb: the box hums along for months, then one day you can't reach it remotely.
Two fixes:

- Re-authenticate when it happens: `sudo tailscale up` on the machine prints a
  login URL; open it from any logged-in browser (your phone works).
- Prevent it: admin console → Machines → the node → **Disable key expiry**. Do this
  for every machine whose job is to be always reachable.

### 1.7 MagicDNS

Once enabled (admin console → DNS → Enable MagicDNS), every node is reachable as
`<hostname>` and `<hostname>.<tailnet>.ts.net`. Rename a device:

```sh
sudo tailscale set --hostname home-mac
```

Pick short, distinctive names. Tailscale defaults to your machine's local hostname
(what `hostname` returns), which tends to be noisy, so override it so commands like
`ssh home-mac` stay readable.

### 1.8 Subnet router: reaching LAN devices

If you have a NAS, a printer, or a non-Tailscale device at home (`192.168.1.50`), put
Tailscale on a Mac at home and advertise the subnet:

```sh
sudo tailscale up --advertise-routes=192.168.1.0/24
# Then in the admin console, approve the advertised route.
```

Now from your phone on the train you can reach `192.168.1.50` as if you were home.

### 1.9 Exit node: full-traffic VPN

```sh
# On a node you want to use as exit:
sudo tailscale up --advertise-exit-node

# Approve in admin console, then on the client:
sudo tailscale set --exit-node=<node-name> --exit-node-allow-lan-access
```

Useful when you want all your traffic to appear from a specific location (your home
IP for geo-locked services, for instance). **Don't use a work device as your personal
exit node.** That mixes traffic across identities, the exact problem `ai` prevents.

### 1.10 ACLs: minimal example

The admin console has a JSON policy editor. Default ACL is "any node can reach any
other node, on any port." Tighten it with tags:

```jsonc
{
  "tagOwners": {
    "tag:laptop":  ["autogroup:admin"],
    "tag:server":  ["autogroup:admin"]
  },
  "acls": [
    // Laptops can reach servers on SSH, http, https
    { "action": "accept", "src": ["tag:laptop"], "dst": ["tag:server:22,80,443"] }
  ],
  "ssh": [
    { "action": "check",
      "src":    ["autogroup:member"],
      "dst":    ["tag:server"],
      "users":  ["<your-username>", "root"] }
  ]
}
```

`check` means "allow but re-prompt for SSO every N hours," which is worth enabling.

### 1.11 Funnel & Serve: when you actually want to expose something

- `tailscale serve`: share a local port to your tailnet over HTTPS. No public Internet.
- `tailscale funnel`: same, but expose to the **public Internet** through Tailscale's
  edge. Good for webhook receivers and demos.

Examples:

```sh
# Share localhost:3000 to your tailnet over HTTPS:
tailscale serve --bg 3000

# Expose it to the entire Internet (read the security warning first):
tailscale funnel 3000
```

Do **not** funnel your SSH or Claude CLI. Funnel is for public web endpoints.

### 1.12 Tailscale on a work laptop

Read §7 first. In brief:

- A personal Tailscale account on a work laptop counts as shadow IT. Most security
  policies forbid it.
- Some employers run a corporate Tailscale tenant. Use **that** one if it exists.
- If you must mix, install Tailscale on a *personal* device that can act as the bridge
  (subnet router), and keep the work device off the personal tailnet.

---

## 2. SSH: the universal remote shell

### 2.1 What SSH is

**Secure Shell.** A TCP protocol (default port 22) that gives you an encrypted,
authenticated terminal on a remote machine. Also moves files (`scp`, `sftp`, `rsync`),
forwards ports, and tunnels arbitrary TCP.

Learn this one tool well before any other networking tool.

### 2.2 Public-key authentication

Passwords are weak and easy to brute-force. SSH supports **key pairs**:

- A **private key** lives on the client (your laptop, phone). Never leaves it.
- A **public key** is copied to the server and listed in `~/.ssh/authorized_keys`.

Login proves possession of the private key without ever sending it.

Generate a modern key:

```sh
ssh-keygen -t ed25519 -C "you@example.com"
# Passphrase: yes, use one. ssh-agent will cache it.
```

This creates `~/.ssh/id_ed25519` (private) and `~/.ssh/id_ed25519.pub` (public).

Copy the public key to a server:

```sh
ssh-copy-id user@host
# Or manually:
cat ~/.ssh/id_ed25519.pub | ssh user@host 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'
```

Pragmatic note: on a **Tailscale-only** host (port 22 never faces the public
Internet), macOS's default password authentication is an acceptable way to make the
*first* connection from a new device — connect with your login password, then
install a key and move on. Keys stay the goal; they're just not a blocker for day
one. A host with public exposure gets no such grace (see §2.8).

### 2.3 ssh-agent: typing the passphrase once

`ssh-agent` is a background process that holds your decrypted private key in memory so
you only type the passphrase once per session.

On macOS:

```sh
ssh-add --apple-use-keychain ~/.ssh/id_ed25519   # stores passphrase in Keychain
```

`~/.ssh/config`:

```
Host *
    UseKeychain yes
    AddKeysToAgent yes
    IdentityFile ~/.ssh/id_ed25519
```

After this, `ssh user@host` runs silent, with no password and no passphrase prompt.

### 2.4 `~/.ssh/config`: your address book

Stop typing long commands. Define hosts:

```
Host home
    HostName home-mac
    User <your-username>
    Port 22
    ForwardAgent yes

Host work-laptop
    HostName work-laptop
    User <your-username>
    ProxyJump bastion.example.com

Host bastion.example.com
    User myname
    IdentityFile ~/.ssh/id_ed25519_work
```

Now `ssh home` is enough. `ProxyJump` chains through a jump box automatically.

### 2.5 Enabling SSH on macOS

`System Settings → General → Sharing → Remote Login`. Allow access for a specific
user. Then verify:

```sh
sudo systemsetup -getremotelogin
ssh localhost
```

Three gotchas learned the hard way:

- **Verify you enabled it on the machine you meant.** With more than one Mac on the
  account it is surprisingly easy to flip the toggle on the wrong one. Run
  `hostname` on the box first, and confirm from a *second* device:
  `nc -z <host> 22` should print `succeeded`.
- **`systemsetup -setremotelogin on` needs Full Disk Access** on modern macOS, so
  scripts (and remote hands) often can't use it. This works without FDA:
  `sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist`.
- **Unprivileged `lsof` can't see root's sshd listener**, so "is it on?" checks can
  false-negative. A plain TCP probe (`nc -z 127.0.0.1 22`) is the reliable test;
  `ai remote doctor` does exactly that.

Default port 22. Moving the port to something high (e.g. 22222) cuts noise from
internet bots, but **only if the SSH port faces the public Internet at all**. With
Tailscale the port stays private, so the change buys you nothing.

### 2.6 Port forwarding: three flavors

SSH can tunnel arbitrary TCP. Three forms:

```sh
# Local forward: my localhost:8080 → remote target
ssh -L 8080:localhost:3000 home
# Now hitting localhost:8080 on my laptop reaches port 3000 on home

# Remote forward: remote's localhost:9000 → my target
ssh -R 9000:localhost:3000 home
# A program on home hitting localhost:9000 reaches port 3000 on my laptop

# Dynamic forward (SOCKS proxy): tunnel arbitrary traffic via home
ssh -D 1080 home
# Then point your browser's SOCKS proxy to localhost:1080
```

In modern setups Tailscale replaces most reasons to do this manually, but it's worth
knowing.

### 2.7 Mosh: SSH for flaky networks

[Mosh](https://mosh.org/) is a UDP-based replacement for the SSH session (still uses
SSH for the initial login). It survives IP changes, suspends, and lossy networks. When
you SSH from a phone on mobile data, mosh beats plain SSH by a wide margin. Install with
`brew install mosh` on both ends; firewalls need to allow UDP in the 60000–61000 range.

Pair Tailscale, mosh, and tmux for the strongest mobile setup.

### 2.8 Hardening

If your SSH is exposed to the public Internet (i.e. not behind Tailscale only),
edit `/etc/ssh/sshd_config` on the server:

```
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
```

Reload: `sudo launchctl kickstart -k system/com.openssh.sshd` (macOS) or
`sudo systemctl restart sshd` (Linux).

Optional: `fail2ban` to ban brute-force IPs. Tailscale-only access skips all of this,
since the port never becomes publicly reachable.

---

## 3. Session persistence: tmux and its alternatives

### 3.1 The problem tmux solves

When you `ssh user@host` and run something long, the connection is fragile:

- Close the terminal → process dies.
- Network drops → process dies.
- Laptop sleeps → connection dies → process dies.

tmux runs a **persistent session on the server** that outlives your SSH connection.
You attach to it, work, then detach. The shell and everything in it keeps running.

### 3.2 Model: server, session, window, pane

```
tmux server  (one per user)
└── session  (e.g. "claude"): what you attach to
    ├── window 0 (like a tab)
    │   └── pane (split of a window)
    │       └── pane
    └── window 1
```

A session can have multiple windows; a window can have multiple panes (splits).

### 3.3 The prefix key

Every tmux command starts with the **prefix**, default `Ctrl-b`. Many users rebind to
`Ctrl-a` (faster, but conflicts with screen).

Essentials:

| Keys | Action |
|------|--------|
| `tmux new -s work` | Create session "work" |
| `tmux ls` | List sessions |
| `tmux attach -t work` | Attach to session "work" |
| `tmux kill-session -t work` | Kill it |
| `prefix d` | Detach (session keeps running) |
| `prefix c` | New window |
| `prefix n` / `prefix p` | Next / previous window |
| `prefix ,` | Rename current window |
| `prefix "` | Horizontal split |
| `prefix %` | Vertical split |
| `prefix arrow` | Move between panes |
| `prefix x` | Kill current pane |
| `prefix [` | Enter scroll/copy mode; `q` to exit |
| `prefix ?` | List all bindings |

### 3.4 Minimal `~/.tmux.conf`

```tmux
# More ergonomic prefix
set -g prefix C-a
unbind C-b
bind C-a send-prefix

# Mouse support (scroll, resize, click panes)
set -g mouse on

# Big history
set -g history-limit 100000

# Sane indexing
set -g base-index 1
setw -g pane-base-index 1

# Reload config without restart
bind r source-file ~/.tmux.conf \; display "reloaded"

# Splits keep current dir
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"

# 24-bit color (needed for many Claude/Codex TUIs to look right)
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:RGB"
```

### 3.5 The SSH + tmux pattern

The canonical "run something long that survives disconnect":

```sh
ssh home
tmux new -s claude
# inside tmux: run anything (claude, codex, npm run dev, etc.)
# detach: prefix-d
exit   # exit ssh; tmux keeps running

# later, from anywhere:
ssh home
tmux attach -t claude
```

You can also one-shot it:

```sh
ssh -t home 'tmux new -As claude'
# -t allocates a TTY; new -As "attach if exists, else create"
```

### 3.6 Things that surprise people

- tmux sessions die if the **server reboots**. They are not on-disk.
  Use [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) if you care.
- Closing the parent terminal does NOT kill tmux. That's the point of it.
- A tmux session belongs to the **user** running `tmux`. You can't attach to someone
  else's session without privilege.
- tmux ≠ screen. If you remember `screen` from 2010, tmux is the modern replacement.

### 3.7 Alternatives: zellij, Herdr — and where mosh fits

tmux is not the only multiplexer anymore. The trade-offs:

| | **tmux** | **zellij** | **Herdr** | **mosh** |
|---|---|---|---|---|
| What it is | multiplexer | modern multiplexer | *agent-aware* multiplexer | roaming transport |
| Survives disconnect | ✓ | ✓ | ✓ (background server) | ✓ (roaming), but no detach |
| Works over SSH from a phone | ✓ | ✓ | ✓ | is the SSH replacement |
| Knows what's *inside* a pane | ✗ | ✗ | ✓ — agent state: blocked / working / done / idle | n/a |
| Maturity / ubiquity | 15+ yrs, in every distro repo | stable, growing | young (2026), moving fast | 10+ yrs, stable |
| Extra moving parts | none | none | its own background server | UDP 60000–61000 must be open |
| Discoverability | man page archaeology | great built-in hints | sidebar UI, mouse-native | n/a |

- **[zellij](https://zellij.dev/)**: friendlier defaults, layouts-as-code, built-in
  hints. If tmux's learning curve is the blocker, start here. The router ships an
  `ai zellij` wrapper; tmux stays the remote fallback.
- **[Herdr](https://herdr.dev/)**: tmux-style persistence *plus semantic agent
  state*. It knows a pane contains claude/codex and rolls every agent up to
  🔴 blocked / 🟡 working / 🔵 done / 🟢 idle, so from your phone you can see at a
  glance which of five agents actually needs input. Official integrations for
  claude, codex, and most agent CLIs; a single Rust binary; scriptable
  (`herdr session list --json`). Trade-offs: it is a young project, it runs its own
  background server (one more thing to trust and update), the default `ctrl+b`
  prefix collides with tmux muscle memory, and it is not preinstalled anywhere.
- **mosh is not a competitor** — it replaces the *network transport*, not the
  multiplexer. mosh + any of the three above is the strongest mobile combination.

Recommendation: keep **tmux as the base layer** for remote persistence — it is the
lowest common denominator on every server you will ever touch, and every guide
(including this one) assumes it. Reach for **Herdr when you routinely juggle several
concurrent agents** and the "which pane needs me?" problem becomes real. They solve
overlapping but not identical problems; nothing stops you from trying Herdr on the
host while your workflows stay tmux-shaped.

`ai remote doctor` reports sessions from all three (tmux, zellij, herdr).

---

## 4. Keeping the Mac awake

### 4.1 macOS sleep modes, briefly

- **Display sleep**: screen off, machine still running.
- **System sleep** ("sleep"): RAM kept powered, CPU halted, network mostly off.
  Existing TCP connections die.
- **Hibernation / safe sleep**: RAM written to disk, machine fully off.
- **Lid-close sleep (MacBooks)**: *forced* sleep when the lid shuts unless an
  external display + power + keyboard/mouse is attached (clamshell mode).

A sleeping Mac cannot run your tmux session. The CPU has stopped executing.

### 4.2 `caffeinate`: the easy way

Built-in. From `man caffeinate`:

| Flag | Prevents |
|------|----------|
| `-d` | Display sleep |
| `-i` | Idle system sleep |
| `-m` | Disk idle sleep |
| `-s` | System sleep (only on AC power) |
| `-u` | Declare user activity (5s by default) |
| `-w PID` | Block sleep until PID exits |
| `-t SEC` | Block sleep for SEC seconds |

Common recipes:

```sh
# Keep the system awake while a command runs, then release:
caffeinate -i ./long-job.sh

# Indefinitely (until Ctrl-C):
caffeinate -dims

# Detached — survives closing the terminal that started it:
nohup caffeinate -is >/dev/null 2>&1 &

# Keep system awake as long as a specific process (e.g. tmux server) lives:
caffeinate -i -w $(pgrep -x tmux | head -1)
```

The detached form is the one you want when you're about to leave the house and the
session must not die with your terminal window. Verify it took hold with
`pmset -g assertions` (look for `PreventUserIdleSystemSleep` held by `caffeinate`).

### 4.3 `pmset`: the heavier hammer

`pmset` reads and changes power-management settings system-wide. Useful subset:

```sh
pmset -g                          # show current settings
pmset -g assertions               # what's currently preventing sleep
pmset -g batt                     # battery / power state

# Disable system sleep when on AC (requires sudo):
sudo pmset -c sleep 0

# Re-enable a 30-minute idle sleep on AC:
sudo pmset -c sleep 30
```

`pmset` settings persist across reboots. Reach for them when you want a *server-like*
Mac that never sleeps on AC power. Use `caffeinate` for one-off, scoped overrides.

### 4.4 Lid-close on MacBooks

By default, closing the lid forces sleep regardless of `caffeinate` or `pmset`. The
intended exception is **clamshell mode**: connect external power + display +
keyboard/mouse and the Mac stays on with the lid shut.

Hacks like `sudo pmset -a disablesleep 1` bypass this, but avoid them. They keep the
laptop hot and discharging while it sits closed in a bag. Better options:

- Leave the lid open (use a stand).
- Use clamshell mode with a real desk setup.
- Move long-running workloads to a desktop / mini-PC / Raspberry Pi that doesn't have
  a lid.

### 4.5 Power Nap & Wake on LAN

- **Power Nap** lets the Mac do some background work (Time Machine, Mail) during
  sleep. It does *not* keep arbitrary user processes running. Don't rely on it.
- **Wake on Network access** wakes the Mac when it receives a special packet. That lets
  you `ssh` in and have the box wake up, but it works only on the same LAN unless you
  set up Wake-on-WAN proxying.

### 4.6 GUI alternative: Amphetamine

If you prefer a menu-bar UI with conditions ("stay awake while screen is mirrored",
"stay awake until 11pm"), [Amphetamine](https://apps.apple.com/app/amphetamine/id937984704)
wraps `caffeinate`-equivalent behavior with rules. It covers everything the CLI does,
though the CLI stays faster for one-offs.

---

## 5. Phone clients

### 5.1 iOS

| App | Notes |
|-----|------|
| **Blink Shell** | Paid, and the strongest option. mosh built in, keyboard support, scriptable. |
| **Termius** | Free tier is fine; cloud key sync; cross-platform. Note that it can store keys in its cloud. |
| **a-Shell** | Free and open source. Limited, but handy for quick SSH. |
| **Tailscale (iOS app)** | Required to put the phone on the tailnet. Always-on toggle works well in practice. |

### 5.2 Android

| App | Notes |
|-----|------|
| **Termux** | Real Linux env in a Play-Store/F-Droid app. Install `openssh`, `mosh`, `tmux` and use it natively. |
| **JuiceSSH** | GUI-friendly, classic. |
| **Termius** | Same as iOS. |
| **Tailscale (Android app)** | Same role as on iOS. |

### 5.3 Key management on a phone

Generate a key **on the phone**, copy its public key to the server, and keep the
private key on the phone only. Never paste your laptop's private key into a
cloud-syncing notes app to move it onto the phone.

If a phone is lost, you should be able to remove its public key from the server's
`authorized_keys` (or, with Tailscale SSH, just remove the device from the tailnet)
without affecting other devices.

### 5.4 The "phone keyboard sucks" reality

For more than 30 seconds of typing, a Bluetooth keyboard turns a phone into a usable
mini-laptop. Keep a small foldable one in your bag if you plan to do this often.

---

## 6. End-to-end workflows

### 6.1 Workflow A: phone → home Mac, long-running Claude task

**One-time setup on the home Mac:**

```sh
# 1. Install Tailscale (GUI app or brew, §1.4) + tmux
brew install tmux
# GUI app: log in from the menu bar. brew variant: sudo tailscale up
sudo tailscale set --hostname home-mac

# 2. Enable Remote Login (System Settings → General → Sharing)
#    ...on THIS machine — run `hostname` first if you own several Macs,
#    then confirm from another device: nc -z home-mac 22
# 3. Prevent sleep on AC power, indefinitely
sudo pmset -c sleep 0 disksleep 0

# 4. (Optional) start a long-lived tmux session at login via launchd or just manually
tmux new -d -s claude
```

**One-time setup on the phone:**

1. Install Tailscale, sign in to same account.
2. Install Blink Shell (or Termius / Termux on Android).
3. First connection can use your Mac login password (fine on a Tailscale-only
   host, §2.2). Then generate a key in the SSH client and install it for keyless
   logins.

**Daily use:**

```sh
# From phone:
ssh $USER@home-mac
tmux attach -t claude
# do work; prefix-d to detach
exit
```

If the connection drops in a subway tunnel, reconnect and run `tmux attach -t claude`
to pick up where you left off. To survive *roaming* (Wi-Fi → LTE), add mosh:

```sh
mosh $USER@home-mac -- tmux new -As claude
```

Leaving in a hurry? The two things that actually matter: **power connected, lid
open** (§4.4) — and a detached `nohup caffeinate -is >/dev/null 2>&1 &` if you
haven't done the `pmset` setup yet.

### 6.2 Workflow B: work laptop → home Mac, after hours

If your work laptop allows installing Tailscale (check §7), same as A. Otherwise:

- Use the phone as a Tailscale-equipped hotspot for the work laptop. The work laptop
  is now on cellular through the phone; if you put the phone on the personal tailnet,
  the work laptop is not. (You'd need a second hop.)
- Easier: use the phone itself to SSH in, and treat the work laptop as a viewer.
- Cleanest: separate physical machine. See workflow D.

### 6.3 Workflow C: home → work laptop

Most workplaces block this on purpose, and bypassing it is a fireable offense.
**Don't.** When remote work is sanctioned, your employer provides the mechanism
(corporate VPN, virtual desktop). Use it.

### 6.4 Workflow D: always-on home server

This is the most robust setup: a small mini-PC or Raspberry Pi at home, plugged in 24/7.

- Runs Tailscale, tmux, sshd.
- Hosts the Claude / Codex sessions.
- Doesn't sleep (it's a server).
- Doesn't depend on your laptop being open.

Your MacBook, work laptop, and phone are all *clients*. They attach to tmux sessions
on the server. The home Mac becomes optional.

Setup, roughly:

```sh
# On the server (Linux):
sudo apt install tmux openssh-server
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh --hostname home-server
# Linux gets the full Tailscale SSH server (§1.5): no key management at all.

# Install Claude Code / Codex however you do on Linux,
# then create a tmux session that holds them:
tmux new -d -s ai 'ai claude personal'  # if you have the ai router set up
```

Then, in the admin console: **disable key expiry** for this node (§1.6). A server
that silently falls off the tailnet after 180 days defeats the purpose.

From any device:

```sh
ssh $USER@home-server
tmux attach -t ai
```

Hardware notes, learned the hard way:

- **Power the Pi properly.** A Raspberry Pi 4 wants the official 5V/3A USB-C
  supply. Laptop USB-C PD chargers *seem* to work, then brown-out under load and
  hard-reset the board — often without even setting the undervoltage flag
  (`vcgencmd get_throttled` can read `0x0` right up until it dies). Symptom: a
  reboot loop every few minutes with lights on. If your always-on box isn't
  reliably always on, suspect the power supply first.
- **Enable persistent logs** so crashes are diagnosable after the fact:
  `sudo mkdir -p /var/log/journal && sudo systemctl restart systemd-journald`,
  then `last -x reboot` and `journalctl -b -1 -e` after the next incident.

Tradeoffs: extra hardware ($), one more box to maintain (security updates), and a
performance ceiling (a Pi handles chat fine but strains under large agentic loads).

### 6.5 Workflow E: flaky network on the road

```sh
mosh $USER@home-server -- tmux new -As road
```

mosh handles network drops, IP changes, and suspend/resume; tmux handles process
persistence. Together they let you close the laptop, walk into a tunnel, switch from
Wi-Fi to LTE, and open the laptop in a café 20 minutes later with the session intact.

---

## 7. Security & corporate policy

### 7.1 The non-negotiables

- SSH keys have **passphrases**, cached by `ssh-agent` / Keychain.
- 2FA on your Tailscale account.
- 2FA on every cloud account that grants access to anything on this tailnet (GitHub,
  Google, etc.).
- A separate Tailscale account for personal vs work tailnets. Don't mix.
- Disable password SSH on any host reachable from the public Internet.

### 7.2 Tailscale-specific hygiene

- Use ACLs to limit who can reach what. Default-allow is convenient and dangerous.
- Use `tailscale ssh` with `check` mode for high-value boxes.
- Never `funnel` an SSH or shell endpoint.
- Periodically `tailscale status` and remove devices you no longer own.
- Rotate machine auth keys if a device is lost (admin console → expire key).
- Disable key expiry **only** on server-role machines (§1.6); leave it on for
  laptops and phones.

### 7.3 Work devices: get permission

Many corporate policies, in plain language:

- **No personal VPN software** on company devices. Tailscale counts.
- **No SSH out** to non-approved hosts. Some networks block port 22 outbound.
- **No remote access** to home machines that store work secrets. Even if it works
  technically, it's an exfiltration risk.

Ask your security/IT team in writing. They tend to say *yes* to "Tailscale on my
personal laptop", *it depends* for the work laptop, and the conversation itself keeps
you out of trouble.

A note on VPN-tolerant offices: "everyone here already uses VPNs" makes the written
question *easier to ask*, not unnecessary. Ambient tolerance is not a policy, it
evaporates exactly when something goes wrong, and the person who asked in writing is
in a different position that day than the person who didn't. Also remember the
flip side: a corporate-managed device on your personal tailnet can *see* your
personal machines. Even with permission, prefer tag-scoped ACLs (§1.10) so the work
device reaches only what it needs.

### 7.4 The `ai` router and security

[ai-session-router](../../README.md) exists to prevent identity mix-ups. Remote access
shifts the threat model:

- If someone compromises a phone and can unlock SSH, they reach your home tailnet.
- So require an SSH key passphrase, biometric unlock on the phone, and an SSH client
  that re-authenticates after backgrounding (Blink and Termius both support this).
- The AI tool writes logs to the **workspace** on the host where it ran, which means
  the server, not the phone. That's intentional and correct.

### 7.5 What to do if you suspect a device is compromised

1. From the Tailscale admin console: expire the device's key. It instantly drops off
   the tailnet.
2. Rotate any SSH public keys present on the device (replace `authorized_keys`
   entries on all servers).
3. Rotate API tokens that might have been on disk (Claude / Codex account roots; see
   `~/.claude-*`, `~/.codex-*`).
4. If the device held work credentials, tell your security team. *Before* §1.

---

## 8. Troubleshooting

### 8.1 "Connection refused"

The TCP port is reachable but nothing is listening. The service is down, or you're
hitting the wrong port. On the server:

```sh
# Is sshd running?
sudo launchctl list | grep ssh    # macOS
sudo systemctl status sshd        # Linux

# Is it listening?
sudo lsof -iTCP:22 -sTCP:LISTEN
```

### 8.2 "Connection timed out"

Something between you and the server is dropping packets: NAT, firewall, or routing.
With Tailscale, run this on both ends:

```sh
tailscale status               # both nodes online?
tailscale ping <peer>          # direct connection? if it falls back to DERP, that's still working but slower
```

### 8.3 "Permission denied (publickey)"

The server rejected your key. Diagnostic SSH:

```sh
ssh -vvv user@host  2>&1 | grep -E 'identity|publickey|Offering|Accepted|denied'
```

Common causes:

- Public key not in server's `~/.ssh/authorized_keys`.
- Permissions on `~/.ssh` or `authorized_keys` too loose (must be `700` and `600`).
- Server config disabled pubkey auth (check `/etc/ssh/sshd_config`).
- Wrong user (`ssh root@host` when the key was added for a different account).

### 8.4 "tmux session disappeared"

Two main causes:

- The host rebooted (e.g. the Mac slept hard, then was restarted). tmux sessions are
  in-memory.
- A different user is logged in. `tmux ls` only shows the current user's sessions.

Mitigations: `pmset -c sleep 0` on a desktop Mac; or a real server; or
[tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) for the few cases
where you need session contents to survive restarts.

### 8.5 "Tailscale says I'm online but I can't reach the peer"

```sh
tailscale status               # is the peer online?
tailscale ping <peer>          # latency? direct vs DERP?
tailscale netcheck             # local network diagnostics
```

If `netcheck` shows everything blocked except port 443, you're behind a strict
firewall. DERP fallback still works, but slower.

### 8.6 "peer's node key has expired"

The node fell off the tailnet because its auth key aged out (§1.6). On the machine:
`sudo tailscale up` prints a login URL — open it from any logged-in browser (phone
included) and approve. **Careful with the URL's freshness**: if the machine reboots
mid-auth, the pending login resets and the old URL silently goes stale; always take
the URL from the *most recent* `tailscale status` / `tailscale up` output. Then
disable key expiry for server-role nodes so it doesn't recur.

### 8.7 "tailscale: command not found (but the app is installed)"

You have the macOS GUI app (§1.4). The CLI is inside the bundle at
`/Applications/Tailscale.app/Contents/MacOS/Tailscale`, and it must be invoked at
that real path or via a shell alias — **a symlink will not work** (the binary aborts
with a `bundleIdentifier` registry error). `ai remote doctor` knows about this
location and reports it as installed.

### 8.8 "I enabled Remote Login but port 22 is still closed"

Almost always: you enabled it **on a different machine** than the one you're probing
(multi-Mac households make this easy). Run `hostname` where you flipped the toggle
and compare. To enable it from a shell on the right machine when
`systemsetup` complains about Full Disk Access:
`sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist`.

### 8.9 "MagicDNS doesn't resolve"

```sh
scutil --dns | grep -A2 'resolver #1'   # macOS: is 100.100.100.100 a DNS server?
tailscale set --accept-dns=true         # ensure DNS acceptance is on
```

VPN clients that override DNS can interfere.

### 8.10 "SSH disconnects after a few minutes idle"

Add to client `~/.ssh/config`:

```
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

Or on the server, add `ClientAliveInterval 60` to `sshd_config`.

### 8.11 "Mac slept anyway"

Check what's currently allowed to prevent sleep:

```sh
pmset -g assertions
```

You should see a `PreventUserIdleSystemSleep` entry held by `caffeinate` or your
running process. If it's missing, your caffeinate exited or never started.

### 8.12 "Raspberry Pi reboot loops / dies under load"

Lights on, but the box drops off the network every few minutes and `uptime` resets:
suspect **power** before software. Laptop USB-C chargers and cheap supplies
brown-out under load and hard-reset the board, frequently without tripping the
undervoltage flag (`vcgencmd get_throttled` → `0x0`). Swap in the official 5V/3A
supply. Enable persistent journald (§6.4) so the *next* crash leaves evidence:
`last -x reboot` shows the reboot history, `journalctl -b -1 -e` the previous boot's
final moments.

---

## 9. Integration with `ai`

The `ai` command (this repo) already separates accounts, workspaces, and browsers.
Remote access adds *which host* to the mix, and the axes stay independent.

### 9.1 Running `ai` over SSH

```sh
ssh home
tmux new -As claude
ai claude personal              # exactly the same as if you were sitting at the Mac
```

The router writes its logs where it always does: `<workspace>/.ai-logs/...` *on the host
where ai ran*, the home Mac rather than your phone. That's by design.

### 9.2 `ai remote doctor`

This command reports remote-access state and never configures it:

- Tailscale status / IP / online peers — including the macOS **GUI-app install**,
  whose CLI hides inside the app bundle (§8.7)
- sshd listening? — uses a TCP connect probe as fallback, since unprivileged `lsof`
  can't see root's listener (§2.5)
- tmux, zellij, **and herdr** sessions present?
- Hostname (to confirm you're on the host you think you are — §8.8 exists for a reason)

Run it after changes to verify, e.g. after `sudo tailscale up --ssh`.

### 9.3 A clean shell hook

A useful `.zshrc` snippet for the **client** side (laptop / phone Termux):

```zsh
# One command to land in a known tmux session on home
home-ai() {
  ssh -t home "tmux new -As ai 'cd ~/dev/personal && ai claude personal'"
}
```

Now `home-ai` from anywhere drops you into a tmux session running Claude on the home
Mac with the right account and workspace.

### 9.4 What `ai` deliberately does *not* do

- It does **not** configure Tailscale (no token storage, no `tailscale up` calls).
- It does **not** start tmux for you in `ai claude/codex`; that's your shell's job.
- It does **not** forward credentials over the network. Account auth lives where each
  account's config root lives, on the host running `ai`.

These boundaries are deliberate. A router should not own VPN setup, sleep policy, or
remote process management. Use the tools in this document for those concerns, and use
`ai` for identity routing.

---

## Appendix A: Quick command cheatsheet

```sh
# SSH key
ssh-keygen -t ed25519 -C "you@example.com"
ssh-copy-id user@host
ssh-add --apple-use-keychain ~/.ssh/id_ed25519

# Tailscale
brew install tailscale            # or the GUI app; then in ~/.zshrc:
alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"  # GUI app only
sudo tailscale up --ssh
tailscale status
tailscale ip -4
tailscale ping <peer>
tailscale netcheck
# Admin console: disable key expiry for server-role nodes (§1.6)

# tmux
tmux new -As ai
tmux ls
tmux attach -t ai
# prefix-d to detach

# herdr (agent-aware alternative, §3.7)
herdr session list

# Sleep control
caffeinate -dims          # block all sleep until Ctrl-C
nohup caffeinate -is >/dev/null 2>&1 &   # detached; survives closing the terminal
caffeinate -i -t 3600     # block idle sleep for 1 hour
sudo pmset -c sleep 0     # never sleep on AC (persistent)
pmset -g assertions       # what's preventing sleep right now

# Diagnostics
ai remote doctor          # this repo's command
ssh -vvv user@host        # verbose SSH
sudo lsof -iTCP -sTCP:LISTEN
```

## Appendix B: Recommended reading

- `man ssh`, `man ssh_config`, `man sshd_config`
- `man tmux` (long, but the only authoritative source)
- `man caffeinate`, `man pmset`
- [Tailscale docs](https://tailscale.com/kb/)
- [Herdr docs](https://herdr.dev/) and [zellij docs](https://zellij.dev/) (multiplexer alternatives, §3.7)
- [WireGuard whitepaper](https://www.wireguard.com/papers/wireguard.pdf) (if you want the crypto)
- [mosh paper](https://mosh.org/mosh-paper.pdf) (why mobile SSH should use UDP)
- This repo's [ARCHITECTURE.md](./ARCHITECTURE.md), [COMMANDS.md](./COMMANDS.md),
  [PORTABILITY.md](./PORTABILITY.md)

## Appendix C: Networking fundamentals & the pre-Tailscale toolbox

Everything here used to be chapter 1 of this guide. You no longer need it to *do*
anything — Tailscale absorbs these problems — but it is worth reading once so the
system isn't magic to you, and so you can debug the day something breaks.

### C.1 IP addresses: public vs private

Every device on a network has an **IP address**. Two kinds matter here:

- **Public IP**: globally unique, routable from anywhere on the Internet. Your ISP
  gives one (or sometimes zero, see CGNAT below) to your home router.
- **Private IP**: only valid *inside* your local network. Common ranges:
  - `10.0.0.0/8`
  - `172.16.0.0/12`
  - `192.168.0.0/16`
  - `100.64.0.0/10` (carrier-grade NAT, *and* Tailscale's range)

Your laptop on home Wi-Fi typically has a `192.168.x.x` address. That address means
nothing to the outside world.

### C.2 NAT: why your home computer is hard to reach

Your home has one public IP (from the ISP) and many devices behind it. The router
performs **NAT** (Network Address Translation): outbound traffic is rewritten to
appear from the public IP, and replies are routed back to the right internal device
based on a port mapping the router remembers.

The consequence: **outbound connections work, inbound connections don't.** When a
server on the Internet tries to reach `your.public.ip`, the router has no mapping to
forward the packet to your laptop, so it drops it.

That is why "just SSH into my home computer from the train" fails out of the box —
and why Tailscale's outbound-only design (§1.2) makes the problem vanish.

**CGNAT**, the harsher variant: some ISPs don't give you a unique public IP at all;
they put you behind a *carrier-level* NAT. Port forwarding is then impossible, full
stop. Mesh VPNs work regardless, because both ends connect outward and meet in the
middle.

### C.3 Ports: the second half of an address

An IP says *which machine*. A **port** (0–65535) says *which program on that machine*.
Examples:

| Port | Service |
|------|---------|
| 22 | SSH |
| 80 | HTTP |
| 443 | HTTPS |
| 5900 | VNC |
| 3000 | typical dev server |

A program **listens** on a port. Another program **connects** to that `(ip, port)`
pair. If nothing is listening, the connection is refused immediately.

### C.4 The pre-Tailscale toolbox (TL;DR)

Before mesh VPNs, exposing a home machine meant one of these. They all still work.
You almost certainly don't want any of them, but here's the map:

| Method | The idea | Why you probably don't want it |
|--------|----------|-------------------------------|
| **Port forwarding + dynamic DNS** | Router rule "public :22 → 192.168.1.42:22", plus `me.duckdns.org` tracking your changing home IP | Needs router access; CGNAT breaks it entirely; your SSH port sits on the public Internet where bots hammer it around the clock |
| **Reverse SSH tunnel to a VPS** | Home box holds an outbound connection to a rented VPS; you SSH to the VPS, which forwards home | A VPS to pay for, patch, and secure — forever |
| **Cloudflare Tunnel / ngrok / frp** | Same reverse-tunnel idea, productized | Vendor lock-in, per-service config, free tiers with strings attached |
| **A classic VPN (OpenVPN / manual WireGuard / IPsec)** | Join the home LAN from outside as a network member | The right idea — Tailscale *is* WireGuard — minus the certificate ceremonies and config-file archaeology you'd be signing up for |

Each row costs more setup, more attack surface, or more maintenance than a mesh VPN.
That's the whole argument of §1.

### C.5 The corporate firewall

Work networks usually allow outbound HTTPS (443) and not much else. Outbound SSH (22)
is often blocked. That is why some tools tunnel SSH over HTTPS, and why Tailscale
falls back to a DERP relay on port 443 when direct UDP fails.

### C.6 IPv6 footnote

IPv6 gives every device a globally unique address and in theory removes the need for
NAT. Residential IPv6 remains patchy, and firewalls block inbound traffic anyway. Don't
count on IPv6 to solve C.2.

## Appendix D: Gotchas specific to Korean networks

Korea-specific notes. Your mileage varies with your network, ISP, and employer.

### D.1 Public IP / CGNAT by carrier

Rough current state (policies change often — verify your own line):

| Carrier | Residential fiber | Mobile |
|---------|------------------|--------|
| KT | Usually a public IP (static is a separate request) | CGNAT by default |
| SK Broadband | Public IP (changeable/pinnable on request) | CGNAT by default |
| LG U+ | Public IP; some lines CGNAT | CGNAT by default |
| MVNOs (알뜰폰) | n/a | CGNAT nearly 100% |

How to check:

```sh
# Look up the WAN IP in your router's admin page, then compare with what
# the outside world sees. If they differ, you are behind CGNAT
# (or the router isn't in router mode).
curl -s https://api.ipify.org   # my IP as seen from outside
ifconfig | grep "inet " | grep -v 127        # my IP as seen by the router
```

**Under CGNAT, port forwarding is flat-out impossible**, so Tailscale (or another
mesh VPN) is the only answer. Fortunately Tailscale works fine behind CGNAT — that
is the point of §1.2.

### D.2 Port blocking on residential lines

Some carriers block inbound traffic on specific ports of residential lines **to
prevent server hosting**:

- Commonly blocked: 25 (SMTP), 80 (HTTP), 443 (HTTPS), 3389 (RDP)
- 22 (SSH) is generally open, but confirm with your ISP
- The Internet is full of guides for dodging this via nonstandard ports like 8080;
  that can violate your terms of service, and enforcement can mean a suspended line

→ Bottom line: check your ISP's terms before exposing anything directly from a
residential line, and when you really need public exposure, prefer mechanisms that
don't touch the ToS — like Tailscale Funnel.

### D.3 Air-gapped workplaces (large corporates, finance, public sector)

Korean large corporates, finance, and the public sector commonly run **망분리**
(network separation: work network ↔ Internet network, physical or logical). In that
environment:

- The work laptop's own Internet access is restricted (browsing goes through a
  virtual desktop)
- Outbound port 22 is blocked almost as a rule
- Merely installing a personal VPN client trips EDR/DLP and pages the security team
- Personal USB and cloud sync are blocked too — there is no unofficial channel to
  even move a key file

→ **Don't even think about putting Tailscale on the work laptop.** In a
network-separated shop, make a formal request to IT security and use whatever they
provide (corporate VDI, a corporate Tailscale tenant, etc.). Getting caught working
around it does your career no favors.

### D.4 Typing Korean in phone SSH apps

Hangul input handling differs per app:

| App (iOS) | Hangul input |
|-----------|--------------|
| Blink Shell | OK (but hitting keys like ESC mid-IME-composition can garble input) |
| Termius | Smoothest |
| a-Shell | Hangul input barely works; treat it as English-commands-only |

| App (Android) | Hangul input |
|---------------|--------------|
| Termux | OK (uses the system keyboard as-is) |
| JuiceSSH | OK |
| Termius | OK |

→ If you'll be typing Korean prompts to Claude/Codex, a **Bluetooth keyboard is
strongly recommended**. Long-form Korean on an on-screen keyboard is genuine misery.

### D.5 Tailscale latency (from Korea)

Tailscale has no [DERP relay](https://tailscale.com/kb/1118/custom-derp-servers/)
in Korea itself (as of 2026; Tokyo is the nearest). So:

- Direct P2P connection established → near-zero added latency (LAN-like)
- DERP fallback → via Tokyo → typically +30–50ms
- Barely noticeable for SSH/terminal work; noticeable for video/streaming

Check:

```sh
tailscale ping <peer>
# "direct" = P2P, "via DERP" = relayed
```

When direct connections fail, the usual culprit is the NAT type on both ends
(symmetric NAT). Enabling UPnP on the router, or adding a single port-forward line
(UDP 41641), raises the P2P success rate.

### D.6 Work machines (BYOD): the common case

Startups, mid-size companies, and foreign-owned shops generally allow BYOD or some
freedom on the company laptop. In that environment:

- Installing Tailscale on your own responsibility is usually fine (check policy first)
- But **moving company data onto other devices in your personal tailnet** is asset
  exfiltration. Separate issue entirely.
- Follow the `ai` router's founding principle: *each identity's data stays in that
  identity's workspace*.

### D.7 The recommended setup for a Korean user

If you are a typical Korean office worker with home Internet and a phone, this is
almost always the answer:

1. **Home Mac: Tailscale + tmux + `pmset -c sleep 0`**
2. **Phone: Tailscale + Blink Shell (or Termux)**
3. **At the office: attempt no remote access of any kind** (use official channels if needed)
4. **Add mosh if your LTE/5G drops often**

This setup fits the repo's overall workflows best.
