# Explain like I'm 5: what this tool did

**Language:** English · [한국어](../ko/ELI5.md)

A plain-language explanation of what the `ai` command in this repo was for, written so
someone seeing it for the first time can follow.

## The one core idea

AI tools like Claude Code and Codex keep your login, your past chats, and your settings
all in **one folder**. Which folder that is comes from a single environment variable (a
setting a program reads when it starts): `CLAUDE_CONFIG_DIR` for Claude, `CODEX_HOME` for
Codex.

So "switching accounts" really just means pointing that variable at a **different
folder**. Point it at the work folder and the tool starts as your work account; point it
at the personal folder and it starts as personal.

That is all `ai` did: set that variable to the right folder just before launching the
tool.

## One everyday comparison

Picture two desk drawers. The left drawer holds personal things, the right one holds work
things. If you just decide which drawer to open before you start, the day's things never
get mixed up. `ai` was the hand that picked the drawer for you before each launch.

## Why it existed

If you use AI tools for both personal and work, by default they want to share one folder:
one login, one bill, one chat history, all mixed together. Separate drawers keep them
apart.

## Where things stand now

Orca now does this session-picking job, so this repo has been archived. To return your
machine to its original state, see [TEARDOWN.md](TEARDOWN.md).

For the full mechanism, see [ARCHITECTURE.md](ARCHITECTURE.md) and
[HOW-IT-WORKS.md](HOW-IT-WORKS.md).
