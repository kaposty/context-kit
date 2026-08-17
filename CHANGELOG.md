# Changelog

## 1.2.0 (2026-08-17)

- **The kit wired twice fired twice, and nothing said so.** A plugin brings its own wiring in
  `hooks/hooks.json`, a project can wire the same scripts again in `.claude/settings.json`,
  and the harness honours both. Measured in this repository straight out of the hook log:
  four events carry an identical line twice, in the same second. The cost is not cosmetic,
  because the restore is placed in the context twice, so a 6076 byte block becomes 12152
  against a budget of 6000 and the budget that exists to protect the window is bypassed by a
  factor of two while every log line still reads healthy. The session-start hook now names
  the second wiring and asks for one spoken sentence. Reported rather than suppressed on
  purpose: suppressing means one instance deciding the other already ran, and a wrong
  decision there silently drops the restore, which is the loss this kit exists to prevent.
  Silent on a plain standalone install, on a plain plugin install, and inside the kit
  repository, where both wirings are deliberate (`SESSION_LEDGER_DOUBLE_WIRE_CHECK`).
- One more assertion, 80 in total, seen red against the version that still had the defect.

## 1.1.0 (2026-08-17)

Every defect below was found the same way: by installing the kit somewhere that is not this
repository, or by reading the logs of installations that had been running for weeks, and
measuring what actually happened. Most of them were invisible from inside a working
checkout, which is why the test suite grew a third install layout before anything else was
touched. Two entries correct a premise rather than a line of code, and they say so.

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
  `if (DISABLE_COMPACT) return false; if (truthy(DISABLE_AUTO_COMPACT)) return false; return
  autoCompactEnabled ?? true`. The recommendation was right, the reason was invented.
- **Nothing ever checked whether auto-compaction was actually off.** Every file here assumed
  it, the guardrail is wired to the `manual` matcher so an automatic compaction runs straight
  past it, and a plugin cannot ship an `env` block, so a plugin-only install had it wrong by
  default. Measured on the machine this kit was built on: the global settings carried no `env`
  block at all. The session-start hook now says so once, and it reads the VALUE rather than the
  presence, because the harness accepts only `1`, `true`, `yes` and `on`: `DISABLE_AUTO_COMPACT=0`
  and a typo both leave auto-compaction running while reading to a human like the opposite. It
  stays quiet when either of the other two doors (`DISABLE_COMPACT`, `autoCompactEnabled: false`)
  is already closed.
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
- **The ledger warning fired after the restore had already cut.** `ledger-lint.sh` stated its
  own rule as "MAX_CHARS must equal the smallest restore budget", which was written before the
  tolerance band existed. The warning does not fire at MAX_CHARS, it fires at MAX_CHARS plus
  the band, so 6000 and 15 percent left a ledger free to sit at 6899 characters against a 6000
  restore with nothing said. Measured over 217 restores in two dogfooded projects: 11 came back
  INCOMPLETE, and every one of them emitted between 6480 and 6593 bytes, inside that silent
  stretch. The rule is now `MAX_CHARS * (1 + TOLERANCE) <= smallest restore budget`, the
  default moves to 5200 (5980 with the band), and the suite derives both sides from the shipped
  files, the settings snippet included, instead of trusting the comment.
- **A stale partial copy under `.claude/` overrode a current plugin, and nothing could notice.**
  The commands probe `.claude/` first, so an old file there wins over the plugin instead of
  sitting beside it. The one mechanism against going stale is part of the installation, so a
  partial copy without `hooks/` has no checker at all, and the checker in the plugin cache
  verifies the cache against the manifest next to it and is therefore always clean. The
  session-start hook now compares the local copy against the installed plugin, which is the
  question a travelling manifest can never answer. Silent when they match, when the local
  version is adopted, and inside the kit repository itself, where the two differ by design.
- **The integrity report told you to overwrite in one direction.** A digest cannot tell an old
  file from an improved one. Measured in a real project whose installation was AHEAD of the
  kit: following that advice would have deleted the better files. It now says which way is not
  knowable and leaves the call to the reader.
- **A marker from one session waved another one through.** `.claude/.checkpoint-ready` was a
  single shared file, and the guardrail tests freshness, not authorship, so a session that had
  never checkpointed passed the moment any other session set the marker. Measured in a
  repository with four concurrent sessions: two of them reported the same marker timestamp to
  the second, because it was the same file. The marker is now derived from the session id the
  hook already receives, both session-start hooks state the exact path so the checkpoint can
  write it, the block text repeats it, and stale ones are reaped after seven days
  (`SESSION_LEDGER_MARKER_TTL_DAYS`). Without an id nothing can be attributed, so the shared
  marker still counts: a guardrail that locks a session out of its own window would be worse
  than the case it prevents.
  **The shared marker is a fallback, not a competitor**, and that distinction was learned the
  hard way within an hour of the first attempt: treating its presence as "some other session
  checkpointed" refused two sessions that had just run the checkpoint and been told they were
  safe to compact. Every session already in flight when the hooks are updated writes the
  shared path, as does every project with its own adopted checkpoint command. Blocking work
  that was done correctly is worse than the defect being fixed, because that is how a
  guardrail gets switched off. So it is judged by its own marker when one exists, by the
  shared one when none does, and refused only when neither is there. The rule then arrives on
  its own: updated checkpoints write only the per-session path, the empty shared marker is
  reaped with the rest after the TTL, and the fallback finds nothing to fall back to.
- **The size warning told a session to delete another session's reasoning.** It asks for content
  to be REMOVED, silently and without mentioning it, and it had no notion of who a ledger
  belongs to. The obvious fix is worse than the defect, and that is measured too: a version that
  simply skipped the check on a foreign stamp ran 566 times in a real project and skipped 491 of
  them, 86.7 percent, then stopped checking entirely for the last four days of its log, because
  a stamp is written once at seeding and refreshed by nobody. So the finding is still reported
  and only the instruction changes: settle ownership first, take the ledger over by updating the
  `_session:` line, then trim. The session-start hook hands over both the id and the archive
  command. Only the first token of the stamp is compared, because a human-readable suffix
  otherwise declares the rightful owner foreign, which is the same silent failure again.
- **The canary was forgeable.** It is a verdict the re-inject hook issues, and the project
  instruction keys off it: no canary means read the ledger from disk. A restored block is
  exactly the kind of text that gets pasted into a ledger, and once it was there the body
  carried a canary nobody had vouched for, so an INCOMPLETE restore read as a complete one and
  suppressed the fallback in the case that needs it. The body is now stripped of canary lines
  before it is wrapped, and a body that was nothing but canary lines is a no-op.
- **The assertion count check forced the changelog to falsify its own history**, demanding the
  current number in the 1.0.0 entry, which shipped with 66. Released sections are history and
  are no longer swept forward.
- **The citation file was a fourth copy of the version number that nothing checked.** Three
  files were compared against each other, and `CITATION.cff` was not one of them, so it was
  free to keep announcing the previous release from the box GitHub renders in the sidebar and
  every citation manager reads. Found while cutting this release: the version and the release
  date were both a version behind. The check now covers all four, and compares the date in
  `date-released` against the date in the changelog heading.
- Fourteen more assertions, 79 in total, each one seen red against the version that still carried
  the defect before it was kept. Two of the fourteen caught defects in the fix itself: BSD `tr`
  reads `' \t\n'` as three literal characters and deletes every `t` and `n` in the file, and
  BSD `sed` has no `\|` in a basic expression.

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
