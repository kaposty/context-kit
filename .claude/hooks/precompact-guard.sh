#!/usr/bin/env bash
# precompact-guard.sh: Checkpoint guardrail, the PreCompact half of the manual system.
#
# Wire to: PreCompact, matcher "manual"
#
# What it enforces: /compact only goes through after the `checkpoint` skill has run,
# because the checkpoint is what curates the durable context (flush ledger, sync plan,
# refresh the red thread, guard bloat) before the summary is taken. Without this, a
# manual /compact still compacts from an unprepared state, which is exactly what the
# checkpoint discipline is meant to prevent. The skill leaves a freshness marker on
# disk (`.claude/.checkpoint-ready`); this hook reads it and blocks /compact unless the
# marker is fresh.
#
# Contract used (Claude Code hooks):
#   exit 0            -> allow the compaction (marker fresh, or fail-open on any error)
#   exit 2 + stderr   -> BLOCK the compaction, stderr is shown to the user
#
# Design choices:
#   - FAIL-OPEN. A bug in this hook must never trap the user in a window they cannot
#     compact. Any error path (no stat, unreadable marker, weird stdin) -> exit 0.
#   - MANUAL only. Auto-compaction is meant to be OFF alongside this. If an "auto"
#     trigger ever reaches here, let it through: an auto-compaction is usually a
#     ceiling event where blocking would be worse than an unprepared summary.
#   - IDLE-AWARE. The axis is not wall-clock but "did work happen since the checkpoint".
#     If the ledger has not been written since the marker, /compact passes regardless of
#     age (prepare at night, compact in the morning). The time window only applies once
#     work happened since: SESSION_LEDGER_CHECKPOINT_MAX_AGE_MIN (default 480 = 8h).
#
# Project-agnostic. Reads hook JSON on stdin.

set -uo pipefail

MARKER=".claude/.checkpoint-ready"
LEDGER=".claude/session-ledger.md"
# WHERE THE RENDERER LIVES. Resolved next to this script first, with the classic install
# path as fallback. The hardcoded ".claude/hooks/..." was a silent bottleneck: install the
# hooks anywhere else, which is exactly what a plugin install does
# (${CLAUDE_PLUGIN_ROOT}/hooks/), and the renderer is simply not found. Nothing errors; the
# restore quietly drops to the byte-cut fallback that this whole file exists to avoid.
_SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
RENDER="${_SELF_DIR:-.claude/hooks}/ledger_render.py"
[ -f "$RENDER" ] || RENDER=".claude/hooks/ledger_render.py"
# (Here it is reused as a "is the ledger actually filled" probe.)
# The window only bites when work happened SINCE the checkpoint (see the idle check
# below). So it can be generous: it exists to nudge a re-checkpoint after a long working
# stretch, not to punish preparing the night before. Default 8h, override via env.
MAX_AGE_MIN="${SESSION_LEDGER_CHECKPOINT_MAX_AGE_MIN:-480}"

LOG=".claude/log/session-ledger-hook.log"
_log() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
  printf '%s precompact-guard %s\n' "$(date -Iseconds 2>/dev/null || date)" "$1" >>"$LOG" 2>/dev/null || true
}

# Fail-open helper: anything unexpected -> allow.
_allow() { _log "allow ($1)"; exit 0; }

STDIN_JSON="$(cat 2>/dev/null || true)"

# PreCompact stdin carries a "trigger" ("manual" | "auto"). Only guard manual ones.
TRIGGER="$(printf '%s' "$STDIN_JSON" \
  | sed -n 's/.*"trigger"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
if [ -n "$TRIGGER" ] && [ "$TRIGGER" != "manual" ]; then
  _allow "trigger=$TRIGGER, not manual"
fi

# No marker at all -> checkpoint never ran -> block.
if [ ! -e "$MARKER" ]; then
  _log "BLOCK (no marker)"
  cat >&2 <<MSG
Compaction stopped: no checkpoint has run in this session.

Run /checkpoint, then /compact. It brings the ledger, the project state and memory
current, so today's reasoning survives the summary instead of only what happened.

Nothing to preserve? echo nothing-to-preserve > $MARKER
MSG
  exit 2
fi

# THE ESCAPE HATCH HAS TO EXIST FOR REAL. The old block text offered `touch $MARKER`,
# and measured, that did not unblock anything: the content check below runs regardless of
# the marker, so a session with genuinely nothing worth preserving stayed blocked, three
# touches in a row, with no working way out named anywhere. With auto-compaction off
# there is no second route to a compaction either, so the actual exit a user finds is
# disabling the hook. A guard whose documented escape is a dead end trains people to
# remove the guard. The opt-out is now explicit and greppable in the marker file itself.
if grep -qi 'nothing-to-preserve' "$MARKER" 2>/dev/null; then
  _allow "opt-out in marker (nothing-to-preserve)"
fi

# Marker exists. The question is NOT "how old is it" (wall-clock is the wrong axis:
# prepare at night, compact in the morning, nothing changed, still valid). The question
# is "did anything happen SINCE the checkpoint that it did not capture". So:
#   1. idle since the checkpoint -> still valid, regardless of clock age -> allow;
#   2. work happened since -> then, and only then, apply a (generous) time window.
# Portable mtime. `stat -f %m` is BSD "mtime" but GNU "--file-system, mount point": on
# Linux it prints "/" and exits 0, so an `||` chain never reaches the -c form and the
# arithmetic below then dies with `AGE_MIN: unbound variable` under set -u, exit 1, which
# the harness reads as a hook failure rather than the promised fail-open. Only an
# all-digit answer is accepted.
_mtime() {
  _v="$(stat -f %m "$1" 2>/dev/null)"
  case "${_v:-}" in ''|*[!0-9]*) _v="$(stat -c %Y "$1" 2>/dev/null)" ;; esac
  case "${_v:-}" in ''|*[!0-9]*) _v="" ;; esac
  printf '%s' "${_v:-}"
}
MTIME="$(_mtime "$MARKER")"
[ -n "$MTIME" ] || _allow "stat failed"          # fail-open
NOW="$(date +%s 2>/dev/null || echo "")"
case "${NOW:-}" in ''|*[!0-9]*) NOW="" ;; esac
[ -n "$NOW" ] || _allow "date failed"            # fail-open
AGE_MIN=$(( ( NOW - MTIME ) / 60 ))

# Content check. The marker proves a checkpoint RAN, never that it captured anything, so
# before trusting a marker, make sure the ledger actually holds filled sections. A session
# that genuinely has nothing to preserve opts out above, by content, not by timestamp:
# `echo nothing-to-preserve > $MARKER`. The renderer exits 3 for
# "nothing but an untouched skeleton". This is the one hollow-checkpoint case that can be
# caught mechanically. Everything beyond it (did the model flush what it was thinking?)
# is not visible from a hook, and this guard does not pretend otherwise.
if [ -f "$RENDER" ] && [ -f "$LEDGER" ]; then
  python3 "$RENDER" "$LEDGER" 4000 >/dev/null 2>&1
  if [ $? -eq 3 ]; then
    _log "BLOCK (marker fresh, but ledger is an empty skeleton)"
    cat >&2 <<MSG
Compaction stopped: a checkpoint ran, but ${LEDGER} is still an empty skeleton, so
nothing would come back after the summary.

Run /checkpoint and write it down for real: each decision with what it beat, each fact
with the command that proved it, each dropped path with its reason, and one NEXT line.

Genuinely nothing to preserve? echo nothing-to-preserve > ${MARKER}
Touching the marker again does not help here, the empty ledger is the problem.
MSG
    exit 2
  fi
fi

# Idle check: has the ledger been written since the checkpoint? The checkpoint writes
# the ledger and then the marker, so right after it ledger_mtime <= marker_mtime. If the
# model captured new reasoning afterwards, ledger_mtime advances past the marker. A small
# grace absorbs near-simultaneous writes. No ledger -> skip to the window.
#
# Honest limit: this reads file mtime, which is a proxy for "new reasoning was captured",
# not for "new reasoning happened". Work that was never written down leaves the ledger
# untouched and therefore reads as idle. That case is invisible from here; the ledger-lint
# hook and the checkpoint skill are what push against it.
GRACE=30
if [ -f "$LEDGER" ]; then
  LMTIME="$(_mtime "$LEDGER")"          # same portability trap as above
  if [ -n "$LMTIME" ] && [ "$LMTIME" -le "$(( MTIME + GRACE ))" ]; then
    _log "allow (idle since checkpoint: ledger untouched, marker age ${AGE_MIN}min irrelevant)"
    exit 0
  fi
fi

# Work happened since the checkpoint. Now the time window matters: a little work is fine,
# but if the checkpoint is also old, its plan/memory reconciliation is out of date.
if [ "$AGE_MIN" -le "$MAX_AGE_MIN" ]; then
  _log "allow (work since checkpoint, but inside the window ${AGE_MIN}min <= ${MAX_AGE_MIN}min)"
  exit 0
fi

_log "BLOCK (work since checkpoint AND marker ${AGE_MIN}min > ${MAX_AGE_MIN}min)"
cat >&2 <<MSG
Compaction stopped: work happened after the last checkpoint, and that one is ${AGE_MIN} min
old (window ${MAX_AGE_MIN} min), so the newest reasoning is not in the ledger yet.

Run /checkpoint again, then /compact goes through.
MSG
exit 2
