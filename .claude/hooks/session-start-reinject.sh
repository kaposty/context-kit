#!/usr/bin/env bash
# session-start-reinject.sh: Session Ledger, part 2 of 3 (compact best-effort + resume).
#
# Wire to: SessionStart, matcher "compact" (and "resume" for a resumed session, "fork" for
# a branched one). fork is not a third case, it is the same case under a new name: up to
# v2.1.213 a forked session reported source "resume" and was covered by that matcher, and
# from v2.1.214 the harness reports "fork" instead. Wiring that omits it loses the restore
# in every session made with /branch, /fork or --fork-session, silently and with exit 0.
#
# Emits the ledger after the compaction summary already exists. A pre-compaction hook
# cannot steer the summary, it can only block compaction or run a side-effect, so the
# ledger is written during the session and read back here. Two caveats measured live:
# on a manual /compact this fires but a few minutes LATE (it can lose the race with the
# next message), and on auto-compaction it does not fire at all (no SessionStart). So it
# is best-effort; the reliable carrier is the ledger FILE on disk plus a re-read line in
# the instruction file of the project. resume is the one path where it fires promptly.
#
# The budgeting rules live in ledger_render.py next to this file, shared with the prime
# hook: sections are allocated by priority so the delta sections (VERIFIED, DROPPED)
# cannot be evicted by earlier bloat, and clipping counts characters, not bytes.
#
# Project-agnostic. Always exits 0: a failed hook must never break a session.
#
# SILENT BY CONSTRUCTION, like the prime hook next to it: the restore is delivered as a
# JSON result with `suppressOutput` plus `hookSpecificOutput.additionalContext`, so it
# reaches the model without being rendered as a message. Plain stdout is the fallback for a
# machine without python3.

set -uo pipefail

LEDGER=".claude/session-ledger.md"
# Well under the 10k hook cap, leaving room for other hooks. Minus the fixed preamble
# this leaves 6550 for the body, which is MORE than the prime hook's 6000, so prime is
# the binding constraint the ledger-lint limit is pinned to, not this number.
BUDGET=7000
# WHERE THE RENDERER LIVES. Resolved next to this script first, with the classic install
# path as fallback. The hardcoded ".claude/hooks/..." was a silent bottleneck: install the
# hooks anywhere else, which is exactly what a plugin install does
# (${CLAUDE_PLUGIN_ROOT}/hooks/), and the renderer is simply not found. Nothing errors; the
# restore quietly drops to the byte-cut fallback that this whole file exists to avoid.
_SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
RENDER="${_SELF_DIR:-.claude/hooks}/ledger_render.py"
[ -f "$RENDER" ] || RENDER=".claude/hooks/ledger_render.py"

STDIN_JSON="$(cat 2>/dev/null || true)"

SOURCE="$(printf '%s' "$STDIN_JSON" \
  | sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
# Read for one reason only: the checkpoint marker is per session, so the session has to be
# told the filename it must write. This hook covers compact, resume and fork, which is
# exactly where an earlier statement of it has just been summarised away.
SESSION_ID="$(printf '%s' "$STDIN_JSON" \
  | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"

# Instrumentation: every call leaves a line, so it is provable whether the harness
# really invokes this hook after a real /compact (the transcript alone is ambiguous:
# the harness re-attaches open files anyway). Logging only, no context impact.
LOG=".claude/log/session-ledger-hook.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
_log() { printf '%s reinject source=%s %s\n' "$(date -Iseconds 2>/dev/null || date)" "${SOURCE:-?}" "$1" >>"$LOG" 2>/dev/null || true; }

case "${SOURCE:-compact}" in
  compact|resume|fork) ;;
  *) _log "skip (source is not compact/resume/fork)"; exit 0 ;;
esac

[ -s "$LEDGER" ] || { _log "no-op (no ledger, or empty)"; exit 0; }

# The preamble and canary printed around the body count against the same output cap,
# so the body gets the budget minus that fixed overhead.
BODY_BUDGET=$(( BUDGET - 450 ))

BODY=""
RC=1
if [ -f "$RENDER" ]; then
  BODY="$(python3 "$RENDER" "$LEDGER" "$BODY_BUDGET" 2>/dev/null)"
  RC=$?
fi

# Renderer contract: 0 = complete, 4 = partial (something canonical clipped or omitted),
# 3 = nothing but an untouched skeleton, anything else = unusable.
# Exit 3 must stay silent; falling back to a raw cut would re-inject the empty shell.
if [ "$RC" -eq 3 ]; then _log "no-op (only empty sections)"; exit 0; fi

COMPLETE=0
[ "$RC" -eq 0 ] && COMPLETE=1

# Any other failure (renderer missing, no python): degrade to a plain cut rather than
# losing the restore entirely. This is a BYTE cut and can split a multi-byte character,
# so iconv drops a broken tail where it exists, and the restore is never called complete.
if { [ "$RC" -ne 0 ] && [ "$RC" -ne 4 ]; } || [ -z "${BODY// /}" ]; then
  BODY="$(head -c "$BODY_BUDGET" "$LEDGER" 2>/dev/null \
    | { iconv -c -f UTF-8 -t UTF-8 2>/dev/null || cat; })"
  COMPLETE=0
  _log "fallback (renderer unusable, raw cut)"
fi

[ -n "${BODY// /}" ] || { _log "no-op (empty body)"; exit 0; }

SIZE=${#BODY}
_log "FIRED emit=${SIZE}b complete=${COMPLETE}"

PAYLOAD=""
_add() { PAYLOAD="${PAYLOAD}${1}
"; }

_add "# Session Ledger (restored after ${SOURCE:-compact})"
_add ""
_add "> Reasoning carried across the summary. Mechanical state (branch, open PRs,"
_add "> todos, build status) is deliberately NOT here: re-derive it if you need it."
_add ""
_add "$BODY"

# THE CANARY IS A VERDICT, NOT A DECORATION. The project instruction file keys off it:
# no canary means read the ledger from disk. Emitting it whenever this hook ran would
# suppress that fallback in precisely the cases that need it, so every restore defect
# would end in "reasoning gone, fallback disabled, success signal shown". It is emitted
# only for a restore the renderer reported COMPLETE.
_add ""
if [ "$COMPLETE" -eq 1 ]; then
  _add "_Canary CTX-LEDGER-RESTORED: the reasoning above came from the session ledger, complete."
  _add "If a later turn lacks it and you do not see this canary, read \`$LEDGER\` before continuing._"
else
  _add "_Restore INCOMPLETE (no canary): the block above is cut or degraded, so parts of the"
  _add "reasoning are missing. Read \`$LEDGER\` before you rely on it._"
fi

[ -n "$SESSION_ID" ] && { _add ""; _add "Checkpoint marker for this session: \`.claude/.checkpoint-ready.${SESSION_ID}\`"; }

# Suppressed JSON result, same contract as the prime hook: the model gets the restore, the
# transcript stays clean. json.dumps handles the escaping, which a restored ledger line
# full of quotes and backslashes genuinely needs.
if command -v python3 >/dev/null 2>&1 \
   && printf '%s' "$PAYLOAD" | python3 -c 'import json,sys
print(json.dumps({"suppressOutput": True,
                  "hookSpecificOutput": {"hookEventName": "SessionStart",
                                         "additionalContext": sys.stdin.read()}}))' 2>/dev/null; then
  exit 0
fi
printf '%s' "$PAYLOAD"   # no python3: visible, but a visible restore beats none
exit 0
