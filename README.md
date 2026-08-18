# The Context Kit
by Mats Kaposty

[![Release](https://img.shields.io/github/v/release/kaposty/context-kit)](https://github.com/kaposty/context-kit/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-blueviolet)](#install-as-a-claude-code-plugin)
[![Tests](https://img.shields.io/github/actions/workflow/status/kaposty/context-kit/test.yml?label=tests)](https://github.com/kaposty/context-kit/actions/workflows/test.yml)
[![Verification](https://img.shields.io/badge/verification-85%20assertions-blue)](#verify-then-prove)

**Ledger · Checkpoint · Guardrail**

**A long session makes Claude Code dumber, and the summary is why.** When the window fills,
the harness compacts: it keeps roughly what happened and loses why. So a later turn re-opens
a settled question, re-verifies a proven fact, or proposes the approach you abandoned two
hours ago for a good reason.

This kit is the fix, and it is three things: a small file that carries the reasoning across
the summary, a pass that brings every durable store current before you compact, and a
guardrail that refuses an unprepared compaction. Nothing here assumes a language, a stack,
or a repository layout.

> [!IMPORTANT]
> **`/compact` decides WHEN the context shrinks. This kit decides WHAT survives it:** the
> reasoning is written to disk *before* the summary is taken, the durable stores are brought
> current in the same pass, and a compaction from an unprepared state is refused rather than
> quietly lossy.

**Contents:** [Requirements](#requirements) · [Install](#install-as-a-claude-code-plugin) · [Verify, then prove](#verify-then-prove) · [Coming back](#coming-back-after-the-agent-worked-without-you) · [What you experience](#what-you-actually-experience) · [Limits](#what-it-does-not-do) · [Read next](#read-next) · [License](#license)

**You operate two commands, plus one for when you have been away. Everything else is silent.**

```
/checkpoint     bring the durable context current, then
/compact        compact from a prepared state

/brief          what happened since you last looked
```

**Or just say it.** "prepare for compaction", "before the compact", "ready to compact" and
the like run the checkpoint too. **English and German ship in the list**, and that is a list,
not an understanding: the hook matches patterns, so a language nobody wrote down does not
fire. Adding one is a line in `hooks/prompt-checkpoint.sh`, which is why the patterns are
spelled out per language instead of packed into one clever regex. (Typing `/checkpoint`
always works, in every language, and so does asking for it in your own words while the skill
description is still loaded.) That path is a hook rather than a skill
description on purpose: descriptions are the one piece of startup content a compaction does
not restore, so a description-only trigger works until the first compaction and then goes
quiet, which is exactly when you would be asking for it. A hook is configuration, it is
re-read every turn, and it survives. It only ever injects the instruction, it never blocks or
edits your message, and it ignores anything over 160 characters so that talking *about* the
checkpoint does not start one. Off switch: `SESSION_LEDGER_PROMPT_TRIGGER=off`.

**One naming detail that will otherwise waste your first minute, and can cost more than that:**
installed as a plugin, the commands are namespaced, so it is `/context-kit:checkpoint`,
`/context-kit:brief` and `/context-kit:prove`. Installed standalone, into `.claude/commands/`,
the plain names are the right ones. Everything below writes the short form for readability.

**Read the completion menu before you press enter.** `checkpoint` is also an alias of the
built in `/rewind`, which restores your code and conversation to an earlier point, so the
menu offers you both while you are still typing. Nothing fires by accident: on the plugin path,
`/checkpoint` answers "isn't available in this environment", and standalone the project
command wins and runs this kit's pass. Both measured. The risk is only that you pick the
wrong line out of the menu, and the namespaced form removes it.

**Type the commands, do not describe them.** Asking for "a checkpoint before we compact"
works in a fresh session, because the skill descriptions are loaded at startup. They are the
one piece of startup content that a compaction does not restore, so from your second
compaction onward in the same session the description route is gone while the command still
works. GUIDE section 3 has the citations.

## Requirements

`bash` and `python3` on your PATH. The hooks are POSIX shell, and `python3` does two jobs
they cannot do safely in shell: it JSON-encodes the hook output, and it runs the restore
budgeting. **Without `python3` the kit still works and degrades honestly:** the restore falls
back to a plain cut, marks itself `INCOMPLETE` instead of printing the canary, and the
session-start block becomes visible text instead of a suppressed result. So the "you see
almost nothing" promise below holds with `python3` present. No Windows support outside WSL.

Measured on both: macOS with the bash 3.2 it still ships, and Ubuntu 24.04 with bash 5.2 and
Python 3.12 on arm64, 85 of 85 green in each. Both matter for a real reason: `stat -f %m` is
mtime on BSD and mount point on GNU, and that difference shipped a silent defect once.

## Install (as a Claude Code plugin)

As a plugin, which is how Claude Code distributes this kind of thing:

```shell
/plugin marketplace add kaposty/context-kit
/plugin install context-kit@context-kit
/reload-plugins
```

Installing from a local clone works too, and is the honest way to try it before trusting a
remote: `/plugin marketplace add /path/to/context-kit`.

Or standalone, if you would rather have the files in your project. **Look before you copy.**
The kit claims the names `brief`, `checkpoint`, `prove` and `session-ledger`, which are about
the most generic in the whole namespace, and `cp -R` overwrites a file of the same name
without a word. This prints what would go, and changes nothing:

```bash
KIT=path/to/context-kit
(cd "$KIT" && find hooks skills commands tools -type f ! -name hooks.json ! -name '.DS_Store') \
  | while read -r f; do [ -e ".claude/$f" ] && echo "WOULD OVERWRITE: .claude/$f"; done
```

Nothing printed means nothing of yours is in the way, so copy. Something printed means that
file is yours and the kit is about to take its name: rename yours first, or take the plugin
path instead, where the two live side by side under different names (`/brief` stays yours,
`/context-kit:brief` is the kit's).

```bash
# The same derived list as the check above, so what gets copied is exactly what was checked.
# `cp -R hooks/.` looks shorter and is wrong: it also brings hooks.json, which is the plugin
# wiring and does nothing in a standalone install, and it carries .DS_Store along. Found by
# running this block and then the uninstall below, and seeing what stayed behind.
(cd "$KIT" && find hooks skills commands tools -type f ! -name hooks.json ! -name '.DS_Store') \
  | while read -r f; do mkdir -p ".claude/$(dirname "$f")"; cp "$KIT/$f" ".claude/$f"; done
cp "$KIT"/.kit-manifest .claude/.kit-manifest
# Only the kit's own scripts, listed rather than globbed: `chmod +x .claude/hooks/*.sh`
# would also change the mode of scripts that belong to your project.
(cd "$KIT" && find hooks tools -name '*.sh') | while read -r f; do chmod +x ".claude/$f"; done
```

The `.kit-manifest` line is the one people skip, and it is the only one that keeps this copy
honest later. It is a digest per delivered file, so the installation can tell you it
has fallen behind without needing the kit next to it. Leave it out and the check finds
nothing to compare against and stays silent forever, which reads exactly like a healthy
install. Copy it again whenever you update, since it is generated by `sync.sh` and describes
the version it was written for. A file you change on purpose goes into `.claude/.kit-adopted`,
one relative path per line, and stops being reported. Switch the whole thing off with
`SESSION_LEDGER_KIT_INTEGRITY=off`.

What this answers is "are my files the ones that shipped", not "is there a newer version".
An install is offline and standalone, so the second question has no local answer. That is a
real limit, and it is stated rather than hidden: it caught both defects that actually
happened here, a hook file missing entirely and a set of files a generation old.

**If the commands do not show up, start a new session.** Right after installing,
`/checkpoint` can answer "No matching commands" and the install looks broken when it is
merely not loaded yet. What is measured: a session started after the files exist resolves
them immediately, and `/reload-skills` does not do it (it reported "no changes" while the
command stayed missing, because it reloads skills, not the command list). What is **not**
understood: the list can also refresh on its own a while later, without a restart. So a new
session is the reliable move, not the only one. `/reload-plugins` is the equivalent step on
the plugin path and is already in the block above.

The first `/brief` or `/prove` asks once for permission to run its script, because both call
into `.claude/tools/`. That is normal, it is one approval per project, and the kit does not
grant itself shell access from a skill file to avoid it.

Then merge the `hooks` and `env` blocks from `settings-snippet.json` into
`.claude/settings.json`. The plugin install brings its own hook wiring, so it needs only the
`env` block.

**"Merge" is the whole instruction, and it is easy to get wrong in the one place that hurts.**
`hooks.Stop` and `hooks.UserPromptSubmit` are arrays, not values. Setting them to the kit's
entry removes your own hooks for those events, silently, and nothing later says so. This does
it correctly: your entries stay and the kit's are appended, your own `env` keys survive, and
the explanatory `_comment` does not travel into your settings.

```bash
jq -s '
  .[0] as $mine | (.[1] | del(._comment)) as $kit |
  $mine
  | .env   = (($mine.env // {}) + ($kit.env // {}))
  | .hooks = (reduce ($kit.hooks // {} | keys_unsorted[]) as $e (($mine.hooks // {});
              .[$e] = ((.[$e] // []) + $kit.hooks[$e])))
' .claude/settings.json "$KIT/settings-snippet.json" > .claude/settings.merged.json
# read it, then: mv .claude/settings.merged.json .claude/settings.json
```

For the plugin path, replace the two `.hooks` lines with nothing: only `.env` is yours to
merge.

**One warning that only applies to the standalone path:** `.claude/settings.json` is read
only from the directory you start Claude Code in, and there is no walk up the tree. Start a
session in a package directory of a monorepo whose kit sits at the root, and all four hooks
are gone, silently and with exit 0. Start from the directory that holds `.claude/`, or
install as a plugin, which is immune because a plugin lives outside the project it serves.

**One line of that block is the point:** `"DISABLE_AUTO_COMPACT": "true"`. Auto-compaction
gives the model no turn to prepare, so this kit turns it off and makes compaction
deliberate. A plugin cannot ship environment variables, so this stays a manual edit either
way. Everything else has a working default.

**And that line has a price, so here it is before you pay it.** Auto-compaction is the
harness's own net for a full window. With it off, nothing compacts unless you run `/compact`,
and a session that misses its cue runs into the wall. The kit's replacement is the self-firing
checkpoint in `ledger-lint.sh`, and that ships **off**, because a pass that interrupts work
nobody asked to interrupt was measured as worse than the problem. So a fresh install has the
net removed and no substitute wired in, by design and by your choice. If you would rather be
nudged than rely on the habit, set `SESSION_LEDGER_CHECKPOINT_TRIGGER=on` in the same breath.

**The kit writes, so it needs to be allowed to write.** Two cases where it silently does
nothing, both measured in a real project:

- **Plan mode.** Every write is refused there, including the ledger's. That is the harness
  working as intended, but it means the phase where most decisions get made is the phase the
  ledger cannot record. Leave plan mode before the checkpoint, or accept that the reasoning
  from it reaches the ledger only afterwards, from memory.
- **Paths outside the project.** `.claude/session-ledger.md` is inside it and needs nothing.
  A plan file under `~/.claude/plans/` is not, and a write there is refused unless
  `permissions.additionalDirectories` names the location. Measured: three refused writes in a
  row, the session carried on without a plan file, and nothing said why.

Finally, two blocks in your project's `CLAUDE.md`. Both are load-bearing, and both cost
almost nothing, because that file is loaded anyway. They are also in
[CLAUDE.example.md](CLAUDE.example.md), ready to append. **Append, never replace:** that file
carries your own rules and this only adds to them.

```bash
cat path/to/context-kit/CLAUDE.example.md >> CLAUDE.md
```

```markdown
# Compact instructions

Keep the reasoning, drop the bookkeeping: decisions and what they beat, facts with the
command that proved them, abandoned paths and why, and the single next action. Leave out
re-derivable state (branch, open reviews, build status) and raw tool output.

## After a compaction

If you do not see a `Canary CTX-LEDGER-RESTORED` line in context, read
`.claude/session-ledger.md` before continuing.

Before answering "I have no record of that": the ledger carries this task only. Anything
older lives in the project state file named in the ledger's `PLAN` section. Read it instead
of declining.
```

The first aims the summary at what matters, the second is the reliable way the reasoning
comes back when a hook loses its race.

Optional, and the thing that makes the kit yours rather than generic: copy
`context-manifest.example.yaml` to `context-manifest.yaml` in your project root and name your
durable stores in it. Without it the checkpoint finds them by convention and says which ones
it reconciled, which is softer but works.

**If your project already keeps a state file, say so before the first checkpoint.** The
second carrier defaults to `.claude/project-state.md`, and that default is only right for a
project that has none. Set `SESSION_LEDGER_PROJECT_STATE` in the `env` block (or
`durable_context.project_state` in the manifest) to the file you already have, or the
checkpoint starts a rival document beside it and the two drift. Measured in a repository with
an 83 KB curated status file: nothing named it, so the kit was one pass away from writing a
second truth.

Two files the kit keeps are durable, not runtime, so they stay **out** of the ignore list and
**in** version control: `.claude/project-state.md` (where the project stands, what was
decided, what was dropped, across tasks) and the manifest. Everything else below belongs to
the session, not to the source, so add it to your `.gitignore`:

```gitignore
.claude/session-ledger.md
.claude/session-ledger.archive/
.claude/.checkpoint-ready*
.claude/.ledger-lint-state
.claude/.checkpoint-trigger-state
.claude/.effect-probe/
.claude/log/
```

**Taking it back out.** A thing you install into your own `.claude/` should be removable
without archaeology, so here is the reverse of the block above. It uses the same derived list,
which is why it cannot reach a file that was never the kit's:

```bash
KIT=path/to/context-kit
(cd "$KIT" && find hooks skills commands tools -type f ! -name hooks.json ! -name '.DS_Store') \
  | while read -r f; do rm -f ".claude/$f"; done
find .claude/skills .claude/hooks .claude/commands .claude/tools -type d -empty -delete
rm -f .claude/.kit-manifest .claude/.checkpoint-ready* .claude/.ledger-lint-state \
      .claude/.checkpoint-trigger-state
# then take the kit's hook entries and its DISABLE_AUTO_COMPACT / SESSION_LEDGER_* keys back
# out of .claude/settings.json, and the appended block back out of CLAUDE.md
```

What deliberately stays: `.claude/session-ledger.md`, your project state file, and
`.claude/log/`. Those are what the kit produced for you, not what it put there, and deleting
someone's record of their own reasoning is not an uninstall. Remove them yourself if you want
them gone. On the plugin path there is nothing to reverse at all: `/plugin uninstall
context-kit@context-kit` leaves the project as it was, which is the strongest argument for
taking that path in the first place.

## Verify, then prove

Two different questions, and most tools only answer the first.

```bash
bash tests/run.sh    # 85 assertions over the renderer, the hooks and the tools
```

That proves the **mechanics**: the parts behave, the budget holds, the canary is never
printed over a damaged restore. Run it against the commit before the release shaping and many
go red, so the net can actually fail. One of the 85 is aimed at the suite itself: a checker
that dies must go red, not silently green, which is how a broken check once passed while
measuring nothing.

It does not prove **effect**, and firing is not effect. For that, run `/prove`. It plants a
fact with a random token into the two ledger sections a bad budget would evict first, has you
run a real `/checkpoint` and `/compact`, and then asks whether the model still knows why that
approach was abandoned. Green means the reasoning survived in context. Yellow means the model
had to read the file, which is the documented normal case. Red means the kit failed its own
core claim, and it will say so.

It has been run. In a throwaway project with the kit installed as a plugin, a token was
planted in the ledger and never mentioned in the conversation. After a real `/compact` the
model was asked what happened with that approach and answered with the token, the reason,
and the dropped status, **without opening a file**: no tool call in that turn. That is the
green case, not the documented yellow one.

**What this does not prove.** One green run on a short session is evidence, not proof, so run
your own. The probe measures whether a planted fact comes back, never whether the checkpoint
wrote down everything worth keeping, and that judgement is the one part of this kit no check
can make for you. The numbers in this README come from the author's own measurements on the
author's own projects; every one of them names the command it came from, so they can be
disagreed with rather than believed. And nothing here is a claim about *other* harnesses: the
mechanisms are generic, the wiring is Claude Code specific, and the suite runs against that
one.

## Coming back after the agent worked without you

The built in displays answer *what is configured*: `/status` shows the active settings
sources, `/permissions` the resolved rules, `/context` what is loaded. None of them answers
*what happened*, which is the only question you have after leaving an agent to work.

`/brief` answers it. The window is everything since your last `/brief`, taken from the
transcript itself, so there is no marker file and no clock to drift; pass `24h`, `90m`, `3d`
or a date to override it. It reads the transcript, git and the hook log for facts, then the
ledger and the project state file for the reasons, and writes six short blocks:

| | Block | Holds |
|---|---|---|
| 🟢 | Progress | finished and backed by evidence |
| 🟡 | In progress | still running, or started and left half done |
| 🔴 | Blocked | waiting on you or on something outside |
| 💡 | Learned | knowledge that outlives the task |
| ⚠️ | Open problems | failures, findings, unsaved reasoning |
| ➡️ | Next | recommended steps, cheapest useful order first |

A block with nothing in it does not appear, so the shape of the report is itself the signal:
a calm day is two blocks, a bad one is six. Every line is tagged `[measured]` or `[read]`, so
a failing command and an impression never share a voice.

Two things it will not do. **It writes no file**, not even a marker: a briefing is
re-derivable, and a stored one only goes stale. **It changes nothing**, it names the next
steps and stops. It is the mirror image of the checkpoint, which writes for the model so
reasoning survives a compaction; this one writes for you, once, and dies when you have read it.

## What you actually experience

Almost nothing, and that is deliberate. The kit speaks to the model, not to you: hook output
is delivered as a suppressed JSON result, so it reaches the model as a system reminder and is
never rendered in the transcript. Measured before and after on a real session start: 2200
characters shown, then 0 shown and 2664 delivered.

You see exactly one thing: the guardrail refusing a `/compact` that would compact from an
unprepared state. If you see anything else, that is a defect.

The kit can also fire the checkpoint itself once enough work has piled up, and it ships
**off**. A pass that starts on its own interrupts work nobody asked to interrupt, and the
guardrail already refuses an unprepared compaction, so nothing is lost by waiting for you.
Opt in with `"SESSION_LEDGER_CHECKPOINT_TRIGGER": "on"` if you would rather be nudged than
blocked.

## What it does not do

- It does not re-inject your instruction file or memory index. The harness already re-reads
  both from disk; duplicating them would burn the hook output cap the ledger needs.
- It does not snapshot mechanical state. Branch, open reviews, build status are one command
  away, so they are recomputed, never carried.
- It does not promise the summary will keep your reasoning. It routes around the summary.
- It cannot preserve what the model never wrote down. A hook sees files, never the
  conversation. This is a discipline with mechanical support, not an automatism.

## Read next

| File | What it is |
|---|---|
| [GUIDE.md](GUIDE.md) | How it works, part by part: the mechanisms, the harness contract, a walked-through day, and the questions everyone asks. |
| `context-manifest.example.yaml` | The per-project config: names the durable stores the checkpoint reconciles, so no paths are hardcoded. |
| [CONTRIBUTING.md](CONTRIBUTING.md) | The bar a change has to clear here, above all: a new assertion is seen red against the broken state before it is kept. |
| [SECURITY.md](SECURITY.md) | What the kit runs on your machine, what it reads, what it writes, and where to report a problem. |
| [CHANGELOG.md](CHANGELOG.md) | What changed between versions. |

## License

MIT, see [LICENSE](LICENSE). Copyright 2026 Mats Kaposty. Use it, fork it, ship it inside
your own tooling; the only thing asked back is that a claim you copy from here keeps the
measurement that earned it.

---

*context-kit · by Mats Kaposty · MIT*
