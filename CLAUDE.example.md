<!-- Append these two blocks to the CLAUDE.md your project already has. Never replace that
     file: it carries your own rules, and this adds to them.
       cat path/to/context-kit/CLAUDE.example.md >> CLAUDE.md   -->

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
