#!/usr/bin/env bash
# session-start-prime.sh: Session Ledger, prime + restore at session start.
#
# Wire to: SessionStart, matcher "startup|clear"
#
# Runs once at session start. Measured behaviour (2026-07-23) drove this design:
# SessionStart fires reliably on startup, but a running auto-compaction does NOT
# fire SessionStart at all. So the reliable place to restore the ledger is here,
# on the next startup, not in the compact-matcher hook.
#
# Two jobs:
#   1. Keep the ledger and restore its content, then flag the one thing this hook cannot
#      decide by itself (see TASK IDENTITY below).
#   2. Inject the maintenance protocol once (cheap, per session, not per turn).
#
# NO CLOCK DECIDES ANYTHING HERE, and that is a correction, not an omission. This hook used
# to archive a ledger older than SESSION_LEDGER_STALE_HOURS (12) on the assumption that age
# means "previous task". Chats are timeless: you can pick a conversation up a week later and
# its context is exactly what it was. The rule punished that. Worse, it was destructive in a
# way that was invisible: opening a NEW session in the same directory archived the ledger of
# an OLD session that was still alive, so resuming that conversation later found its carrier
# gone. A rule that can delete a live session's reasoning to enforce a guess about tidiness
# is the wrong rule. Nothing is rotated by age now; archiving is a decision, taken on the
# first turn, with the whole picture available. Old ledgers cost a few kilobytes on disk,
# which is the cheapest thing in this entire kit.
#
# TASK IDENTITY. What actually matters is not age but ownership: is this ledger MINE. The
# ledger carries the id of the session that created it, so a mismatch is detectable. This
# hook cannot resolve it alone, because at SessionStart no user prompt exists yet and
# nothing here knows what the new task is. What it CAN do is say that the ledger belongs to
# a different session and hand over the exact command to archive it. The model sees the
# first user message and settles it in one step. Ambiguity is made explicit rather than
# resolved by guessing, and never by a timer.
#
# Project-agnostic. Reads hook JSON on stdin, writes to stdout, always exits 0:
# a failing hook must never block a session start.
#
# SILENT BY CONSTRUCTION. Plain stdout from a SessionStart hook is added to the context AND
# rendered in the transcript, so the whole protocol used to appear as a message at every
# session start. Maintenance the user has to read has become the work. The documented way
# out is a JSON result: `suppressOutput` keeps it out of the transcript, while
# `hookSpecificOutput.additionalContext` still delivers it to the model, wrapped in a system
# reminder instead of shown as a chat message. Same effect on the model, none on the reader.
# The plain-text path is kept as a fallback for a machine without python3, because a visible
# restore beats no restore.

set -uo pipefail

LEDGER=".claude/session-ledger.md"
ARCHIVE_DIR=".claude/session-ledger.archive"
# Cap on restored content. Lower than the re-inject hook budget on purpose: this hook
# also carries the maintenance protocol and possibly the task check, and all of it shares
# the same 10k output cap. Measured at 6000 the total reached ~8.4k, which
# is uncomfortably close to the point where the whole block is replaced by a pointer.
# This is the SMALLEST restore budget in the kit, so it is the one the ledger-lint limit
# (SESSION_LEDGER_MAX_CHARS) is pinned to. Lower it and that limit has to follow, or the
# lint reports green on a ledger that gets clipped here.
#
# Measured worst case at 6000 (all seven sections full, plus the protocol, plus the
# foreign-session block): 8595 characters against the 10000 cap, so ~1400 of headroom.
# 6500 leaves only 915, which is too thin to be safe. It was 5000 for half a day, and
# that was too tight in practice: a real session started shaving markup and rewording
# entries to land at 4999, which is character golf against a counter instead of curation.
# A budget that makes the model optimise the number rather than the content is set wrong.
RESTORE_BUDGET=6000
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
SESSION_ID="$(printf '%s' "$STDIN_JSON" \
  | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"

LOG=".claude/log/session-ledger-hook.log"
_log() { mkdir -p "$(dirname "$LOG")" 2>/dev/null || true; printf '%s prime source=%s %s\n' "$(date -Iseconds 2>/dev/null || date)" "${SOURCE:-?}" "$1" >>"$LOG" 2>/dev/null || true; }

# Everything this hook has to say is collected here and delivered once, at the end.
PAYLOAD=""
_add() { PAYLOAD="${PAYLOAD}${1}
"; }
# Deliver as a suppressed JSON result so nothing shows up in the transcript. json.dumps
# does the escaping, which is the reason this goes through python3 rather than through a
# hand-rolled sed: a quote or a backslash in a restored ledger line would otherwise emit
# broken JSON, and a hook that emits broken JSON delivers nothing at all.
_emit() {
  [ -n "${PAYLOAD//[[:space:]]/}" ] || return 0
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$PAYLOAD" | python3 -c 'import json,sys
print(json.dumps({"suppressOutput": True,
                  "hookSpecificOutput": {"hookEventName": "SessionStart",
                                         "additionalContext": sys.stdin.read()}}))' 2>/dev/null \
      && return 0
    _log "fallback (json output failed, plain text)"
  fi
  printf '%s' "$PAYLOAD"   # no python3: visible, but a visible restore beats none
}

case "${SOURCE:-startup}" in
  startup|clear) ;;
  *) _log "skip (source is not startup/clear)"; exit 0 ;;
esac

mkdir -p "$(dirname "$LEDGER")" 2>/dev/null || true

KEPT=0
FOREIGN=0        # kept ledger was written by a different session
RECENT_MIN=""    # how recently that other session touched it
# PORTABLE mtime, and the reason it needs its own function. `stat -f %m` is BSD/macOS
# "modification time", but on GNU/Linux `-f` means --file-system and `%m` is the mount
# point: it prints "/" and exits 0, so an `||` chain never reaches the -c form. The
# result was neither an error nor a number, and under `set -u` the arithmetic below then
# aborted the whole if-block: no restore, no rotate, not even a log line, exit 0. A kit
# that calls itself project-agnostic must not fail silently on the other mainstream
# platform. So: try both forms and accept only an all-digit answer.
_mtime() {
  _v="$(stat -f %m "$1" 2>/dev/null)"
  case "${_v:-}" in ''|*[!0-9]*) _v="$(stat -c %Y "$1" 2>/dev/null)" ;; esac
  case "${_v:-}" in ''|*[!0-9]*) _v="" ;; esac
  printf '%s' "${_v:-}"
}

if [ -s "$LEDGER" ]; then
  # ALWAYS keep. The only question left is whether it belongs to this session.
  KEPT=1
  OWNER="$(sed -n 's/^_session: \(.*\)_$/\1/p' "$LEDGER" 2>/dev/null | head -1)"
  if [ -n "$SESSION_ID" ] && [ -n "$OWNER" ] && [ "$OWNER" != "$SESSION_ID" ]; then
    FOREIGN=1
    MTIME="$(_mtime "$LEDGER")"
    NOW="$(date +%s 2>/dev/null || echo "")"
    case "${NOW:-}" in ''|*[!0-9]*) NOW="" ;; esac
    # Only used to phrase "touched N minutes ago", and to warn when another session may be
    # writing right now. Nothing is decided by it, so an unreadable clock costs a sentence,
    # never the ledger.
    if [ -n "$MTIME" ] && [ -n "$NOW" ]; then
      RECENT_MIN=$(( ( NOW - MTIME ) / 60 ))
    fi
  fi
  _log "keep+restore (foreign=${FOREIGN})"
else
  _log "FIRED (prime, no ledger yet)"
fi

# Seed a skeleton only when we do not have a kept ledger. The session stamp is what
# lets a later startup tell "same session reopened" from "different session, same dir".
if [ "$KEPT" -eq 0 ] && [ ! -s "$LEDGER" ]; then
  {
    echo "# Session Ledger"
    echo "_started: $(date -Iseconds 2>/dev/null || date)_"
    [ -n "$SESSION_ID" ] && echo "_session: ${SESSION_ID}_"
    echo
    # Order is restore-first: orientation (TASK, NEXT, OPEN) before reference
    # material (DECIDED, VERIFIED, DROPPED). After a compaction the first question
    # is always "where do I continue", so NEXT sits near the top, not in prose.
    for s in TASK NEXT OPEN DECIDED VERIFIED DROPPED PLAN; do echo "## $s"; echo; done
  } > "$LEDGER" 2>/dev/null || true
fi

# 1. Prime the model with the maintenance protocol (always).
#
# SHORT ON PURPOSE. This was ~1700 characters, paid at every session start, and it is the
# one part of the kit that is present without anyone asking for it. The detail belongs in
# the `session-ledger` skill, which loads on demand; what has to be here unprompted is the
# trigger list, the working-set rule and the silence rule. Everything else is retrievable,
# and a standing block that nobody rereads is exactly the always-on tax this kit exists to
# argue against.
#
# Built from _add lines rather than a heredoc: a heredoc inside a command substitution
# inside double quotes does not parse under bash 3.2, which is still the default shell on
# macOS, and the failure mode is a syntax error that takes the whole hook with it.
_add "# Session ledger active"
_add ""
_add "\`$LEDGER\` carries this session's reasoning across compaction: a summary keeps what"
_add "happened, not why. Append only on an event: a decision locked (DECIDED, with what it"
_add "beat), a fact verified (VERIFIED, with the command), a question opened (OPEN), a path"
_add "abandoned (DROPPED, with why), the task changed (TASK). NEXT rides along, never a write"
_add "of its own. Resolve in place, stay under ~150 lines, no secrets, no re-derivable"
_add "status. Older than this task lives in the project state file \`PLAN\` names: read it"
_add "before saying you have none. Silent housekeeping: never report it or mention this block."
_add "Detail: the \`session-ledger\` skill."

# 1b. Integrity, and the one place it can live. This is folded into the hook every install
# already wires, deliberately, instead of shipping a hook of its own: a separate hook would
# have to be added to every existing settings.json, and the installs that most need to hear
# they are stale are exactly the ones nobody goes back to re-wire. Silent when healthy, so
# the always-on cost of a correct install is one process and no output.
#
# This is also the one thing here that is meant to reach the HUMAN, which is why the report
# asks for a spoken line while everything else in this block asks for silence. The reason is
# not importance, it is who can act: a drifted install cannot be repaired by the model.
if [ "${SESSION_LEDGER_KIT_INTEGRITY:-on}" != "off" ] && command -v python3 >/dev/null 2>&1; then
  INTEGRITY_PY="${_SELF_DIR:-.claude/hooks}/kit_integrity.py"
  KIT_ROOT="$(dirname "${_SELF_DIR:-.claude/hooks}")"
  if [ -f "$INTEGRITY_PY" ]; then
    REPORT="$(python3 "$INTEGRITY_PY" "$KIT_ROOT" 2>/dev/null)"
    case $? in
      4) _add ""; _add "$REPORT"; _log "integrity drift reported" ;;
      3) _log "integrity unverifiable (no manifest at $KIT_ROOT)" ;;
    esac
  fi
fi

# 2. If we kept a fresh ledger, restore its content so the new session inherits the
#    reasoning. This is the reliable restore path, since SessionStart fires on startup
#    even when the compact-matcher hook did not (e.g. auto-compaction).
if [ "$KEPT" -eq 1 ]; then
  CONTENT=""
  RC=1
  if [ -f "$RENDER" ]; then
    CONTENT="$(python3 "$RENDER" "$LEDGER" "$RESTORE_BUDGET" 2>/dev/null)"
    RC=$?
  fi
  # Renderer contract: 0 = complete, 4 = partial (something canonical was clipped or
  # omitted), 3 = nothing to restore, anything else = unusable.
  COMPLETE=0
  [ "$RC" -eq 0 ] && COMPLETE=1
  if [ "$RC" -ne 0 ] && [ "$RC" -ne 3 ] && [ "$RC" -ne 4 ]; then
    # Degraded path (no python3, renderer missing). This is a BYTE cut, the very thing
    # the renderer exists to avoid, so it can split a multi-byte character and it drops
    # whatever sits past the cut. iconv removes a broken tail if it is available.
    CONTENT="$(head -c "$RESTORE_BUDGET" "$LEDGER" 2>/dev/null \
      | { iconv -c -f UTF-8 -t UTF-8 2>/dev/null || cat; })"
    COMPLETE=0
    _log "fallback (renderer unusable, raw cut)"
  fi
  if [ "$RC" -ne 3 ] && [ -n "${CONTENT// /}" ]; then
    _add ""
    _add "---"
    _add "## Ledger restored (session continues the prior task)"
    _add ""
    _add "$CONTENT"
    # THE CANARY IS A VERDICT, NOT A DECORATION. The project instruction file says: if
    # you do not see this line, read the ledger from disk. So emitting it whenever a hook
    # ran would suppress the fallback in exactly the cases that need it, and the session
    # would carry a success signal over a restore that lost its delta sections. It is
    # therefore emitted only when the renderer reported a COMPLETE restore; anything else
    # says the opposite and sends the reader to the file.
    _add ""
    if [ "$COMPLETE" -eq 1 ]; then
      _add "_Canary CTX-LEDGER-RESTORED: the reasoning above came from the session ledger, complete."
      _add "If a later turn lacks it and you do not see this canary, read \`$LEDGER\` before continuing._"
    else
      _add "_Restore INCOMPLETE (no canary): the block above is cut or degraded, so parts of the"
      _add "reasoning are missing. Read \`$LEDGER\` before you rely on it._"
    fi

    # The one thing this hook cannot decide: is this ledger mine, or does it belong to
    # another conversation in the same directory? Say so, and hand over the exact escape.
    if [ "$FOREIGN" -eq 1 ]; then
      _add ""
      RECENT_NOTE=""
      [ -n "$RECENT_MIN" ] && RECENT_NOTE=", last touched ${RECENT_MIN} minute(s) ago"
      _add "**Task check (first turn, before appending anything):** this ledger was written by a"
      _add "different session${RECENT_NOTE}. If the work you are asked to do"
      _add "now is NOT the task in \`## TASK\` above, first carry the durable half out of it,"
      _add "the decisions and the dropped paths, into the project state file this project"
      _add "keeps (\`## PLAN\` names it). Archiving ends the ledger's reach, so whatever is"
      _add "not carried over dies here. Then archive and start clean:"
      _add ""
      _add '```'
      _add "mkdir -p $ARCHIVE_DIR && mv $LEDGER $ARCHIVE_DIR/ledger-\$(date +%Y%m%d-%H%M%S).md"
      _add '```'
      _add ""
      _add "Never append new reasoning to the ledger of a different task: mixed ledgers restore"
      _add "the wrong decisions after a compaction. If it IS the same task, just continue."
      if [ -n "$RECENT_MIN" ] && [ "$RECENT_MIN" -lt 10 ]; then
        _add ""
        _add "_It was touched very recently, so another session may be running in this same"
        _add "directory. Two sessions sharing one ledger interleave and corrupt both: use a"
        _add "separate worktree per session._"
      fi
    fi
  fi
fi

_emit
exit 0
