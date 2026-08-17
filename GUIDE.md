# GUIDE: how the kit works

Everything you need to understand, extend, or distrust this kit. [README.md](README.md) is
the entry point.

## 1. Three kinds of things that get confused

| Kind | Who runs it | When | Can it judge? |
|---|---|---|---|
| **File** | nobody, it just sits there | always | no, it is content |
| **Hook** | the harness (shell) | on an event, deterministic | no, shell logic only |
| **Skill** | the model | when invoked or triggered | yes, that is the point |

**A hook never knows what you decided.** It sees files and git state, never your reasoning.
That single fact forces the entire shape of this kit: the model writes the reasoning down,
the hooks only carry and enforce.

## 2. The Session Ledger

A plain markdown file at `.claude/session-ledger.md`. No process, no daemon. Seven sections,
in the order a compacted window reads them: orientation first, reference material after.

| Section | What goes in |
|---|---|
| `TASK` | one line: what this session is trying to achieve |
| `NEXT` | one line: the single most valuable next action, readable cold |
| `OPEN` | a question still unresolved, and what would settle it |
| `DECIDED` | a decision, and what it beat |
| `VERIFIED` | a fact, and the exact command that proved it |
| `DROPPED` | an abandoned path, and why, so it is never retried |
| `PLAN` | a pointer to the active plan file. A path, never a copy |

`NEXT` pays off fastest. Everything else says what happened; `NEXT` says what to do, and that
is the one thing a freshly compacted window cannot re-derive. A stale `NEXT` is worse than
none, because it gets followed.

`VERIFIED` carries the command, because a fact without provenance degrades into a belief the
moment a summary paraphrases it. `DROPPED` is the section people skip and regret: an
abandoned approach without its reason will be proposed again, confidently, by a future turn
that has no memory of why it failed.

**Never in it:** secrets; copies of files that survive on their own (instruction files, the
memory index); re-derivable status (branch, open reviews, todos, build state). A ledger that
fills with status has become the thing it was built to replace.

**What outlives the task lives elsewhere.** The ledger is mortal on purpose: a new task
archives it, and `DECIDED` and `DROPPED` go with it. That is the gap `.claude/project-state.md`
closes. Three carriers, separated by **reach**, and the test is one sentence: *would this be
useful in a different project?*

| Carrier | Reaches across | Carries | In git? |
|---|---|---|---|
| `.claude/session-ledger.md` | one task, across compactions | the working set in hand | no |
| `.claude/project-state.md` | every task in this project | where it stands, next steps, decisions, dropped paths | yes |
| the memory store | every project | techniques, platform traps, how the user works | harness-managed |

The checkpoint reconciles all three, in place. Only the ledger is restored into context by a
hook; the other two are read when they are needed, which is why they may be longer.

**When the model writes:** only on five events. A decision locks, a fact is verified, a
question opens, a path is abandoned, the goal changes. A quiet turn writes nothing. Items are
resolved **in place**: an answered `OPEN` becomes a `DECIDED` or `VERIFIED` and leaves
`OPEN`. It is a working set, not a changelog.

**Age never retires it.** Chats are timeless: a conversation picked up a week later has
exactly the context it had. Two age-based rules were tried here and both destroyed
continuity, the second one invisibly, by archiving the ledger of an old session that was
still alive as soon as a new session opened in the same directory. What is checked now is
ownership: the ledger carries the id of the session that wrote it, and a mismatch is restored
**and** flagged, so the model can archive it on the first turn if the task really is a
different one.

## 3. The harness contract

Stated once, here, because every other part of this kit is a consequence of it. Sourced from
the Claude Code documentation and corrected by live measurement where the two disagreed.

**What survives a compaction, from disk:** the project-root `CLAUDE.md`, unscoped
`.claude/rules/`, auto memory, and invoked skill bodies up to a budget. **What does not:**
your conversation, and with it your reasoning. Path-scoped rules and nested `CLAUDE.md` files
drop out until a matching file is read again.

**What a hook can and cannot do:**

- A `PreCompact` hook can only block the compaction or run a side effect. Its output goes to
  **you**, never to the model, so it cannot instruct anything at compaction time.
- A `Stop` hook can deliver `hookSpecificOutput.additionalContext`, which reaches the model as
  a system reminder, does not block the turn, and is not rendered in the transcript. This is
  the only place where a hook can still buy the model a turn to prepare.
- A `SessionStart` hook can inject context. Plain stdout is both injected **and** displayed; a
  JSON result with `suppressOutput` plus `additionalContext` is injected only. That is why
  this kit is silent.
- Hook output is capped at 10,000 characters. Past the cap the whole block is replaced by a
  file pointer, so a fat re-inject silently becomes no re-inject.
- `PostCompact` exists, and its output goes to the user only. **Do not use it for a restore.**
  One was tried here and failed live with "Hook cancelled", before the documentation confirmed
  it could never have worked.

**The skill listing does not survive a compaction, and this changes how you drive the kit.**
Startup content reloads afterwards, CLAUDE.md and memory included. The list of skills and
their descriptions is the documented exception: it is not re-injected, and only the skills
you actually invoked keep their bodies, capped and oldest discarded first. The consequence
here is concrete. In a fresh session "prepare the compaction" reaches the checkpoint by
description. After the first `/compact` that route is gone, so the second checkpoint of the
same session, and every one after it, needs the typed command. **That is what the command
files are for**, and it is why this kit ships one for every skill you are meant to reach.
Two habits follow: type `/checkpoint` and `/brief` rather than describing them, and keep a
skill body short enough to be worth re-appending (all three here are well under the cap).
This is documented behaviour, cited in four places in the Claude Code documentation, and it
has not been re-measured here. The probe, if you want it: in a session with a skill you never
invoked, note `/context`, compact, then write a prompt that matches that skill's description
exactly and see whether it still fires.

**What can steer the summary:** not a hook, but you. `/compact <instructions>` and the
`# Compact instructions` section of `CLAUDE.md` both reach the summariser. Use them, and do
not lean on them: they aim the summary, they do not guarantee what survives.

**Measured, not assumed (2026-07-23 to 07-26, real sessions):**

- The reasoning survived a real auto-compaction and a "prompt too long" crash. Nothing lost.
- `SessionStart` with matcher `compact` fires on a manual `/compact`, but a few minutes late,
  so it can lose the race with your next message. Best-effort, kept.
- A running auto-compaction raises no `SessionStart` at all.
- The silent injection was verified in the session transcript on disk: the `SessionStart`
  entry carries `content: ""` and a separate `hook_additional_context` entry carries 2664
  characters including the canary. Before the change: 2200 characters shown to the user.

**Hard lesson from the crash, not a kit feature:** never paste bulk data into context. A 5 MB
CSV pushed the window past its limit and killed the session. Process large data with code and
keep the summary.

## 4. The flow

```
Session start
   │
   ├─ HOOK  session-start-prime.sh   (SessionStart: startup|clear)
   │        restores the ledger whatever its age, flags a foreign one,
   │        injects a 696-character protocol. All of it suppressed.
   ▼
Session runs ──  THE MODEL writes to .claude/session-ledger.md on the five events
   │
   ├─ HOOK  ledger-lint.sh           (Stop, after every turn, silent)
   │        ledger over budget?            -> tells the model to trim
   │        enough work since checkpoint?  -> tells the model to RUN the checkpoint
   │
   ├─ HOOK  prompt-checkpoint.sh     (UserPromptSubmit, silent)
   │        "prepare for compaction", "compact vorbereiten" (English and German)
   │        -> tells the model to run the checkpoint, and names the SKILL.md path
   │           because by then the description may be gone from context
   ▼
/checkpoint ──  SKILL checkpoint (the model, one turn)
   │            sweeps the session, flushes the ledger, reconciles memory and
   │            knowledge docs IN PLACE, writes .claude/.checkpoint-ready
   ▼
/compact ──  HOOK precompact-guard.sh  (PreCompact: manual)
   │         marker fresh and ledger filled -> through
   │         no marker, hollow ledger, or stale after work -> BLOCK (the one visible message)
   ▼
Return path, three nets, one carrier:
   the FILE on disk + the re-read line in CLAUDE.md   <- reliable
   SessionStart compact -> reinject                   <- fires late, best-effort
   SessionStart startup -> prime                      <- next session, crash restart
```

Saving is reliable. Loading is best-effort plus the file. "On disk" becomes "in context" the
moment the model reads the file again, which is exactly what the re-read line guarantees.

## 5. Who does what

| Step | Done by | Type |
|---|---|---|
| restore the ledger, inject the protocol, flag a foreign ledger | `session-start-prime.sh` | Hook |
| hand the ledger back after `compact` (late) or `resume` | `session-start-reinject.sh` | Hook |
| **write the reasoning into the ledger** | **the model** | behaviour, not a call |
| keep the ledger inside its budget | `ledger-lint.sh` (Stop), silently | Hook + model |
| fire the checkpoint when work has piled up | `ledger-lint.sh` (Stop), **opt-in, off by default** | Hook + model |
| fire the checkpoint when you ask for it in words | `prompt-checkpoint.sh` (UserPromptSubmit) | Hook + model |
| **curate everything durable, set the marker** | `checkpoint` skill | Skill |
| refuse an unprepared `/compact` | `precompact-guard.sh` | Hook |
| allocate the restore budget by priority | `ledger_render.py` | shared by both restore hooks |
| inspect or repair a ledger | `session-ledger` skill | Skill (explicit) |

## 6. A day with it

You are building rate limiting. Two hours in, the ledger looks like this, and you never typed
any of it:

```markdown
## TASK
Rate limiting for the API, Redis based.

## NEXT
Middleware skeleton in api/middleware/ratelimit.py, sliding window via redis pipeline
(INCR + EXPIRE). Key-versus-IP axis still open.

## OPEN
- Limit per API key or per IP? Settles once we know whether anonymous requests are allowed.

## DECIDED
- Sliding over fixed window: fixed lets double load through at the window edge.

## VERIFIED
- Redis already runs as the session store [grep -r "redis" config/ -> cache.py:12]

## DROPPED
- In-memory counter per process: with N replicas the limit is N times too high.
- Off-the-shelf token bucket: three transitive dependencies for forty lines of logic.
```

The window fills. You run `/checkpoint`, or it already ran itself and told you so in one
sentence. It sweeps the session, resolves what is now settled, reconciles memory and the plan
file, and marks itself ready. You type `/compact`. The guardrail lets it through, and the two
hours of argument leave the window.

Afterwards the model does not propose the token bucket, because `DROPPED` says why it lost.
It does not re-ask fixed versus sliding, because `DECIDED` settled it. It does not ask where
to continue, because `NEXT` says so. You answer "anonymous requests are allowed" and the model
moves the open question into `DECIDED`, in place.

That is the whole product: the session got shorter, and nothing got dumber.

## 7. Questions people actually ask

**Do I have to do anything before `/compact`?** One step: `/checkpoint`. Often it has already
run itself. The guardrail refuses `/compact` without it, refuses a marker sitting over an
empty ledger, and refuses when work happened since a checkpoint that is now stale. What it
cannot check is whether the model wrote down everything it was thinking; a hook sees files,
not the conversation.

**Why is the preparation a skill and the enforcement a hook?** Because curation needs
judgement and a turn, which only the model has, and enforcement needs determinism, which only
a hook has. Splitting them along that line is the whole design.

**Does this burn tokens?** A little. The protocol costs about 170 tokens once per session, a
ledger line 20 to 40 tokens on an event, the restore 500 to 1500 once per compaction, and the
file on disk costs nothing. Against that: after a compaction without it, the model re-greps,
rebuilds decisions, and re-reads files, which is a multiple. Honest counter-view: a short
session that never compacts paid a small premium for insurance it did not claim.

**Is this a replacement for memory?** No, different horizons. Auto memory holds what is true
across sessions and is re-injected from disk after a compaction. The ledger holds what this
session decided and dies with it. The checkpoint is the bridge: it promotes durable lessons
into memory and **corrects or deletes** what this session made false, rather than appending a
second opinion next to the first.

**What if I run two sessions in the same directory?** They share one ledger file and
interleave. Use a separate worktree per session. The prime hook detects a foreign ledger and
says so, but detection is not prevention.

**Do I have to invoke the skill?** No. Hooks plus the model handle the normal case. Invoke
`session-ledger` explicitly only to inspect, repair, or hand over.

**How do I know it works here?** `bash tests/run.sh` proves the mechanics, 79 assertions, and
against the state before the release commit many of them go red, so the net can actually fail. Then run
one real `/compact` and confirm the reasoning comes back. A design that is right in principle
and unwired in practice preserves nothing.

## 8. The parts

| File | Type | Runs | Purpose |
|---|---|---|---|
| `skills/checkpoint/SKILL.md` | Skill | you (or the Stop hook, if opted in) | eight phases, from sweeping the session to writing the marker |
| `skills/session-ledger/SKILL.md` | Skill | explicit | the full ledger protocol, plus inspect and repair |
| `commands/checkpoint.md` | Command | `/checkpoint` | one-keystroke entry to the skill |
| `skills/brief/SKILL.md` | Skill | you, never on its own | the briefing: six blocks, reports only, writes nothing |
| `commands/brief.md` | Command | `/brief` | one-keystroke entry, takes an optional window |
| `hooks/session-start-prime.sh` | Hook | `startup`, `clear` | protocol plus restore, suppressed |
| `hooks/session-start-reinject.sh` | Hook | `compact`, `resume` | restore, suppressed, best-effort |
| `hooks/precompact-guard.sh` | Hook | `PreCompact` manual | the only visible mechanism, and the only blocking one |
| `hooks/ledger-lint.sh` | Hook | `Stop` | size check, silent; plus the opt-in checkpoint nudge |
| `hooks/ledger_render.py` | Library | called by both restore hooks | priority budgeting, character-safe clipping, completeness verdict |
| `hooks/hooks.json` | Config | plugin install | the same wiring via `${CLAUDE_PLUGIN_ROOT}` |
| `hooks/kit_integrity.py` | Library | called by the session start | reports an installation that no longer matches the manifest it shipped with |
| `.kit-manifest` | Config | generated by `sync.sh`, copied into the install | a digest per delivered file, so a foreign copy can tell it has fallen behind |
| `settings-snippet.json` | Config | standalone install | hook wiring plus the `env` block |
| `CLAUDE.example.md` | Config | appended to your CLAUDE.md | the two instruction blocks: aim the summary, and read the file when the canary is missing |
| `context-manifest.example.yaml` | Config | read by the checkpoint | names this project's durable stores |
| `tools/brief-digest.sh` | Tool | called by the briefing | facts from transcript, git and hook log, inside a character budget |
| `tools/effect-probe.sh` | Tool | manual | plants a fact only the ledger could carry, then checks whether it survived a real compaction |
| `tests/run.sh` | Tests | manual, CI | 79 assertions, no framework |

## 9. Why the renderer is its own file

`ledger_render.py` looks like over-engineering until you read what it prevents. A naive cut at
N bytes was measured against a real 18 KB ledger: `VERIFIED` started at byte 11677 and
`DROPPED` at 13839, so a 6000-byte cut delivered `TASK`, `DECIDED` and half of `OPEN`, and
dropped exactly the two sections that carry the point of the whole kit. Bloat sitting earlier
in the file actively pushed them out.

So the budget is allocated by priority, every canonical section gets a floor, non-canonical
sections are served last and cut first, clipping counts characters rather than bytes, and the
exit code reports whether the restore was complete. That last part is load-bearing: the canary
is emitted **only** on a complete restore, because the instruction file treats a present canary
as "no need to read the file". Emitting it unconditionally would mean every restore defect ends
the same way, with the reasoning gone, the fallback suppressed, and a success signal on screen.
Worse than having no kit at all.

## 10. Honest limits

- **The promise covers the compaction you trigger.** Every measurement behind this kit was
  taken against `/compact`: the restore hook fired on 27 of 30 manual boundaries, median
  1.7 s. Whether `SessionStart` with matcher `compact` fires at all on an *automatic*
  compaction is not measured here. Compact at a break in your work and this is moot. If you
  let the window fill instead, the hook path may not run, and you fall back to the re-read
  line in your `CLAUDE.md`: the ledger file is still on disk, and the missing canary is what
  sends the model to it. Degraded, not lost.
- **A standalone install dies if you start Claude Code from a subdirectory.**
  `.claude/settings.json` is read only from the directory you start in, with no walk up the
  tree (measured twice, independently; `CLAUDE.md` climbs the tree and
  `.claude/settings.local.json` applies repository wide, but `settings.json` does neither).
  So a standalone install at the repository root plus a session started in
  `packages/whatever` loses all four hooks, silently and with exit 0: no guardrail, no
  restore, no lint. The plugin path is immune, because a plugin lives outside the project it
  serves. Either start from the directory that holds `.claude/`, or install as a plugin.
- **It is not free, and the cost grows with your ledger.** The kit occupies context in every
  session before you type anything: the session-start injection, plus one description per
  skill and per command. The injection is the large half and it is bounded by
  `SESSION_LEDGER_MAX_CHARS` (default 6,000), so the ceiling is roughly that plus a few
  hundred characters of protocol, plus about 3,000 characters of descriptions. Measured in
  this repository at its own ceiling: 9,760 characters, near enough 2,400 tokens. That is
  the price of the reasoning coming back, and it is a real price. Lower the ledger budget if
  you would rather pay less and recover less; the two move together. Deliberately written as
  a property with its lever rather than as a single number, because a number here drifts on
  the next commit and this file has no way to notice.
- **A skill you never invoke still costs you.** Descriptions share a fixed listing budget,
  and once it overflows the harness drops the rarest ones. The name stays visible, so the
  skill looks installed and never fires. If you carry many skills, set the ones you rarely
  use to `name-only` or `off` in `.claude/settings.local.json` rather than raising the
  budget, which charges every session.
- It preserves what the model wrote down. Nothing recovers a decision that was never recorded.
- The checkpoint nudge measures transcript growth, a proxy for "work happened", not a gauge of
  how full the window is.
- Two sessions in one directory still corrupt one ledger. Worktrees, not hope.
- The harness contract above is version-dependent. Verify it with one live compaction before
  you rely on it anywhere new.
- **The briefing's facts are tested, its judgement is not.** An assertion plants a token into
  a synthetic transcript in a throwaway project and requires the digest to surface it, so
  discovery, the window, the budget and the honest degradation all go red when they break.
  Nothing checks whether the six blocks were filled *well*: whether the right thing landed
  under blocked, whether the next steps really are the cheapest order. That part is a model
  reading facts, and it is as good as any other reading.
- **`/brief` sees only what the transcript kept.** Work done in another directory, in a
  subagent whose transcript lives elsewhere, or before the transcripts you still have on
  disk, is invisible to it, and it will not know that it is missing.
- **The project state file is documented and unproven.** Every effect measurement in this kit
  plants into the ledger and reads what the restore delivers, so what is measured is the
  ledger. The project state is reached by a pointer in `PLAN` and by the archive
  instruction, never by injection, and no probe covers that path yet. Treat it as a
  discipline with a pointer, not as a mechanism with evidence.
