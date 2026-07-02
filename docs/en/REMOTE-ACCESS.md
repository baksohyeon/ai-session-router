# Remote access — the complete guide

**Language:** English · [한국어](../ko/REMOTE-ACCESS.md)

How to run AI CLI sessions on one machine and reach them from anywhere (your other
laptop, your phone on the train, a hotel Wi-Fi) without losing the session when the
network drops or the lid closes.

This document is **concept-first**. Every section explains *why* before *how*. Most
"just type this" guides break because you don't know which failure mode you're hitting.

### Conventions

- `$USER` in shell commands — expands automatically to your username at runtime, so
  examples are copy-paste-safe.
- `<your-username>`, `<your-host>` etc. in config files (SSH config, ACL JSON) — manual
  placeholders. Replace before saving; these contexts don't do shell expansion.
- `home-mac`, `home-server`, `work-laptop` — generic hostname placeholders. Use
  whatever names you set with `tailscale set --hostname`.
- `~/dev/personal`, `~/dev/work` — the router's default workspaces from
  [`install.sh`](../install.sh). Override via `router.env` (see
  [examples/router.env.example](../examples/router.env.example)).

---

## Table of contents

0. [Scenarios this document solves](#0-scenarios-this-document-solves)
1. [Networking — the parts you can't skip](#1-networking--the-parts-you-cant-skip)
2. [SSH — the universal remote shell](#2-ssh--the-universal-remote-shell)
3. [tmux — keep the session alive](#3-tmux--keep-the-session-alive)
4. [Keeping the Mac awake](#4-keeping-the-mac-awake)
5. [Tailscale — the easy mesh VPN](#5-tailscale--the-easy-mesh-vpn)
6. [Phone clients](#6-phone-clients)
7. [End-to-end workflows](#7-end-to-end-workflows)
8. [Security & corporate policy](#8-security--corporate-policy)
9. [Troubleshooting](#9-troubleshooting)
10. [Integration with `ai`](#10-integration-with-ai)

---

## 0. Scenarios this document solves

| # | Scenario | Tools used |
|---|----------|-----------|
| A | Phone → home Mac, run a long Claude task while commuting | Tailscale + SSH + tmux + caffeinate |
| B | Work laptop → home Mac, occasional after-hours work | Tailscale + SSH + tmux |
| C | Home Mac → work laptop *(usually blocked — see §8)* | Often not possible by policy |
| D | Always-on home server (mini PC / Raspberry Pi) runs Claude, every device attaches | Tailscale + SSH + tmux on server (no caffeinate needed) |
| E | Coffee shop laptop loses Wi-Fi mid-session, reattaches with everything intact | mosh OR tmux + SSH reconnect |

Difficulty increases down the list. Pick the lightest option that solves your problem.

---

## 1. Networking — the parts you can't skip

### 1.1 IP addresses: public vs private

Every device on a network has an **IP address**. Two kinds matter here:

- **Public IP** — globally unique, routable from anywhere on the Internet. Your ISP
  gives one (or sometimes zero — see CGNAT below) to your home router.
- **Private IP** — only valid *inside* your local network. Common ranges:
  - `10.0.0.0/8`
  - `172.16.0.0/12`
  - `192.168.0.0/16`
  - `100.64.0.0/10` (carrier-grade NAT, *and* Tailscale's range)

Your laptop on home Wi-Fi typically has a `192.168.x.x` address. That address means
nothing to the outside world.

### 1.2 NAT — why your home computer is hard to reach

Your home has one public IP (from the ISP) and many devices behind it. The router
performs **NAT** (Network Address Translation): outbound traffic is rewritten to
appear from the public IP, and replies are routed back to the right internal device
based on a port mapping the router remembers.

The consequence: **outbound connections work, inbound connections don't.** When a
server on the Internet tries to reach `your.public.ip`, the router has no mapping to
forward the packet to your laptop, so it drops it.

That is why "just SSH into my home computer from the train" fails out of the box.

### 1.3 Ports — the second half of an address

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

### 1.4 The classic ways to expose a home machine

Before Tailscale-style tools, the options were:

1. **Port forwarding on the router.** Tell the router "incoming TCP 22 → 192.168.1.42:22".
   Then expose your home IP via dynamic DNS (e.g. `me.duckdns.org`). Downsides: it needs
   router access, the ISP may block it (CGNAT), and your SSH port now sits on the public
   Internet where bots attack it around the clock.
2. **A reverse SSH tunnel to a VPS.** Your home box connects *outward* to a VPS and
   keeps the connection open; you SSH into the VPS, which forwards to home.
3. **Cloudflare Tunnel / ngrok / frp.** Similar idea, but easier to set up.
4. **A real VPN** (OpenVPN, WireGuard, IPsec). You join a private network from outside
   and reach home as if you were on the LAN. Historically painful to configure.

All of these work. Each one costs you more setup, more attack surface, or more vendor
lock-in than a mesh VPN, which is what §5 covers.

### 1.5 CGNAT — when you don't even have a public IP

Some ISPs (mobile networks, many APAC fiber providers) don't give you a unique public
IP at all. They put you behind a *carrier-level* NAT. Port forwarding is impossible.
Tailscale and other mesh VPNs work *because* they don't need inbound connectivity:
both ends connect outward to a relay and meet in the middle.

### 1.6 The corporate firewall

Work networks usually allow outbound HTTPS (443) and not much else. Outbound SSH (22)
is often blocked. That is why some tools tunnel SSH over HTTPS, and why Tailscale
falls back to a relay (DERP) on port 443 when direct UDP fails.

### 1.7 IPv6 footnote

IPv6 gives every device a globally unique address and in theory removes the need for
NAT. Residential IPv6 remains patchy, and firewalls block inbound traffic anyway. Don't
count on IPv6 to solve §1.2.

---

## 2. SSH — the universal remote shell

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

### 2.3 ssh-agent — typing the passphrase once

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

### 2.4 `~/.ssh/config` — your address book

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

Default port 22. Moving the port to something high (e.g. 22222) cuts noise from
internet bots, but **only if the SSH port faces the public Internet at all**. With
Tailscale the port stays private, so the change buys you nothing.

### 2.6 Port forwarding — three flavors

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

### 2.7 Mosh — SSH for flaky networks

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

## 3. tmux — keep the session alive

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
└── session  (e.g. "claude") — what you attach to
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

---

## 4. Keeping the Mac awake

### 4.1 macOS sleep modes, briefly

- **Display sleep** — screen off, machine still running.
- **System sleep** ("sleep") — RAM kept powered, CPU halted, network mostly off.
  Existing TCP connections die.
- **Hibernation / safe sleep** — RAM written to disk, machine fully off.
- **Lid-close sleep (MacBooks)** — *forced* sleep when the lid shuts unless an
  external display + power + keyboard/mouse is attached (clamshell mode).

A sleeping Mac cannot run your tmux session. The CPU has stopped executing.

### 4.2 `caffeinate` — the easy way

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

# Keep system awake as long as a specific process (e.g. tmux server) lives:
caffeinate -i -w $(pgrep -x tmux | head -1)
```

### 4.3 `pmset` — the heavier hammer

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

## 5. Tailscale — the easy mesh VPN

### 5.1 What it is

[Tailscale](https://tailscale.com) is a **mesh VPN built on WireGuard**. You install
it on every device you own and log into the same account, and every device can then
reach every other device by name, from anywhere, as if they shared a LAN.

### 5.2 Why it works without port forwarding

Both devices initiate **outbound** connections to Tailscale's coordination service.
Tailscale uses NAT-traversal (STUN, hole punching) to get the two devices talking
**directly** in most cases. When a direct connection fails (some symmetric NATs,
corporate firewalls), traffic falls back to a **DERP relay** on TCP/443, which any
network that allows web browsing also allows.

You never open a port on your router, and the "incoming connection" problem from §1.2
disappears.

### 5.3 Concepts you should know

| Concept | What it is |
|---------|-----------|
| **Tailnet** | Your private network of devices (one per account / org) |
| **Node** | A device on the tailnet |
| **Tailscale IP** | `100.x.x.x` — each node gets one. Stable. |
| **MagicDNS** | Resolve nodes by hostname (`home-mac`, `work-laptop`) without managing DNS |
| **ACLs** | Rules in `acl.hujson` controlling who can reach what, on which ports |
| **Tags** | Labels on nodes (e.g. `tag:server`) used by ACLs |
| **Subnet router** | Node that advertises a LAN range so others can reach LAN-only devices |
| **Exit node** | Node that routes *all* your traffic — used like a regular VPN |
| **Tailscale SSH** | SSH where Tailscale handles auth using your tailnet identity (no keys) |
| **Funnel** | Expose a node's port to the public Internet via Tailscale (HTTPS only) |
| **Serve** | Expose a node's port *within* the tailnet (no public Internet) |

### 5.4 Install & connect

macOS (CLI):

```sh
brew install tailscale
sudo tailscale up
# Opens a browser to log in. Then:
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

### 5.5 Tailscale SSH — kill your authorized_keys file

If you enable Tailscale SSH, the server delegates authentication to Tailscale:

```sh
sudo tailscale up --ssh
```

Now `ssh user@home-mac` from any logged-in tailnet device succeeds without managing
keys. ACLs you write in the admin console govern auth. Add 2FA on your Tailscale
identity (required for `check` ACL rules) for the strongest practical setup.

You can still use plain SSH alongside it.

### 5.6 MagicDNS

Once enabled (admin console → DNS → Enable MagicDNS), every node is reachable as
`<hostname>` and `<hostname>.<tailnet>.ts.net`. Rename a device:

```sh
sudo tailscale set --hostname home-mac
```

Pick short, distinctive names. Tailscale defaults to your machine's local hostname
(what `hostname` returns), which tends to be noisy, so override it so commands like
`ssh home-mac` stay readable.

### 5.7 Subnet router — reaching LAN devices

If you have a NAS, a printer, or a non-Tailscale device at home (`192.168.1.50`), put
Tailscale on a Mac at home and advertise the subnet:

```sh
sudo tailscale up --advertise-routes=192.168.1.0/24
# Then in the admin console, approve the advertised route.
```

Now from your phone on the train you can reach `192.168.1.50` as if you were home.

### 5.8 Exit node — full-traffic VPN

```sh
# On a node you want to use as exit:
sudo tailscale up --advertise-exit-node

# Approve in admin console, then on the client:
sudo tailscale set --exit-node=<node-name> --exit-node-allow-lan-access
```

Useful when you want all your traffic to appear from a specific location (your home
IP for geo-locked services, for instance). **Don't use a work device as your personal
exit node.** That mixes traffic across identities, the exact problem `ai` prevents.

### 5.9 ACLs — minimal example

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

### 5.10 Funnel & Serve — when you actually want to expose something

- `tailscale serve` — share a local port to your tailnet over HTTPS. No public Internet.
- `tailscale funnel` — same, but expose to the **public Internet** through Tailscale's
  edge. Good for webhook receivers and demos.

Examples:

```sh
# Share localhost:3000 to your tailnet over HTTPS:
tailscale serve --bg 3000

# Expose it to the entire Internet (read the security warning first):
tailscale funnel 3000
```

Do **not** funnel your SSH or Claude CLI. Funnel is for public web endpoints.

### 5.11 Tailscale on a work laptop

Read §8 first. In brief:

- A personal Tailscale account on a work laptop counts as shadow IT. Most security
  policies forbid it.
- Some employers run a corporate Tailscale tenant. Use **that** one if it exists.
- If you must mix, install Tailscale on a *personal* device that can act as the bridge
  (subnet router), and keep the work device off the personal tailnet.

---

## 6. Phone clients

### 6.1 iOS

| App | Notes |
|-----|------|
| **Blink Shell** | Paid, and the strongest option. mosh built in, keyboard support, scriptable. |
| **Termius** | Free tier is fine; cloud key sync; cross-platform. Note that it can store keys in its cloud. |
| **a-Shell** | Free and open source. Limited, but handy for quick SSH. |
| **Tailscale (iOS app)** | Required to put the phone on the tailnet. Always-on toggle works well in practice. |

### 6.2 Android

| App | Notes |
|-----|------|
| **Termux** | Real Linux env in a Play-Store/F-Droid app. Install `openssh`, `mosh`, `tmux` and use it natively. |
| **JuiceSSH** | GUI-friendly, classic. |
| **Termius** | Same as iOS. |
| **Tailscale (Android app)** | Same role as on iOS. |

### 6.3 Key management on a phone

Generate a key **on the phone**, copy its public key to the server, and keep the
private key on the phone only. Never paste your laptop's private key into a
cloud-syncing notes app to move it onto the phone.

If a phone is lost, you should be able to remove its public key from the server's
`authorized_keys` (or, with Tailscale SSH, just remove the device from the tailnet)
without affecting other devices.

### 6.4 The "phone keyboard sucks" reality

For more than 30 seconds of typing, a Bluetooth keyboard turns a phone into a usable
mini-laptop. Keep a small foldable one in your bag if you plan to do this often.

---

## 7. End-to-end workflows

### 7.1 Workflow A — phone → home Mac, long-running Claude task

**One-time setup on the home Mac:**

```sh
# 1. Install Tailscale + tmux + caffeinate (built in)
brew install tailscale tmux
sudo tailscale up --ssh
sudo tailscale set --hostname home-mac

# 2. Enable Remote Login (System Settings → General → Sharing)
# 3. Prevent sleep on AC power, indefinitely
sudo pmset -c sleep 0 disksleep 0

# 4. (Optional) start a long-lived tmux session at login via launchd or just manually
tmux new -d -s claude
```

**One-time setup on the phone:**

1. Install Tailscale, sign in to same account.
2. Install Blink Shell (or Termius / Termux on Android).
3. Generate a key in the SSH client; SSH into home Mac once using Tailscale SSH (no
   key needed) to verify connectivity.

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

### 7.2 Workflow B — work laptop → home Mac, after hours

If your work laptop allows installing Tailscale (check §8), same as A. Otherwise:

- Use the phone as a Tailscale-equipped hotspot for the work laptop. The work laptop
  is now on cellular through the phone; if you put the phone on the personal tailnet,
  the work laptop is not. (You'd need a second hop.)
- Easier: use the phone itself to SSH in, and treat the work laptop as a viewer.
- Cleanest: separate physical machine. See workflow D.

### 7.3 Workflow C — home → work laptop

Most workplaces block this on purpose, and bypassing it is a fireable offense.
**Don't.** When remote work is sanctioned, your employer provides the mechanism
(corporate VPN, virtual desktop). Use it.

### 7.4 Workflow D — always-on home server

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

# Install Claude Code / Codex however you do on Linux,
# then create a tmux session that holds them:
tmux new -d -s ai 'ai claude personal'  # if you have the ai router set up
```

From any device:

```sh
ssh $USER@home-server
tmux attach -t ai
```

Tradeoffs: extra hardware ($), one more box to maintain (security updates), and a
performance ceiling (a Pi handles chat fine but strains under large agentic loops).

### 7.5 Workflow E — flaky network on the road

```sh
mosh $USER@home-server -- tmux new -As road
```

mosh handles network drops, IP changes, and suspend/resume; tmux handles process
persistence. Together they let you close the laptop, walk into a tunnel, switch from
Wi-Fi to LTE, and open the laptop in a café 20 minutes later with the session intact.

---

## 8. Security & corporate policy

### 8.1 The non-negotiables

- SSH keys have **passphrases**, cached by `ssh-agent` / Keychain.
- 2FA on your Tailscale account.
- 2FA on every cloud account that grants access to anything on this tailnet (GitHub,
  Google, etc.).
- A separate Tailscale account for personal vs work tailnets — don't mix.
- Disable password SSH on any host reachable from the public Internet.

### 8.2 Tailscale-specific hygiene

- Use ACLs to limit who can reach what. Default-allow is convenient and dangerous.
- Use `tailscale ssh` with `check` mode for high-value boxes.
- Never `funnel` an SSH or shell endpoint.
- Periodically `tailscale status` and remove devices you no longer own.
- Rotate machine auth keys if a device is lost (admin console → expire key).

### 8.3 Work devices: get permission

Many corporate policies, in plain language:

- **No personal VPN software** on company devices. Tailscale counts.
- **No SSH out** to non-approved hosts. Some networks block port 22 outbound.
- **No remote access** to home machines that store work secrets. Even if it works
  technically, it's an exfiltration risk.

Ask your security/IT team in writing. They tend to say *yes* to "Tailscale on my
personal laptop", *it depends* for the work laptop, and the conversation itself keeps
you out of trouble.

### 8.4 The `ai` router and security

[ai-session-router](../../README.md) exists to prevent identity mix-ups. Remote access
shifts the threat model:

- If someone compromises a phone and can unlock SSH, they reach your home tailnet.
- So require an SSH key passphrase, biometric unlock on the phone, and an SSH client
  that re-authenticates after backgrounding (Blink and Termius both support this).
- The AI tool writes logs to the **workspace** on the host where it ran, which means
  the server, not the phone. That's intentional and correct.

### 8.5 What to do if you suspect a device is compromised

1. From the Tailscale admin console: expire the device's key. It instantly drops off
   the tailnet.
2. Rotate any SSH public keys present on the device (replace `authorized_keys`
   entries on all servers).
3. Rotate API tokens that might have been on disk (Claude / Codex account roots; see
   `~/.claude-*`, `~/.codex-*`).
4. If the device held work credentials, tell your security team. *Before* §1.

---

## 9. Troubleshooting

### 9.1 "Connection refused"

The TCP port is reachable but nothing is listening. The service is down, or you're
hitting the wrong port. On the server:

```sh
# Is sshd running?
sudo launchctl list | grep ssh    # macOS
sudo systemctl status sshd        # Linux

# Is it listening?
sudo lsof -iTCP:22 -sTCP:LISTEN
```

### 9.2 "Connection timed out"

Something between you and the server is dropping packets: NAT, firewall, or routing.
With Tailscale, run this on both ends:

```sh
tailscale status               # both nodes online?
tailscale ping <peer>          # direct connection? if it falls back to DERP, that's still working but slower
```

### 9.3 "Permission denied (publickey)"

The server rejected your key. Diagnostic SSH:

```sh
ssh -vvv user@host  2>&1 | grep -E 'identity|publickey|Offering|Accepted|denied'
```

Common causes:

- Public key not in server's `~/.ssh/authorized_keys`.
- Permissions on `~/.ssh` or `authorized_keys` too loose (must be `700` and `600`).
- Server config disabled pubkey auth (check `/etc/ssh/sshd_config`).
- Wrong user (`ssh root@host` when the key was added for a different account).

### 9.4 "tmux session disappeared"

Two main causes:

- The host rebooted (e.g. the Mac slept hard, then was restarted). tmux sessions are
  in-memory.
- A different user is logged in — `tmux ls` only shows the current user's sessions.

Mitigations: `pmset -c sleep 0` on a desktop Mac; or a real server; or
[tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) for the few cases
where you need session contents to survive restarts.

### 9.5 "Tailscale says I'm online but I can't reach the peer"

```sh
tailscale status               # is the peer online?
tailscale ping <peer>          # latency? direct vs DERP?
tailscale netcheck             # local network diagnostics
```

If `netcheck` shows everything blocked except port 443, you're behind a strict
firewall. DERP fallback still works, but slower.

### 9.6 "MagicDNS doesn't resolve"

```sh
scutil --dns | grep -A2 'resolver #1'   # macOS: is 100.100.100.100 a DNS server?
tailscale set --accept-dns=true         # ensure DNS acceptance is on
```

VPN clients that override DNS can interfere.

### 9.7 "SSH disconnects after a few minutes idle"

Add to client `~/.ssh/config`:

```
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

Or on the server, add `ClientAliveInterval 60` to `sshd_config`.

### 9.8 "Mac slept anyway"

Check what's currently allowed to prevent sleep:

```sh
pmset -g assertions
```

You should see a `PreventUserIdleSystemSleep` entry held by `caffeinate` or your
running process. If it's missing, your caffeinate exited or never started.

---

## 10. Integration with `ai`

The `ai` command (this repo) already separates accounts, workspaces, and browsers.
Remote access adds *which host* to the mix, and the axes stay independent.

### 10.1 Running `ai` over SSH

```sh
ssh home
tmux new -As claude
ai claude personal              # exactly the same as if you were sitting at the Mac
```

The router writes its logs where it always does: `<workspace>/.ai-logs/...` *on the host
where ai ran*, the home Mac rather than your phone. That's by design.

### 10.2 `ai remote doctor`

This command reports remote-access state and never configures it:

- Tailscale status / IP / online peers
- sshd listening?
- tmux sessions present?
- Hostname (to confirm you're on the host you think you are)

Run it after changes to verify, e.g. after `sudo tailscale up --ssh`.

### 10.3 A clean shell hook

A useful `.zshrc` snippet for the **client** side (laptop / phone Termux):

```zsh
# One command to land in a known tmux session on home
home-ai() {
  ssh -t home "tmux new -As ai 'cd ~/dev/personal && ai claude personal'"
}
```

Now `home-ai` from anywhere drops you into a tmux session running Claude on the home
Mac with the right account and workspace.

### 10.4 What `ai` deliberately does *not* do

- It does **not** configure Tailscale (no token storage, no `tailscale up` calls).
- It does **not** start tmux for you in `ai claude/codex` — that's your shell's job.
- It does **not** forward credentials over the network. Account auth lives where each
  account's config root lives, on the host running `ai`.

These boundaries are deliberate. A router should not own VPN setup, sleep policy, or
remote process management. Use the tools in this document for those concerns, and use
`ai` for identity routing.

---

## Appendix A — Quick command cheatsheet

```sh
# SSH key
ssh-keygen -t ed25519 -C "you@example.com"
ssh-copy-id user@host
ssh-add --apple-use-keychain ~/.ssh/id_ed25519

# Tailscale
brew install tailscale
sudo tailscale up --ssh
tailscale status
tailscale ip -4
tailscale ping <peer>
tailscale netcheck

# tmux
tmux new -As ai
tmux ls
tmux attach -t ai
# prefix-d to detach

# Sleep control
caffeinate -dims          # block all sleep until Ctrl-C
caffeinate -i -t 3600     # block idle sleep for 1 hour
sudo pmset -c sleep 0     # never sleep on AC (persistent)
pmset -g assertions       # what's preventing sleep right now

# Diagnostics
ai remote doctor          # this repo's command
ssh -vvv user@host        # verbose SSH
sudo lsof -iTCP -sTCP:LISTEN
```

## Appendix B — Recommended reading

- `man ssh`, `man ssh_config`, `man sshd_config`
- `man tmux` (long, but the only authoritative source)
- `man caffeinate`, `man pmset`
- [Tailscale docs](https://tailscale.com/kb/)
- [WireGuard whitepaper](https://www.wireguard.com/papers/wireguard.pdf) (if you want the crypto)
- [mosh paper](https://mosh.org/mosh-paper.pdf) (why mobile SSH should use UDP)
- This repo's [ARCHITECTURE.md](./ARCHITECTURE.md), [COMMANDS.md](./COMMANDS.md),
  [PORTABILITY.md](./PORTABILITY.md)
