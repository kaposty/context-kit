# Contributing

Issues, pull requests and ports to other harnesses are welcome. This file is short on
process and long on the one rule that actually matters here.

## The one hard rule

**A check that has never failed proves nothing.** Every assertion in `tests/run.sh` was seen
**red** against the version that still had the defect, and only then kept. That is not a
formality. Three separate times in this kit a green assertion turned out to be measuring
nothing: one changed only the delivery file, so the file comparison tripped before the real
check ran; one placed its fixture in the wrong order, so the old buggy code passed by
accident; one was tested against a small fixture while the shipped code ran five times over
the limit on a real repository.

So, for a change that fixes a defect:

1. Write the assertion first.
2. Run it against the broken state and **watch it fail**.
3. Fix the defect.
4. Run the suite again and watch it pass.

Say in the pull request that you did this. "Seen red against `<commit>`" is the sentence. A
pull request that changes behaviour without one will not be merged, however good the idea,
because it would quietly move the kit into a state nobody measured.

Bug reports are most useful as assertions: a small case where a hook does the wrong thing is
worth more than a description of it.

## Before you open a pull request

```bash
bash tests/run.sh            # 66 assertions, all green
bash sync.sh --check         # delivery and installation identical, exit 0
claude plugin validate .     # both manifests
```

CI runs the first two on Ubuntu and macOS. Both platforms matter for a real reason: `stat -f %m`
is mtime on BSD and mount point on GNU, and that difference shipped a silent defect once.
macOS still ships bash 3.2, so every delivered shell file has to parse under it.

## Where to make the change

The repository holds the same files twice, and the difference is mechanical:

- **The delivery**, at the top level (`hooks/`, `skills/`, `commands/`, `tools/`, the two
  manifests, the documents). **Changes happen here.**
- **The installation**, in `.claude/`, so this repository runs its own mechanism. Those are
  copies. Never edit them; run `bash sync.sh` and they are rewritten.

If a file exists at the top level under the same name, the copy in `.claude/` is a copy. If it
does not, it is a working file that belongs to this repository (`settings.json` and the like)
and is edited normally.

Three diverging copies were the most common source of defects here, which is why
reconciliation is a command and not a matter of discipline.

## House style

- English, project neutral, full words rather than abbreviations.
- Only the plain hyphen. No em dashes and no en dashes, in any file: the kit is meant to be
  read by people who did not build it, and it should paste cleanly everywhere.
- **Every verified fact carries the command that proved it.** A claim without provenance is a
  belief, and it will be asked for in review.
- **Every abandoned path carries its reason**, in the commit message or in the code comment.
  Otherwise it gets proposed again in three months.
- Comments explain why, not what. The what is in the line below them.

## What a change to a hook has to keep

- **Silence.** Hook output reaches the model as a suppressed JSON result and is never rendered
  to the user. If your change makes something visible in the transcript, it is a defect, not a
  feature. The only thing a user ever sees from this kit is the guardrail refusing an
  unprepared `/compact`.
- **Fail-open.** A hook that cannot do its job lets the session continue. The guardrail
  blocks only when it positively knows a checkpoint has not run; every error path exits 0.
- **Honest degradation.** Without `python3` the kit says `INCOMPLETE` and withholds the canary
  rather than delivering a partial restore that reads like a whole one.
- **The output cap.** Hook output is capped at 10000 characters by the harness. The restore
  budget exists because of it; do not spend it on content the harness already re-reads from
  disk, such as the instruction file or the memory index.

## Versioning

Semantic versioning, read against what an adopter experiences:

- **MAJOR**: a hook contract or a file location changes, so an existing installation has to be
  touched by hand.
- **MINOR**: a new capability or knob, with the suite extended to cover it.
- **PATCH**: a fix or a documentation change with no new claim.

The version is bumped in **both** `.claude-plugin/plugin.json` and
`.claude-plugin/marketplace.json` on every release, and the changelog gets its entry in the
same commit; plugin users may not receive an update otherwise. All three are checked against
each other by the suite, so a half-done bump goes red rather than shipping.

## Porting to another harness

The mechanisms are generic, the wiring is not: hook events, the transcript format, and the
namespacing of commands are Claude Code specifics. A port is welcome as its own directory
with its own copy of the suite, so the claims stay per harness rather than being asserted
across harnesses that nobody measured.

## Maintenance cadence

Solo maintainer, so issues are answered best effort. The harness moves quickly, so the two
install paths are re-probed on a fresh throwaway project before every release rather than
assumed to still work.
