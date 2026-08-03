---
description: Checkpoint, brings all durable context current so a following /compact runs clean
---

Run the checkpoint skill now, to bring ALL durable context current before compaction.
Nothing may be stale. Work the phases in order, each one is a quality gate:

1. Sweep the session since the last checkpoint: decisions taken, facts verified (with the
   command), questions opened/answered, paths dropped (with the reason), goal shifts.
2. Flush the session ledger (`.claude/session-ledger.md`): resolve items in place, keep it
   thin, no bulk data, no re-derivable status.
3. Sync the plan file (if any): mark finished endpoints, add new ones, one dated
   decision-log line per real change. Then keep it cheap to read: a plan is the most
   expensive file this pass touches, so finished endpoints move out to an archive file with
   their date and outcome, evidence lives below the spine or beside it, and only the spine
   (endpoints, status, open questions, decision log) stays in the part a checkpoint reads.
   Carried out means gone from the spine.
4. Refresh the situation (derived fresh, not stored): where we stand (one line), what is
   next (the single most valuable action), open risks/blockers.
   **One exception, and it matters: write the "what is next" line into the ledger's `NEXT`
   section.** It is a judgement, not a lookup, and after a compaction it is the first thing
   anyone reads. Spoken only in the hand-off it dies with the summary.
5. Guard against bloat: name any large files or pasted bulk data (CSVs, logs, dumps) in
   context and say "re-derive via script, do not carry".
6. Bring all durable context current (not only the ledger). The rule for this phase is
   RECONCILE, NEVER APPEND: a store is edited like a wrong sentence, not extended like a log.
   Three stores, separated by REACH. The test is one sentence: would this be useful in a
   different project?
   - project state (`.claude/project-state.md`, or the manifest's
     `durable_context.project_state`): what outlives this TASK. The ledger is archived when
     the task changes and its DECIDED and DROPPED go with it, so carry them here: where the
     work stands, the next step, the decision and what it beat, the dropped path and why.
   - memory: what outlives this PROJECT. A reusable technique, a platform trap, a correction
     to how the user works. One fact per entry, update an existing entry instead of
     duplicating, delete entries this session proved wrong, keep the memory index in sync.
     A fact that only matters here belongs in the project state, not in memory.
   - correct project knowledge docs this session changed, in place (do not append blindly).
   - test: is there a durable file this session made false or incomplete? If yes, the phase
     is not done.
7. Write the freshness marker: `mkdir -p .claude && touch .claude/.checkpoint-ready`. Only
   AFTER phases 1 through 6, never as the first step.
8. Give a short, explicit hand-off: what was persisted (ledger / project state / memory /
   N decisions), the "what is next" line verbatim, any bloat warning, then exactly:
   **"Checkpoint saved. Safe to run /compact now."**

Then STOP. Do NOT compact yourself (it is not technically possible anyway). The user then
types `/compact`, and the PreCompact guardrail lets it through because the marker is fresh.
