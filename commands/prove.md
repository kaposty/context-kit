---
description: Prove the kit actually rescues reasoning, instead of trusting that its hooks fired
---

Run the effect probe. It is the only check in this kit that measures **effect** rather than
mechanism: the test suite proves the parts behave, the hook log proves a hook ran, and
neither proves that a path this session abandoned stays abandoned after a compaction.

Work these steps and report honestly, including a red result.

First resolve the install once, so no step has to guess where the script lives:

```bash
for d in .claude/tools tools "$(ls -dt "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/*/context-kit/*/tools 2>/dev/null | head -1)"; do [ -f "$d/effect-probe.sh" ] && { P="$d/effect-probe.sh"; break; }; done
```

Every `$P` below is that path. If the loop leaves `$P` empty, the kit is not installed where
you are standing: say so and stop, rather than guessing a path.

1. **Plant.** Run `bash "$P" plant`. It writes one entry into `DROPPED` and one into
   `VERIFIED`, each carrying a random token that no model could produce by inference, and it
   plants them in the two sections a naive budget evicts first.

2. **Check the mechanical half.** Run `bash "$P" verify`. It renders the
   ledger at the smallest restore budget in the kit and reports whether the token survives.
   Red here means the budgeting is broken and there is no point continuing.

3. **Do the real thing.** Run `/checkpoint`, then tell the user to run `/compact`. You cannot
   run `/compact` yourself, so stop here and say so plainly.

4. **Ask, after the compaction.** Run `bash "$P" ask` and put its question
   to the user verbatim, or answer it yourself if the user asks you to: *what happened with
   approach `<token>`, and why?* Answering it from context without reading a file is the
   green case. Answering it only after reading `.claude/session-ledger.md` is the documented
   normal case, not a failure. Not knowing the token at all, or proposing the dropped
   approach as a fresh idea, is the kit failing its core claim.

5. **Grade.** Run `bash "$P" grade "<the answer>"` and report the verdict as
   it comes, with the token, the reason, and whether the dropped status came back.

## The wider measurement

The five steps above answer a yes/no: does anything arrive at all. They cannot answer **how
much** of a session's reasoning survives, which is the question a user actually has. For
that, the same tool has a second mode that plants one item in each of the three sections
that carry reasoning, a dropped path, a decision with its alternative, a verified fact with
its scale:

1. `bash "$P" recall-plant`
2. `/checkpoint`, then the user runs `/compact`
3. `bash "$P" recall-ask`, and put all three questions in **one** message
4. `bash "$P" recall-grade <answers-file> <transcript.jsonl>`

The grading reads the transcript, not the model's account of itself: an item is green only
if no file was opened in the turn that answered it. Asking a model whether it read a file
gets you its impression, not the fact. `RED` on any item is the only real failure; yellow
means the file carried what the hook did not.

Do not soften a red result and do not grade yourself generously. A probe that always passes
proves nothing, which is the exact failure this kit exists to argue against.
