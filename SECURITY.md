# Security Policy

## Supported versions

Only the latest release receives fixes. There is no backporting.

## Reporting a vulnerability

Unlike a prose-only skill, this kit ships **executable code**: shell hooks that Claude Code
runs on its own, without asking, several times per session, plus one Python file. That is the
real surface, so findings in it are welcome.

1. Preferred: open a private report via GitHub Security Advisories ("Report a vulnerability"
   on the Security tab of https://github.com/kaposty/context-kit).
2. Alternatively: open a regular issue if the finding is not sensitive.

You should get a first response within a week.

## What runs, and when

| Event | Script | When it runs |
|---|---|---|
| `SessionStart` | `session-start-prime.sh`, `session-start-reinject.sh` | at startup, and again after a compaction, a resume or a fork |
| `UserPromptSubmit` | `prompt-checkpoint.sh` | on every message you send |
| `PreCompact` | `precompact-guard.sh` | when you run `/compact` |
| `Stop` | `ledger-lint.sh` | when a turn ends |

`prompt-checkpoint.sh` is the only one that sees your message text. It never blocks or edits
it: it matches a short list of phrases and, on a match, injects the checkpoint instruction.
Anything over 160 characters is ignored outright. Turn it off with
`SESSION_LEDGER_PROMPT_TRIGGER=off`.

## What it reads

- Files under the project's `.claude/`: the ledger, the project state, the markers.
- Git, for the working-tree state shown in a briefing.
- **The session transcript**, under `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/`, and only
  when you run `/brief` or `/prove`. This is the part worth knowing about: the transcript
  holds your whole conversation, so a briefing can quote excerpts of it back onto your screen.
  It is your own file and it never leaves the machine, but if you share a screenshot of a
  briefing, share it as you would share the conversation itself.

## What it writes

Only inside the project's `.claude/` directory (the ledger, its archive, the markers and the
hook log), plus one directory outside it: `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/effect-probe/`,
where `/prove` keeps the answer key to its own measurement. That one is outside on purpose,
because the checkpoint inventories the project and would otherwise read the answers to the
test it is about to sit.

## What it does not do

**No network access, at all.** Nothing in the delivered hooks, tools, skills or commands
opens a connection, and there is no telemetry, no update check and no phone-home. Check it
yourself, the whole delivery is shell and one Python file:

```bash
grep -rnE '\b(curl|wget|nc|ssh|scp|urllib|requests\.|socket|http)' hooks/ tools/ skills/ commands/
```

That command returns nothing on a clean checkout. It also means the integrity check can only
answer "are my files the ones that shipped", never "is there a newer version": an installation
has no way to ask.

It runs no code it did not ship with, installs nothing, and touches no file outside the two
locations above.

## Trusting the copy you have

`.kit-manifest` is a digest per delivered file and travels with an installation, so a copy
that has drifted or fallen behind reports it at the next session start instead of looking
healthy. Files you changed on purpose go into `.claude/.kit-adopted`, one relative path per
line, and stop being reported. This detects accident and drift; it is not a signature and it
is not a defense against someone who can edit the manifest too.
