# Changelog

## 1.6.0 (2026-08-19)

- **The ownership verdict was missing from the door that gets used all day.** All of the
  attribution logic lived in the prime hook, which runs on `startup` and `clear`, while the
  restore hook covers `compact`, `resume` and `fork` and carried none of it. Reported from
  the field and then found in this repository's own log, two hooks in the same second: prime
  logging `foreign=1` and the restore hook handing the very same ledger to the model with
  nothing said. Another session's TASK stood in that context twice with no sign it was not
  its own. A restore on those three sources now names the owner, before the body rather than
  after it, and the log carries `foreign=` so the decision is visible without reading the
  payload. It still restores: a session that has taken the work over needs the reasoning, and
  refusing would turn an attribution problem into a lost-context problem. Foreign only, and
  that is a decision rather than an omission, because an unsigned ledger names nobody to be
  wrong about and a warning there would fire on every resume of every ledger nobody stamped.

- **A plugin user who had ever updated was running the tools they first installed.** The
  documented line for locating `brief-digest.sh` and `effect-probe.sh` globbed the plugin
  cache and stopped at the first hit, and a shell glob sorts lexically, so `1.0.0` beat
  `1.5.1`. The cache keeps every version ever installed: measured with eight of them in one
  cache, `/brief` ran the digest from the first release and every fix since had never reached
  that reader, silently, with no error to notice. The line now takes the newest by write time.
  Found while repairing a shell alias that had the same glob and had turned into a multiple
  read, which was the visible half of the same mistake.

- **In a working copy shared by several sessions, quoted lines said nothing about where they
  came from.** The digest resolves transcripts by working directory, so it reads all sessions
  in that directory, which is right for a briefing about a person's day. What was wrong is
  that messages the user had sent to OTHER sessions were listed together with their own,
  unmarked, and the budget then cut the blocks that carried the difference. Lines now carry a
  short session mark, and only when the window actually holds more than one session, so the
  ordinary single-session case pays nothing for a distinction it does not have.

## 1.5.1 (2026-08-18)

- **Following the documentation could wire the kit twice.** The two install paths are written
  as alternatives and nothing said they are exclusive, so somebody who already has the plugin,
  here or at user scope, and then runs the standalone block ends up with both. Measured by
  following this page: every hook fires twice and the restore is placed in the context twice,
  against a budget meant to cap it once. It is not an error, both copies exit 0, and that is
  what makes it expensive, because nothing looks wrong. The kit has reported the doubling at
  session start since 1.2.0, and a report after the fact is second best; the recipe now rules
  it out before it copies, with the one command that shows an existing install.

## 1.5.0 (2026-08-18)

- **The carrier path from 1.4.0 was unreachable for the case that motivated it.** Sessions
  started from a desktop or IDE surface get no environment of their own: counted in a real
  session record, 24 fields, none of them env, args or command. So the only place a user could
  set `SESSION_LEDGER_FILE` was the `env` block in settings.json, which is per DIRECTORY and
  therefore puts every session back on one file, which is precisely what the variable exists to
  avoid. It shipped with an instruction ("in the shell that starts the session") that a whole
  class of users cannot follow, and nothing said so. `SESSION_LEDGER_FILE=auto` moves the
  resolution to where the knowledge already is: the hooks receive the session id, so one
  setting in settings.json gives every session its own `.claude/session-ledger.<id>.md`,
  including sessions nobody can hand an environment to. Fail-safe, and that branch is asserted
  rather than assumed: a missing id, or one that could escape the directory, falls back to the
  shared default instead of building a path out of it. Opt-in, because it also ends continuity
  between sessions in one directory, which is the point in parallel and a loss in series.
  Found by the same measurement that found the lint judging one carrier and naming another,
  because its session id was parsed after the size had already been taken.

## 1.4.0 (2026-08-18)

- **A directory carried exactly one ledger, and settling ownership turned that into a dead
  end.** The path was hardcoded in all four hooks and had no variable among fifteen. Measured
  in a working copy running five concurrent sessions: once the owner had stamped the ledger,
  the other four had nowhere at all to put their reasoning, and every route the ownership
  block offers was closed to them, since claiming it would be theft and archiving it would
  delete somebody else's work. `SESSION_LEDGER_FILE` gives each session its own carrier. All
  four hooks read it, unset behaves exactly as before, and a separate git worktree per session
  remains the recommendation, because it separates everything rather than only the carrier.
  The size warning names the file when it is not the default, since with several carriers in
  one directory "the session ledger" identifies nothing.

- **Two checks stood down without saying so.** The shadow check and the double-wiring check
  both need a second reference point on the machine, so both are gated on where the hook runs
  from and stand down when it is the project's own copy under `.claude/hooks`, which is the
  majority shape. That is correct, and it was invisible. Measured on 2026-08-18: two sessions
  compared notes on a field run, saw four checks stay quiet, and both got the tally wrong in
  opposite directions, because silence that means "passed" and silence that means "could not
  apply here" look identical in a log. They are logged as their own result now. The same run
  showed the integrity check is self-referential in a copied tree, verifying the copy against
  the manifest beside it, which is the limit the checker already states in its own header.
- The `_session:` line in the unsigned-ledger block ran to 110 characters against the ~88 the
  surrounding paragraph is set to, because the id was inlined into a line that was already
  near the limit. It sits on its own indented line now. Cosmetic, found in a field run of
  1.3.0, and held back from a release of its own rather than spending a tag and five
  installation updates on a line break.

## 1.3.1 (2026-08-18)

- **Updating an installation left mess in the adopter's repository, and the kit caused it.**
  An update overwrites files somebody may have adopted on purpose, so whoever runs one keeps a
  backup first, and the only sensible place for it is beside what it backs up, under
  `.claude/`. Nothing covered that path. Measured in a real project: 18 files from two backup
  directories tracked in git, on top of three markers and the hook log, because `.gitignore`
  said nothing about `.claude/` at all. Both ignore lists now cover
  `.claude/.kit-backup-*/`, and the README documents the update itself, with the backup
  under the name the ignore list knows and a pointer at `.kit-adopted` for what to keep.
  The derived check could not have caught this and that is not a flaw in it: it reads the
  paths the SCRIPTS write, and no script writes a backup. A procedure in the README does, so
  the new assertion derives from the README, the same rule the phrase-trigger check follows.
  86 assertions.

## 1.3.0 (2026-08-18)

Seven defects, none of them found here. Two sessions running the kit in other projects
measured their own installation and reported what it did, which is the only way most of these
could have surfaced: every one of them looks correct from inside a working checkout.

- **A ledger nobody signed was silently adopted as your own.** The owner check compares the
  `_session:` stamp against the running session, and a ledger with no stamp at all skipped the
  comparison entirely, so "cannot attribute" came out as "mine". Measured in a project with
  five concurrent sessions: one was handed another session's decisions, open questions and
  measurements as its own, with `foreign=0` in the log throughout, and came within a step of
  appending to them. Every ledger seeded before the stamp existed is in that state, as is every
  one written by an adopted checkpoint that does not know about it. There is now a third
  verdict between mine and foreign: unsigned ledgers say so, ask the session to compare
  `## TASK` against its actual task, and offer both the claim and the archive. The costs are
  not symmetric, which is what decided it: a wrong "foreign" costs a paragraph of context, a
  wrong "mine" invites a session to trim or archive reasoning that has no second copy.
- **The compaction guardrail waved a session through on another session's marker.** The shared
  marker is a fallback for sessions that started before the per-session one existed, and the
  reasoning shipped with it was that the fallback would expire on its own once checkpoints
  wrote only the new path. It does not: the checkpoint still offers the shared path whenever
  the session id cannot be found, so shared markers keep being produced and the migration never
  ends. Measured: a compaction allowed on a marker written one minute earlier by a different
  session, with two more from dead sessions beside it. The fallback stays, because locking a
  session out of its own window is still worse, and it becomes attributable instead: a
  checkpoint that falls back writes its id into the file, and a marker naming somebody else is
  refused. An unsigned shared marker still passes, which is the pre-migration case.
- **The double-wiring warning asserted two things it had never measured**, one release after
  it was added. It said the restore was in the context twice and that the log showed two
  identical lines per event. Both were checked in the field and both were false there, because
  the settings file it had found the wiring in was invalid JSON and the harness had discarded
  it, so only the plugin was firing. It now reports what it can see, the wirings, and says in
  the same breath that firings are a different question and the log is where they are.
- **A settings file the harness threw away is not a wiring, and now it is reported.** One
  trailing comma made `.claude/settings.json` invalid, and the harness discarded the whole
  file: `env`, `permissions.allow` and `permissions.deny` inert for 19 hours, including a rule
  protecting `.env` and one blocking `rm -rf`, with nothing anywhere saying a word. Not a
  defect in this kit, and reported anyway, because the kit reads those files already and is
  the only thing in the room that can see the hole (`SESSION_LEDGER_SETTINGS_CHECK`).
- **The wiring report said "twice" and counted files, not wirings.** A settings file can wire
  the same script more than once inside itself: measured, `session-start-reinject.sh` twice
  under SessionStart, so with the plugin that hook fired three times while the text said twice.
  It counts now. The first version of the count used `grep -c`, which counts matching LINES,
  and a settings file written by a tool is one line, so three wirings counted as one. That was
  caught by the assertion written for the fix.
- **The wiring report recommended the lossy direction first.** It offered "drop the settings
  entries and keep the plugin" and "disable the plugin and keep the local copy" as equals. In
  the project that reported it the LOCAL copies were the newer ones, four hooks of five,
  deliberately adopted and documented, and a session followed the order the text named first
  and had to retract it after diffing. This is the same mistake the integrity report already
  fixed once: a digest cannot tell an old file from an improved one, so it must not point at a
  direction. The report now says which way is not knowable and names `.kit-adopted`.
- **`brief-digest.sh` reported stale git facts in the voice of measurements.** On a checkout 32
  commits behind its upstream it printed "no commits in window" while 24 commits sat on the
  branch inside that window, and called a carrier file unsaved that had been written an hour
  earlier. A briefing repeating that tells somebody they wrote nothing all day. The tree is
  deliberately NOT swapped for the upstream, since the local checkout is what the session
  worked in; it is declared in the header instead, in the same voice as `INCOMPLETE` and
  `CUT FOR SPACE`, and silent on a tree that is current or has no upstream.
- Five more assertions, 85 in total, each seen red against the version that still carried the
  defect. Four of the existing ones had to be re-anchored: they matched the wording of the
  warning rather than the log line, so improving a sentence turned them red without any
  behaviour changing, which is the substring trap this suite already has a rule about.

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
