# Changelog

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
- **66 assertions** in `tests/run.sh`, green on macOS with bash 3.2 and on Ubuntu 24.04 with
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
