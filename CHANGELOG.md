# Changelog

## Unreleased

Four defects, all found the same way: by installing the kit somewhere that is not this
repository and measuring what happened. Three of the four were invisible from inside a
working checkout, which is why the test suite grew a third install layout before anything
else was touched.

- **`/brief` and `/prove` could never find their scripts on a plugin install.** The shipped
  line resolved through `${CLAUDE_PLUGIN_ROOT}`, which is substituted for hook commands and
  is empty in a call the model makes, so the plugin branch never matched. It also probed for
  a DIRECTORY, so a project with its own `tools/`, or with half a copy under `.claude/tools/`,
  won the lookup and the call died with exit 127. Measured twice in a real project, four days
  apart. The line now walks candidates, tests for the FILE, and finds the cache through
  `CLAUDE_CONFIG_DIR`.
- **The test suite could not see that.** It checked for the substring `CLAUDE_PLUGIN_ROOT`
  and ran the line in two layouts that both live inside this checkout, so it pinned the defect
  in place instead of catching it. It now executes the line in four layouts, two of them the
  ones that were failing in the field.
- **The kit denied a settings key that exists.** Three places said `autoCompactEnabled` is not
  real and is silently ignored. The binary carries it in the schema and resolves
  `if (DISABLE_AUTO_COMPACT) return false; return autoCompactEnabled ?? true`. The
  recommendation was right, the reason was invented.
- **The standalone install overwrote without a word.** Five `cp -R` lines, over the most
  generic names in the namespace (`brief`, `checkpoint`, `prove`, `session-ledger`), with
  nothing about collisions, backups or removal anywhere in the docs. There is now a check that
  prints what would be overwritten, a real `jq` merge for `settings.json` that appends to your
  hook arrays instead of replacing them, an uninstall block, and a section on what the kit
  needs permission to write. Running those blocks in a test found two more: `cp -R hooks/.`
  carried the plugin wiring into standalone installs, and the mode glob touched scripts
  belonging to the project.
- **`DISABLE_AUTO_COMPACT` now states its price** where it is recommended. It removes the
  harness's own net for a full window, and the kit's replacement ships off.
- Two more assertions, 68 in total, each one seen red against the version that still carried
  the defect before it was kept.

## 1.0.0 (2026-08-03)

First public release. Every number below carries the command that produced it, because a
claim without its provenance is a belief.

- **Session ledger**: the carrier that survives a compaction. Written during the session,
  budgeted to 6000 characters, re-injected at the next session start as a suppressed result
  so it costs no screen.
- **`/checkpoint`**: the deliberate pass before `/compact`. It sweeps the session, flushes the
  ledger, syncs the plan file, and reconciles every durable store the project keeps (project
  state, memory, knowledge docs) so nothing durable is left stale.
- **Compaction guardrail** (`PreCompact`): refuses a `/compact` from an unprepared state, and
  equally refuses a fresh marker sitting over an empty ledger.
- **`/brief`**: a briefing for the person rather than the model, in six blocks, taken from the
  transcript, git and the hook log. It writes no file and changes nothing.
- **`/prove`**: the effect probe. It plants a token in the ledger sections a bad budget would
  evict first and grades, from the transcript, whether the reasoning came back without a file
  being opened.
- **Phrase trigger** (`UserPromptSubmit`): "compact vorbereiten", "prepare for compaction" and
  the like start the checkpoint. It lives in a hook rather than in a skill description on
  purpose, because descriptions are the one piece of startup content a compaction does not
  restore, and that is exactly when the phrase gets said.
- **Integrity check** plus a `.kit-manifest` that travels with an installation, so a copy that
  has fallen behind says so instead of looking healthy. It found both defects that actually
  happened here: a hook file missing entirely, and a set of files a generation old.
- **`sync.sh`**, which derives what to copy from the filesystem rather than from a typed list.
  The typed list was itself a defect: a newly added hook shipped, never reached the
  installation, and `--check` still reported "identical".
- **68 assertions** in `tests/run.sh`, green on macOS with bash 3.2 and on Ubuntu 24.04 with
  bash 5.2 and Python 3.12. Every one of them was seen red against the version that still had
  the defect. One is aimed at the suite itself: a checker that dies must go red, not silently
  green.

### Honest limits at this version

- Effect is evidenced, not proven: one green probe run on a short session, plus the runs
  behind the numbers in the README. Run `/prove` in your own project rather than trusting
  someone else's transcript.
- `.kit-manifest` answers "are my files the ones that shipped", never "is there a newer
  version". An installation is offline and has no delivery beside it to compare against.
- No Windows outside WSL, and `python3` is required for the silent, budgeted path. Without it
  the kit degrades out loud (`INCOMPLETE`) instead of pretending.
