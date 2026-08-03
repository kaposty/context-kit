---
description: Briefing on what happened since you last looked, so you stay in the loop over autonomous work
argument-hint: "[24h | 90m | 3d | a date]"
---

Run the brief skill now. Report only. Write no file, commit nothing, fix nothing.

1. **Facts.** Run exactly this, it resolves the install itself instead of making you guess:
   `T=$(ls -d .claude/tools tools "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/tools" 2>/dev/null | head -1); bash "$T/brief-digest.sh" $ARGUMENTS`
   With no argument the window is everything since the last
   run of this command, taken from the transcript. Repeat any `CUT FOR SPACE` or `INCOMPLETE`
   note in the briefing instead of hiding it.
2. **Reasons.** Read the session ledger, and the project state file its `PLAN` section names
   if there is one. Use them to explain the facts, do not copy them.
3. **Write six blocks in this order**, leaving out every block that has nothing in it:
   🟢 Progress, 🟡 In progress, 🔴 Blocked, 💡 Learned, ⚠️ Open problems, ➡️ Next.
   These exact words, translated but not replaced by synonyms: a heading that moves between
   runs cannot be scanned by habit.
   `➡️ Next` always appears and holds two to four steps in the cheapest useful order, each
   with a rough effort in the coarsest honest unit, minutes, an hour, a day.
   `🔴 Blocked` covers everything waiting on the user or on the outside world, and every line
   says which of the two, because only one of them is the reader's to act on now.
4. **Tag every line** `[measured]` or `[read]`, so evidence and impression never share a voice.
5. **Never let an identifier stand in for the change.** `#3021 merged` says only that a
   number moved; write what it does and put the identifier in parentheses if it is needed at
   all. Same for tickets, decision records, commits and branches.

Open with one line naming the window and its real span, and put anything that limits how far
the report can be trusted into that same line: a cut, an `INCOMPLETE`, a window the digest
widened or you set by hand. Never as a footnote at the end.

Every number carries what it is measured against, or it only looks like evidence: not
`0 of 16 chunks over 507 tokens` but `no chunk over the 512 limit, the largest is 507`.

Bullets, bold the load bearing word, plain language, around 25 lines. Write it in the
language the user writes in.
