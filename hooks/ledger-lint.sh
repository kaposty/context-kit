#!/usr/bin/env bash
# ledger-lint.sh: Session Ledger, the one guard that is actually mechanical.
#
# Wire to: Stop, matcher "*"
#
# WHY THIS EXISTS. The rest of this kit asks the model to keep the ledger small and to
# keep only the seven canonical sections. That instruction was measured against reality
# and lost: a real dogfooded ledger reached 177 lines and ~18 KB with 13 sections, six of them
# invented (a reading programme, a term dictionary, and four more of that kind). That is not a
# cosmetic problem. The re-inject budget is finite, so a bloated ledger silently stops
# protecting the session: the sections that carry the point (VERIFIED, DROPPED) are the
# ones pushed past the cut. Prose in a skill file did not prevent it. A check does.
#
# It warns, it does not block work, and the user never sees it. Exit 2 used to be the way
# to reach the model, but it surfaces as a hook error notice, so routine housekeeping was
# announced to the reader as a failure. A Stop hook can do better: a JSON result with
# `hookSpecificOutput.additionalContext` is delivered to the model as a system reminder,
# the turn ends normally, and nothing is rendered in the transcript. Exit code stays 0.
# To make sure this can never turn into a loop, it fires at most once per cooldown window
# (default 180 min) and never twice for the same ledger content.
#
# THE SECOND JOB, and the reason this hook is worth more than a size check: it decides when
# a checkpoint is overdue and tells the model to run it, silently. That closes the one gap
# the PreCompact guardrail cannot: a hook firing at compaction time reaches only the user
# (PreCompact output never goes to the model), so by then it is too late to prepare
# anything. Here, at the end of a turn, the model still has a turn to spend. The measure is
# transcript growth since the last checkpoint marker, which is a proxy for "work happened",
# the same axis the guardrail uses, and it is deliberately not sold as a context gauge.
#
# Silent when healthy: a ledger within limits and a recent checkpoint produce no output.
#
# THE NUMBER IS NOT FREE. MAX_CHARS must equal the SMALLEST restore body budget in this
# kit, which is the prime hook's RESTORE_BUDGET (6000); the re-inject body gets 6550. Any
# higher and this check goes green on a ledger that the restore then clips, which is a
# false assurance: exactly the failure mode the lint exists to catch. If you raise a
# restore budget, this number does not follow automatically. Raise it only after the
# smallest one moved.
#
# AND IT WARNS WITH A BAND, NOT ON THE EXACT NUMBER. Measured on a real session: a limit
# of 5000 with a warning on the very first character over produced character golf. The model
# rewrote "position 1 of 2289" as "position 1/2289" and stripped bold markup to land at
# 4999, burning turns to satisfy a counter while the content stayed the same. That is the
# opposite of curation. So the warning fires only past a tolerance band: a few percent
# over is normal breathing, and the restore handles it by priority anyway.
#
# Overrides: SESSION_LEDGER_MAX_LINES (150), SESSION_LEDGER_MAX_CHARS (6000),
#            SESSION_LEDGER_TOLERANCE_PCT (15),
#            SESSION_LEDGER_LINT_COOLDOWN_MIN (180), SESSION_LEDGER_LINT=off to disable.
#            SESSION_LEDGER_CHECKPOINT_TRIGGER=on to opt into the self-firing checkpoint
#            (off by default), SESSION_LEDGER_CHECKPOINT_TRIGGER_KB (400) for its threshold.
# Project-agnostic. Fail-open: any error exits 0.

set -uo pipefail

[ "${SESSION_LEDGER_LINT:-on}" = "off" ] && exit 0

LEDGER=".claude/session-ledger.md"
STATE=".claude/.ledger-lint-state"
MARKER=".claude/.checkpoint-ready"
TSTATE=".claude/.checkpoint-trigger-state"
MAX_LINES="${SESSION_LEDGER_MAX_LINES:-150}"
MAX_CHARS="${SESSION_LEDGER_MAX_CHARS:-6000}"   # = smallest restore budget, see header
TOLERANCE_PCT="${SESSION_LEDGER_TOLERANCE_PCT:-15}"   # band before warning, see header
# 180, not 60. At 60 a ledger that hovers near the limit produced six warnings in six
# hours in a real session. The warning is a nudge, not a deadline: the restore degrades
# gracefully and reports itself, so there is no reason to interrupt this often.
COOLDOWN_MIN="${SESSION_LEDGER_LINT_COOLDOWN_MIN:-180}"
CANON="TASK NEXT OPEN DECIDED VERIFIED DROPPED PLAN"

LOG=".claude/log/session-ledger-hook.log"
_log() { mkdir -p "$(dirname "$LOG")" 2>/dev/null || true; printf '%s ledger-lint %s\n' "$(date -Iseconds 2>/dev/null || date)" "$1" >>"$LOG" 2>/dev/null || true; }

STDIN_JSON="$(cat 2>/dev/null || true)"

# Both checks write into one message, delivered once at the end.
MESSAGE=""
_say() { MESSAGE="${MESSAGE}${1}
"; }

# Portable mtime, same trap as in the other hooks: `stat -f %m` is BSD mtime but GNU
# "--file-system", where it prints the mount point and exits 0. Only an all-digit answer
# counts; an empty answer means "unknown", never "zero".
_mtime() {
  _v="$(stat -f %m "$1" 2>/dev/null)"
  case "${_v:-}" in ''|*[!0-9]*) _v="$(stat -c %Y "$1" 2>/dev/null)" ;; esac
  case "${_v:-}" in ''|*[!0-9]*) _v="" ;; esac
  printf '%s' "${_v:-}"
}

# ---------------------------------------------------------------------------
# CHECK 2: is a checkpoint overdue? Runs first because it does not depend on the ledger.
#
# The baseline is the transcript size at the moment of the last checkpoint. It cannot be
# read from the marker (a touch carries no size), so it is recorded here and re-recorded
# whenever the marker changes, which is exactly when a checkpoint ran. Growth past the
# threshold means work happened since; that is the same axis the PreCompact guardrail uses,
# and it is a proxy for work, NOT a measure of how full the context window is.
_checkpoint_due() {
  # OFF by default, deliberately. A checkpoint that fires itself interrupts work nobody
  # asked to have interrupted, and the user who dogfooded this named it exactly that:
  # sensory overload. The guardrail already refuses an unprepared /compact, so nothing is
  # lost by waiting for the human to fire the pass. Turn it on with
  # SESSION_LEDGER_CHECKPOINT_TRIGGER=on if you would rather be nudged than blocked.
  [ "${SESSION_LEDGER_CHECKPOINT_TRIGGER:-off}" = "on" ] || return 0
  TRIGGER_KB="${SESSION_LEDGER_CHECKPOINT_TRIGGER_KB:-400}"
  case "$TRIGGER_KB" in ''|*[!0-9]*) return 0 ;; esac

  TRANSCRIPT="$(printf '%s' "$STDIN_JSON" \
    | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || return 0
  TSIZE="$(wc -c <"$TRANSCRIPT" 2>/dev/null | tr -d ' ')"
  case "${TSIZE:-}" in ''|*[!0-9]*) return 0 ;; esac

  MARKER_MTIME="$(_mtime "$MARKER")"
  MARKER_MTIME="${MARKER_MTIME:-0}"
  BASE_SIZE=""
  BASE_MARKER=""
  BASE_PATH=""
  if [ -f "$TSTATE" ]; then
    BASE_SIZE="$(sed -n '1p' "$TSTATE" 2>/dev/null)"
    BASE_MARKER="$(sed -n '2p' "$TSTATE" 2>/dev/null)"
    BASE_PATH="$(sed -n '3p' "$TSTATE" 2>/dev/null)"
  fi
  case "${BASE_SIZE:-}" in ''|*[!0-9]*) BASE_SIZE="" ;; esac

  # Reset the baseline and start counting from here when any of these holds:
  #   - there is no baseline yet;
  #   - a checkpoint has run since it was taken (the marker moved);
  #   - THE TRANSCRIPT IS A DIFFERENT FILE. Every session gets its own transcript, so a
  #     baseline carried over from the previous one is measured against a file that starts
  #     small again. Without this the second session of the day would never reach the
  #     threshold, and the nudge would quietly stop existing after its first use;
  #   - the file shrank below the baseline, which means the same thing by another route.
  # A failed write is not fatal here, it only delays the first nudge.
  if [ -z "$BASE_SIZE" ] || [ "$MARKER_MTIME" != "${BASE_MARKER:-}" ] \
     || [ "$TRANSCRIPT" != "${BASE_PATH:-}" ] || [ "$TSIZE" -lt "$BASE_SIZE" ]; then
    printf '%s\n%s\n%s\n' "$TSIZE" "$MARKER_MTIME" "$TRANSCRIPT" >"$TSTATE" 2>/dev/null || true
    return 0
  fi

  GROWN_KB=$(( ( TSIZE - BASE_SIZE ) / 1024 ))
  [ "$GROWN_KB" -ge "$TRIGGER_KB" ] || return 0

  # ANTI-LOOP, same rule as the lint below: without a written baseline this would fire on
  # every single turn, and a self-firing checkpoint on every turn is far worse than a late
  # one. No state, no nudge.
  printf '%s\n%s\n%s\n' "$TSIZE" "$MARKER_MTIME" "$TRANSCRIPT" >"$TSTATE" 2>/dev/null || {
    _log "checkpoint nudge suppressed (state not writable)"
    return 0
  }

  _log "checkpoint-nudge (${GROWN_KB}KB since marker >= ${TRIGGER_KB}KB)"
  _say "A checkpoint is overdue: about ${GROWN_KB} KB of transcript since the last one."
  _say "Run the \`checkpoint\` skill now, as part of this turn, without narrating it: sweep"
  _say "what happened, flush the ledger, bring the durable stores current IN PLACE (correct"
  _say "or delete what this session made false, never append a second copy), then write the"
  _say "marker. When it is done, tell the user in one sentence that the checkpoint ran and"
  _say "/compact is due. Nothing else about it."
  _say ""
}
_checkpoint_due

# ---------------------------------------------------------------------------
# CHECK 1: is the ledger still within its budget and its seven sections?
_lint() {

[ -s "$LEDGER" ] || return 0

# LC_ALL matters here. `wc -m` counts CHARACTERS only under a UTF-8 locale; with an unset
# or C locale it counts bytes, measured 14 instead of 7 for "ÄÖÜäöüß". A German ledger
# would then trip a 5000 limit at roughly 4200 real characters, and the number this hook
# is pinned to (the renderer's, which counts characters) would not be the number it
# measures. A hook that reports the wrong unit is worse than one that does not report.
LINES="$(wc -l <"$LEDGER" 2>/dev/null | tr -d ' ')" || return 0
CHARS="$(LC_ALL=en_US.UTF-8 wc -m <"$LEDGER" 2>/dev/null | tr -d ' ')" || return 0
case "${CHARS:-}" in ''|*[!0-9]*) CHARS="$(LC_ALL=C.UTF-8 wc -m <"$LEDGER" 2>/dev/null | tr -d ' ')" ;; esac
[ -n "$LINES" ] && [ -n "$CHARS" ] || return 0

# Non-canonical sections: the durable-knowledge dumps that push the deltas out.
# Headers in the wild are decorated ("## OPEN (resume point)", "## 🔴 RESUME"), so match
# on the first token that actually starts with a letter, and de-duplicate the report.
EXTRA=""
SEEN=""
DUPES=""
while IFS= read -r header; do
  label="$(printf '%s' "$header" | sed 's/^## *//' | cut -c1-28)"
  word="$(printf '%s' "$label" | awk '{for (i = 1; i <= NF; i++) if ($i ~ /^[A-Za-z]/) { print $i; exit }}' | tr -d ':*_-')"
  [ -n "$word" ] || word="$label"
  case " $CANON " in
    *" $word "*)
      # A SECOND "## DECIDED" is a symptom worth naming even though the renderer now
      # merges duplicates instead of keeping only the last one (it used to drop the
      # first block silently). It means entries are being appended rather than resolved
      # in place, which is how a working set turns into a changelog and then into bloat.
      case " $SEEN " in
        *" $word "*)
          case " $DUPES " in *" $word "*) : ;; *) DUPES="$DUPES $word" ;; esac ;;
        *) SEEN="$SEEN $word" ;;
      esac
      continue ;;
  esac
  case " $EXTRA " in
    *" $word "*) continue ;;   # already reported
  esac
  [ -n "$word" ] && EXTRA="$EXTRA $word"
done < <(grep -E '^## ' "$LEDGER" 2>/dev/null || true)

PROBLEMS=""
TRIP_LINES=$(( MAX_LINES + ( MAX_LINES * TOLERANCE_PCT / 100 ) ))
TRIP_CHARS=$(( MAX_CHARS + ( MAX_CHARS * TOLERANCE_PCT / 100 ) ))
[ "$LINES" -gt "$TRIP_LINES" ] && PROBLEMS="$PROBLEMS
- ${LINES} lines (target ${MAX_LINES})"
[ "$CHARS" -gt "$TRIP_CHARS" ] && PROBLEMS="$PROBLEMS
- ${CHARS} characters (restore budget ${MAX_CHARS}, warning past ${TRIP_CHARS})"
[ -n "$EXTRA" ] && PROBLEMS="$PROBLEMS
- non-canonical sections:${EXTRA} (durable knowledge belongs in the project state file,\n  the knowledge docs, or memory)"
[ -n "$DUPES" ] && PROBLEMS="$PROBLEMS
- duplicate section headers:${DUPES} (write into the existing section, do not append a second one)"

[ -n "$PROBLEMS" ] || { rm -f "$STATE" 2>/dev/null; return 0; }   # healthy: silent, reset

# Cooldown + content fingerprint, so this cannot nag every turn or loop on a Stop it
# just blocked. Same content as last warning, or inside the window -> stay quiet.
# The fingerprint covers WHICH problems, not just the size: two different ledgers of the
# same length used to look identical to this check, so a real new problem could be
# swallowed as "already warned".
FINGERPRINT="${LINES}:${CHARS}:${EXTRA}:${DUPES}"
NOW="$(date +%s 2>/dev/null || echo 0)"
if [ -f "$STATE" ]; then
  LAST_FP="$(sed -n '1p' "$STATE" 2>/dev/null)"
  LAST_TS="$(sed -n '2p' "$STATE" 2>/dev/null)"
  [ "$LAST_FP" = "$FINGERPRINT" ] && return 0
  if [ -n "$LAST_TS" ] && [ "$NOW" -gt 0 ]; then
    [ $(( ( NOW - LAST_TS ) / 60 )) -lt "$COOLDOWN_MIN" ] && return 0
  fi
fi
# THE ANTI-LOOP GUARANTEE HANGS ON THIS WRITE. If the state file cannot be written
# (read-only .claude, full disk, the path occupied by a directory, a uid mismatch in a
# shared checkout) then there is no cooldown record, and an exit 2 here fires on EVERY
# Stop, forever: measured 2 2 2 2 2 where a healthy run gives 2 0 0 0 0. The only way out
# was SESSION_LEDGER_LINT=off, while the header promised this "can never turn into a
# loop". So: no state, no exit 2. Warning once via stdout is worth less than a warning,
# but an unbreakable block on every turn is worth far less than nothing.
if ! printf '%s\n%s\n' "$FINGERPRINT" "$NOW" >"$STATE" 2>/dev/null; then
  _log "WARN suppressed (state not writable, would repeat forever)"
  return 0
fi

_log "WARN (${LINES} lines, ${CHARS} chars, extra:${EXTRA:-none})"

# SHORT ON PURPOSE. This text used to run 27 lines, and it was delivered as a hook error
# on top. The reasoning behind the rules stayed in this file, where it costs nothing; what
# goes to the model is the finding and the remedy. The tolerance band above is what keeps
# this from becoming a character-counting game, so the text no longer has to argue about it.
_say "Session ledger is over its limits:${PROBLEMS}"
_say ""
_say "Trim by REMOVING content, not by rewording. Move durable knowledge by REACH: past"
_say "this task to the project state file, past this project to memory. Collapse resolved"
_say "items into one line, drop re-derivable status, keep only: ${CANON}."
_say "Do it silently in this turn, and do not mention it."
_say ""
}
_lint

# ---------------------------------------------------------------------------
# One delivery for both checks. A Stop hook's stdout is never shown to the user, and
# `additionalContext` reaches the model as a system reminder without ending up in the
# transcript, so exit code 0 with JSON is both silent and effective. `suppressOutput` is
# belt and braces for the plain-text fallback path below.
[ -n "${MESSAGE//[[:space:]]/}" ] || exit 0
if command -v python3 >/dev/null 2>&1 \
   && printf '%s' "$MESSAGE" | python3 -c 'import json,sys
print(json.dumps({"suppressOutput": True,
                  "hookSpecificOutput": {"hookEventName": "Stop",
                                         "additionalContext": sys.stdin.read()}}))' 2>/dev/null; then
  exit 0
fi
# No python3: stdout on a Stop hook is not shown to the user either, but it does not reach
# the model as reliably. Better than dropping the finding, and still not an error notice.
printf '%s' "$MESSAGE"
exit 0
