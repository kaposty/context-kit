#!/usr/bin/env bash
# tests/run.sh: the regression net for the only real mechanics in this kit.
#
# WHY IT EXISTS. Every defect this file locks down was found by an adversarial review on
# 2026-07-25, in code that had shipped and looked healthy. Four of them lost content
# silently, and one of them (duplicate section headers) needed no budget pressure at all:
# a 252-character ledger with a 5000-character budget already dropped a verified fact and
# an abandoned path with no note anywhere. A five-line test would have caught it the day
# it was written. The kit's own lesson, that a prose instruction is not a mechanism,
# applies to the kit itself: this file is that mechanism.
#
# Run:  bash tests/run.sh          (from the kit root)
# Exit: 0 all green, 1 on the first failing assertion class (all are reported).
#
# No framework on purpose: the kit ships shell hooks and one python file, so the test
# harness stays shell and python too. Nothing here touches a real project.

set -uo pipefail

KIT="$(cd "$(dirname "$0")/.." && pwd)"
RENDER="$KIT/hooks/ledger_render.py"
TMP="$(mktemp -d 2>/dev/null || echo /tmp/ctxkit-tests-$$)"
mkdir -p "$TMP"
PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }

# ---------------------------------------------------------------------------
echo "renderer: budget is a post-condition, not an intention"
# Regression: allocation charged headers and bodies while emitting separators, two
# footnotes and per-section notes on top. Measured overshoot on 4001 of 4001 budgets,
# up to +491 characters, which is how a block crosses the 10000 cap and silently
# becomes a file pointer instead of a restore.
RES="$(python3 - "$RENDER" "$TMP" <<'PY'
import subprocess, sys, os
render, tmp = sys.argv[1], sys.argv[2]
secs = [("TASK", "Goal.\n"), ("NEXT", "Step.\n"),
        ("OPEN", "- Question\n" * 20), ("DECIDED", "- Decision\n" * 20),
        ("VERIFIED", "- Fact via cmd\n" * 20), ("DROPPED", "- Path dropped\n" * 20),
        ("PLAN", "- Step\n" * 5),
        ("METHOD", "- bloat\n" * 40), ("DICTIONARY", "- bloat\n" * 40)]
path = os.path.join(tmp, "budget.md")
open(path, "w", encoding="utf-8").write(
    "# Session Ledger\n\n" + "".join("## %s\n%s\n" % (n, b) for n, b in secs))
over = 0
for b in range(60, 6001, 7):
    n = len(subprocess.run([sys.executable, render, path, str(b)],
                           capture_output=True, text=True).stdout)
    if n > b:
        over += 1
print(over)
PY
)"
[ "$RES" = "0" ] && ok "no budget overshoot across 850 budgets" \
                 || bad "budget overshoot" "$RES budgets exceeded their cap"

# ---------------------------------------------------------------------------
echo "renderer: duplicate canonical headers merge instead of overwriting"
# Regression: by_name was a dict comprehension, so a second "## VERIFIED" replaced the
# first. Silent, no note, and unrelated to budget pressure.
cat > "$TMP/dup.md" <<'EOF'
# Session Ledger

## VERIFIED
- FACT-ONE proven

## DROPPED
- PATH-ONE dropped

## VERIFIED
- FACT-TWO proven

## DROPPED
- PATH-TWO dropped
EOF
OUT="$(python3 "$RENDER" "$TMP/dup.md" 5000)"
MISS=""
for token in FACT-ONE FACT-TWO PATH-ONE PATH-TWO; do
  printf '%s' "$OUT" | grep -q -- "$token" || MISS="$MISS $token"
done
[ -z "$MISS" ] && ok "all four entries survive a duplicated header" \
               || bad "duplicate headers lose content" "missing:$MISS"

# ---------------------------------------------------------------------------
echo "renderer: the floor is a floor for everyone, not for whoever came first"
# Regression: pass 1 gave the full 320-character floor to the first section in PRIORITY
# and left the rest with nothing, so at budget 500 to 700 OPEN, DECIDED and PLAN were
# evicted entirely, reintroducing the very failure this file was written to stop.
SURV="$(python3 "$RENDER" "$TMP/budget.md" 700 | grep -cE '^## ')"
[ "${SURV:-0}" -ge 7 ] && ok "all 7 canonical sections present at a 700 budget" \
                       || bad "floor not honoured" "only $SURV sections at budget 700"

# ---------------------------------------------------------------------------
echo "renderer: exit code reports completeness (this is what gates the canary)"
COMPLETE_RC=0; PARTIAL_RC=0
python3 "$RENDER" "$TMP/dup.md" 5000 >/dev/null 2>&1; COMPLETE_RC=$?
python3 "$RENDER" "$TMP/budget.md" 700 >/dev/null 2>&1; PARTIAL_RC=$?
[ "$COMPLETE_RC" -eq 0 ] && ok "complete restore exits 0" \
                         || bad "complete restore exit code" "got $COMPLETE_RC, want 0"
[ "$PARTIAL_RC" -eq 4 ] && ok "clipped restore exits 4" \
                        || bad "partial restore exit code" "got $PARTIAL_RC, want 4"

# ---------------------------------------------------------------------------
echo "renderer: an empty or impossible restore stays silent"
# Regression: budget 0 returned exit 0 with 497 characters of pure footnote, so the
# caller injected noise and, worse, printed a success canary over it.
printf '# Session Ledger\n\n## TASK\n\n## NEXT\n\n' > "$TMP/skel.md"
python3 "$RENDER" "$TMP/skel.md" 5000 >/dev/null 2>&1
[ $? -eq 3 ] && ok "untouched skeleton exits 3" || bad "skeleton exit code" "want 3"
python3 "$RENDER" "$TMP/budget.md" 0 >/dev/null 2>&1
[ $? -eq 3 ] && ok "budget 0 exits 3" || bad "budget 0 exit code" "want 3"
python3 "$RENDER" "$TMP/budget.md" -500 >/dev/null 2>&1
[ $? -eq 3 ] && ok "negative budget exits 3" || bad "negative budget exit code" "want 3"

# ---------------------------------------------------------------------------
echo "renderer: UTF-8 seams stay valid (characters, never bytes)"
python3 - "$RENDER" "$TMP" <<'PY'
import subprocess, sys, os
render, tmp = sys.argv[1], sys.argv[2]
path = os.path.join(tmp, "utf8.md")
open(path, "w", encoding="utf-8").write(
    "# L\n\n## TASK\n" + "ÄÖÜäöüß🔴🟢 " * 200 +
    "\n\n## DROPPED\n" + "Path ü dropped 🚨 " * 200 + "\n")
bad = 0
for b in range(60, 4001, 11):
    raw = subprocess.run([sys.executable, render, path, str(b)], capture_output=True).stdout
    try:
        if "�" in raw.decode("utf-8"):
            bad += 1
    except UnicodeDecodeError:
        bad += 1
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] && ok "no mojibake at any cut point" || bad "UTF-8 seam" "broken characters found"

# ---------------------------------------------------------------------------
echo "renderer: a fenced code block is content, not a section header"
# Regression: a VERIFIED line quoting markdown split its own section, the tail was
# re-sorted to the end as a phantom non-canonical section, and the lint then reported a
# section that did not exist and could only be "fixed" by destroying real content.
printf '# L\n\n## VERIFIED\n- belegt via:\n```\n## Ledger restored\n```\n- zweiter Fakt\n' > "$TMP/fence.md"
OUT="$(python3 "$RENDER" "$TMP/fence.md" 3000)"
printf '%s' "$OUT" | grep -q "non-canonical" \
  && bad "fenced header treated as section" "phantom section reported" \
  || ok "fenced ## stays inside its section"

# ---------------------------------------------------------------------------
echo "renderer: output is deterministic"
H1="$(python3 "$RENDER" "$TMP/budget.md" 1500 | shasum | cut -d' ' -f1)"
H2="$(python3 "$RENDER" "$TMP/budget.md" 1500 | shasum | cut -d' ' -f1)"
H3="$(python3 "$RENDER" "$TMP/budget.md" 1500 | shasum | cut -d' ' -f1)"
[ "$H1" = "$H2" ] && [ "$H2" = "$H3" ] && ok "three runs, one hash" \
                                       || bad "non-deterministic output" "hashes differ"

# ---------------------------------------------------------------------------
echo "hooks: the canary is a verdict, never a decoration"
# Regression: the canary was printed unconditionally, including on the degraded byte-cut
# fallback that had just lost VERIFIED and DROPPED entirely. Since the project
# instruction file treats a present canary as "no need to read the file", every restore
# defect suppressed its own remedy while showing a success signal.
LAB="$TMP/lab"; mkdir -p "$LAB/.claude/hooks" "$LAB/fakebin"
cp "$KIT/hooks/session-start-reinject.sh" "$KIT/hooks/ledger_render.py" "$LAB/.claude/hooks/"
python3 - "$LAB" <<'PY'
import sys, os
lab = sys.argv[1]
head = "# Session Ledger\n\n## TASK\nX\n\n## NEXT\nY\n\n## BLOAT\n" + ("fuell " * 900) + "\n"
tail = "\n## VERIFIED\n- DELTA-FACT proven\n\n## DROPPED\n- DELTA-PATH dropped\n"
open(os.path.join(lab, ".claude", "session-ledger.md"), "w", encoding="utf-8").write(head + tail)
PY
printf '#!/bin/sh\nexit 127\n' > "$LAB/fakebin/python3"; chmod +x "$LAB/fakebin/python3"
OUT="$(cd "$LAB" && echo '{"source":"compact"}' \
  | PATH="$LAB/fakebin:$PATH" bash .claude/hooks/session-start-reinject.sh 2>/dev/null)"
if printf '%s' "$OUT" | grep -q "CTX-LEDGER-RESTORED"; then
  bad "canary on a degraded restore" "fallback lost the delta sections and still claimed success"
else
  printf '%s' "$OUT" | grep -qi "INCOMPLETE" \
    && ok "degraded restore says INCOMPLETE and sends the reader to the file" \
    || bad "degraded restore is silent about its own damage" "neither canary nor warning"
fi
OUT="$(cd "$LAB" && echo '{"source":"compact"}' \
  | bash .claude/hooks/session-start-reinject.sh 2>/dev/null)"
printf '%s' "$OUT" | grep -q "CTX-LEDGER-RESTORED" \
  && ok "healthy restore does print the canary" \
  || bad "healthy restore lacks the canary" "the fallback would never be switched off"

# ---------------------------------------------------------------------------
echo "hooks: a forked session is restored, in the wiring and in the hook itself"
# A regression from outside, not from this repo. Up to v2.1.213 a forked session reported
# SessionStart source "resume", so the matcher "compact|resume" covered it. From v2.1.214
# the harness reports "fork" instead, and the same wiring silently stopped covering
# /branch, /fork and --fork-session. Nothing here changed; the platform did, which is why
# this is a test and not a comment. Two halves, because either one alone loses the restore
# with exit 0 and no output: the matcher decides whether the hook is called at all, and the
# case guard inside the hook decides whether it does anything once called.
LABF="$TMP/lab-fork"; mkdir -p "$LABF/.claude/hooks"
cp "$KIT/hooks/session-start-reinject.sh" "$KIT/hooks/ledger_render.py" "$LABF/.claude/hooks/"
printf '# Session Ledger\n\n## TASK\nFORK-PROBE\n\n## NEXT\nweiter\n' \
  > "$LABF/.claude/session-ledger.md"
OUTF="$(cd "$LABF" && echo '{"source":"fork"}' \
  | bash .claude/hooks/session-start-reinject.sh 2>/dev/null)"
WIREF="$(python3 - "$KIT" <<'PY'
import json, os, sys
kit = sys.argv[1]
need = {"compact", "resume", "fork"}
bad = []
# Both shipped wirings, because they are edited separately and drifted apart before:
# hooks.json is the plugin path, settings-snippet.json the standalone one. Read as JSON
# rather than grepped, so splitting one entry into three (which the snippet already does)
# stays correct.
for rel in ("hooks/hooks.json", "settings-snippet.json"):
    doc = json.load(open(os.path.join(kit, rel), encoding="utf-8"))
    hooks = doc.get("hooks", doc)
    covered = set()
    for entry in hooks.get("SessionStart", []):
        cmds = " ".join(h.get("command", "") for h in entry.get("hooks", []))
        if "session-start-reinject" not in cmds:
            continue
        covered |= set(entry.get("matcher", "").split("|"))
    missing = sorted(need - covered)
    if missing:
        bad.append("%s-misses-%s" % (os.path.basename(rel), "+".join(missing)))
print(",".join(bad) if bad else "OK")
PY
)"
if printf '%s' "$OUTF" | grep -q "FORK-PROBE" && [ "$WIREF" = "OK" ]; then
  ok "a forked session reaches the hook, and the hook restores"
else
  bad "a forked session loses the restore" \
      "hook-restored=$(printf '%s' "$OUTF" | grep -c FORK-PROBE) wiring=$WIREF"
fi

# ---------------------------------------------------------------------------
echo "hooks: the lint cannot become an unbreakable block"
# Regression: the whole anti-loop guarantee hung on one state write whose failure was
# swallowed. With the state path unwritable the hook returned exit 2 on every Stop
# forever (measured 2 2 2 2 2), and the only escape was disabling it.
# Exit 2 is gone now (see the silence test below), so the codes alone no longer prove
# anything: what is asserted is that an unwritable state produces NO warning at all,
# rather than one on every single turn.
LAB2="$TMP/lab2"; mkdir -p "$LAB2/.claude/hooks/" "$LAB2/.claude/.ledger-lint-state"
cp "$KIT/hooks/ledger-lint.sh" "$LAB2/.claude/hooks/"
python3 -c "
import sys
open(sys.argv[1],'w').write('# L\n\n## TASK\nx\n\n## BLOAT\n'+'y'*9000+'\n')" \
  "$LAB2/.claude/session-ledger.md"
CODES=""
EMITTED=0
for _ in 1 2 3 4; do
  OUT="$(cd "$LAB2" && echo '{}' | bash .claude/hooks/ledger-lint.sh 2>/dev/null)"
  CODES="$CODES$?"
  [ -n "$OUT" ] && EMITTED=$((EMITTED + 1))
done
[ "$CODES" = "0000" ] && ok "unwritable state never blocks the turn" \
                      || bad "lint blocks on unwritable state" "exit codes: $CODES (want 0000)"
[ "$EMITTED" -eq 0 ] && ok "unwritable state suppresses the warning instead of repeating it" \
                     || bad "lint nags on unwritable state" "$EMITTED of 4 calls warned with no cooldown record"

# ---------------------------------------------------------------------------
echo "hooks: the lint counts characters, not bytes"
# Regression: `wc -m` counts bytes without a UTF-8 locale (14 instead of 7 for ÄÖÜäöüß),
# so a German ledger tripped a 5000 limit at roughly 4200 real characters and the hook
# did not measure the same unit as the renderer it is pinned to.
LAB3="$TMP/lab3"; mkdir -p "$LAB3/.claude/hooks"
cp "$KIT/hooks/ledger-lint.sh" "$LAB3/.claude/hooks/"
python3 -c "
import sys
open(sys.argv[1],'w',encoding='utf-8').write('# L\n\n## TASK\n'+'ÄÖÜäöüß'*400+'\n')" \
  "$LAB3/.claude/session-ledger.md"
# 2800 characters, but 5600 bytes: must stay silent under a 5000 limit.
(cd "$LAB3" && rm -f .claude/.ledger-lint-state && echo '{}' \
  | SESSION_LEDGER_MAX_CHARS=5000 bash .claude/hooks/ledger-lint.sh >/dev/null 2>&1)
[ $? -eq 0 ] && ok "2800 umlaut characters do not trip a 5000 character limit" \
             || bad "lint counts bytes" "a German ledger trips the limit early"

# ---------------------------------------------------------------------------
echo "hooks: the size warning has a tolerance band, so nobody plays character golf"
# Regression: with a hard limit and a warning on the first character over, a real session
# rewrote entries and stripped markup to land at 4999 of 5000. It burned a turn and
# carried exactly the same content. A limit that makes the model optimise the counter
# instead of the content is set wrong, so the warning now needs a real overrun.
LAB6="$TMP/lab6"; mkdir -p "$LAB6/.claude/hooks"
cp "$KIT/hooks/ledger-lint.sh" "$LAB6/.claude/hooks/"
_ledger_of() {
  python3 -c "
import sys
n = int(sys.argv[2])
body = '# L\n\n## TASK\n'
open(sys.argv[1], 'w', encoding='utf-8').write(body + 'x' * (n - len(body)) + '\n')" \
    "$LAB6/.claude/session-ledger.md" "$1"
}
# The lint no longer signals by exit code (it never blocks), so the band is measured on
# whether anything was emitted at all.
_lint_emits() {
  OUT="$(cd "$LAB6" && rm -f .claude/.ledger-lint-state && echo '{}' \
    | SESSION_LEDGER_MAX_CHARS=5000 SESSION_LEDGER_TOLERANCE_PCT=15 \
      SESSION_LEDGER_CHECKPOINT_TRIGGER=off \
      bash .claude/hooks/ledger-lint.sh 2>/dev/null)"
  [ -n "$OUT" ] && echo yes || echo no
}
_ledger_of 5200   # 4 percent over: inside the band, must stay silent
[ "$(_lint_emits)" = "no" ] && ok "a few percent over stays silent" \
                            || bad "warns on a trivial overrun" "this is what caused the golfing"
_ledger_of 6500   # 30 percent over: a real overrun, must warn
[ "$(_lint_emits)" = "yes" ] && ok "a real overrun still warns" \
                             || bad "band swallows a real overrun" "the guard stopped guarding"

# ---------------------------------------------------------------------------
echo "hooks: the documented escape hatch actually unblocks"
# Regression: the block text offered `touch $MARKER`, which did not unblock, because the
# marker was never the problem. With auto-compaction off there was no second route, so
# the real escape people find is deleting the hook.
LAB4="$TMP/lab4"; mkdir -p "$LAB4/.claude/hooks"
cp "$KIT/hooks/precompact-guard.sh" "$KIT/hooks/ledger_render.py" "$LAB4/.claude/hooks/"
printf '# Session Ledger\n\n## TASK\n\n## NEXT\n\n' > "$LAB4/.claude/session-ledger.md"
(cd "$LAB4" && touch .claude/.checkpoint-ready && echo '{"trigger":"manual"}' \
  | bash .claude/hooks/precompact-guard.sh >/dev/null 2>&1)
[ $? -eq 2 ] && ok "a hollow checkpoint is still blocked" \
             || bad "hollow checkpoint passes" "the content check no longer bites"
(cd "$LAB4" && echo nothing-to-preserve > .claude/.checkpoint-ready \
  && echo '{"trigger":"manual"}' | bash .claude/hooks/precompact-guard.sh >/dev/null 2>&1)
[ $? -eq 0 ] && ok "the explicit opt-out unblocks" \
             || bad "escape hatch is a dead end" "documented opt-out still exits 2"

# ---------------------------------------------------------------------------
echo "hooks: an unreadable timestamp must not eat the ledger"
# Regression: `stat -f %m` is BSD mtime but GNU "mount point", so on Linux it printed "/"
# with exit 0, the arithmetic aborted the enclosing block under set -u, and prime did
# nothing at all: no restore, no rotate, no log line, exit 0.
LAB5="$TMP/lab5"; mkdir -p "$LAB5/.claude/hooks" "$LAB5/gnu"
cp "$KIT/hooks/session-start-prime.sh" "$KIT/hooks/ledger_render.py" "$LAB5/.claude/hooks/"
printf '# Session Ledger\n_session: S-OLD_\n\n## VERIFIED\n- CROWN-JEWEL proven\n' \
  > "$LAB5/.claude/session-ledger.md"
printf '#!/bin/sh\nif [ "$1" = "-f" ]; then echo "/"; exit 0; fi\nexec /usr/bin/stat "$@"\n' \
  > "$LAB5/gnu/stat"; chmod +x "$LAB5/gnu/stat"
OUT="$(cd "$LAB5" && echo '{"source":"startup","session_id":"S-NEU"}' \
  | PATH="$LAB5/gnu:$PATH" bash .claude/hooks/session-start-prime.sh 2>/dev/null)"
printf '%s' "$OUT" | grep -q CROWN-JEWEL \
  && ok "prime still restores when stat has GNU semantics" \
  || bad "prime dies silently on a GNU stat" "the ledger was not restored"

# ---------------------------------------------------------------------------
echo "hooks: chats are timeless, so no clock may retire a ledger"
# Regression: prime archived any ledger older than SESSION_LEDGER_STALE_HOURS (12) on the
# assumption that age means "previous task". A conversation picked up a week later has
# exactly the context it had, and worse: opening a NEW session in the same directory
# archived the ledger of an OLD session that was still alive, so resuming that conversation
# found its carrier gone. Age now decides nothing; ownership is flagged and the model
# decides on the first turn.
LAB10="$TMP/lab10"; mkdir -p "$LAB10/.claude/hooks"
cp "$KIT/hooks/session-start-prime.sh" "$KIT/hooks/ledger_render.py" "$LAB10/.claude/hooks/"
printf '# Session Ledger\n_session: S-OLD_\n\n## TASK\nold work\n\n## VERIFIED\n- CROWN-JEWEL proven\n' \
  > "$LAB10/.claude/session-ledger.md"
touch -t 202501010000 "$LAB10/.claude/session-ledger.md"   # roughly a year untouched
_restored() {   # <session-id> -> yes/no, plus whether the task check was raised
  (cd "$LAB10" && printf '{"source":"startup","session_id":"%s"}' "$1" \
    | bash .claude/hooks/session-start-prime.sh 2>/dev/null)
}
OUT="$(_restored S-OLD)"
case "$OUT" in *CROWN-JEWEL*) ok "a year-old ledger of this session is still restored" ;;
               *) bad "old ledger not restored" "a clock is still retiring live reasoning" ;; esac
case "$OUT" in *"Task check"*) bad "task check on its own ledger" "the owning session must not be questioned" ;;
               *) ok "no task check when the ledger belongs to this session" ;; esac
[ -d "$LAB10/.claude/session-ledger.archive" ] \
  && bad "ledger archived by age" "opening a new session would strand a live conversation" \
  || ok "nothing is archived by age"
OUT="$(_restored S-NEU)"
case "$OUT" in *CROWN-JEWEL*) ok "another session's ledger is restored, not discarded" ;;
               *) bad "foreign ledger dropped" "the decision belongs to the model, not the hook" ;; esac
case "$OUT" in *"Task check"*) ok "and it is flagged as belonging to another session" ;;
               *) bad "foreign ledger not flagged" "a mixed ledger restores the wrong decisions" ;; esac

# ---------------------------------------------------------------------------
echo "hooks: what the kit says to the model is not said to the user"
# Regression: plain stdout from a SessionStart hook is added to the context AND rendered in
# the transcript, so 3357 characters of maintenance protocol appeared as a message at every
# single session start, and the lint announced routine housekeeping through exit 2, which
# the harness surfaces as a hook error notice. A kit that asks to be read every few turns
# has become the work. The documented cure is a JSON result: suppressOutput keeps it out of
# the transcript, additionalContext still delivers it to the model.
LAB7="$TMP/lab7"; mkdir -p "$LAB7/.claude/hooks"
cp "$KIT/hooks/session-start-prime.sh" "$KIT/hooks/session-start-reinject.sh" \
   "$KIT/hooks/ledger-lint.sh" "$KIT/hooks/ledger_render.py" "$LAB7/.claude/hooks/"
_silent_json() {   # <output> <expected hookEventName> -> length of additionalContext, or -1
  printf '%s' "$1" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    h = d["hookSpecificOutput"]
    ok = d.get("suppressOutput") is True and h["hookEventName"] == sys.argv[1]
    print(len(h["additionalContext"]) if ok else -1)
except Exception:
    print(-1)
' "$2" 2>/dev/null || echo -1
}
OUT="$(cd "$LAB7" && echo '{"source":"startup","session_id":"S1"}' \
  | bash .claude/hooks/session-start-prime.sh 2>/dev/null)"
PROTO_LEN="$(_silent_json "$OUT" SessionStart)"
[ "${PROTO_LEN:-0}" -gt 0 ] && ok "prime delivers a suppressed SessionStart result" \
                            || bad "prime output is not a suppressed JSON result" "the protocol lands in the transcript"
{ [ "${PROTO_LEN:-0}" -gt 0 ] && [ "$PROTO_LEN" -le 700 ]; } \
  && ok "the primed protocol stays under 700 characters ($PROTO_LEN)" \
  || bad "primed protocol too fat or unreadable" "$PROTO_LEN characters at every session start"

printf '# Session Ledger\n\n## TASK\nX\n\n## DROPPED\n- PATH-A dropped: "quoted" and \\ escaped\n' \
  > "$LAB7/.claude/session-ledger.md"
OUT="$(cd "$LAB7" && echo '{"source":"compact"}' \
  | bash .claude/hooks/session-start-reinject.sh 2>/dev/null)"
[ "$(_silent_json "$OUT" SessionStart)" -gt 0 ] \
  && printf '%s' "$OUT" | python3 -c '
import json, sys
sys.exit(0 if "PATH-A" in json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"] else 1)' \
  && ok "reinject delivers the restore suppressed, escaping intact" \
  || bad "reinject is not silent or mangles the payload" "quotes and backslashes must survive json encoding"

python3 -c "
import sys
open(sys.argv[1],'w').write('# L\n\n## TASK\nx\n\n## BLOAT\n'+'y'*9000+'\n')" \
  "$LAB7/.claude/session-ledger.md"
ERR="$LAB7/lint.err"
OUT="$(cd "$LAB7" && echo '{}' | bash .claude/hooks/ledger-lint.sh 2>"$ERR")"
RC=$?
LINT_LEN="$(_silent_json "$OUT" Stop)"
{ [ "$RC" -eq 0 ] && [ ! -s "$ERR" ] && [ "$LINT_LEN" -gt 0 ]; } \
  && ok "the lint warns through additionalContext, never through an error notice" \
  || bad "lint still surfaces as an error" "rc=$RC stderr=$( [ -s "$ERR" ] && echo nonempty || echo empty ) json=$LINT_LEN"
{ [ "${LINT_LEN:-0}" -gt 0 ] && [ "$LINT_LEN" -le 600 ]; } \
  && ok "the lint warning stays under 600 characters ($LINT_LEN)" \
  || bad "lint text too long or unreadable" "$LINT_LEN characters of sermon"

# ---------------------------------------------------------------------------
echo "hooks: the checkpoint fires itself before the guardrail has to block"
# The PreCompact guardrail can only ever say no, and only to the user: PreCompact output
# never reaches the model, so by compaction time nothing can still be prepared. The Stop
# hook can, because there the model still has a turn. Measured here: silent until real work
# piled up, one nudge, then silent again until the next stretch.
LAB9="$TMP/lab9"; mkdir -p "$LAB9/.claude/hooks"
cp "$KIT/hooks/ledger-lint.sh" "$LAB9/.claude/hooks/"
printf '# L\n\n## TASK\nsmall and healthy\n' > "$LAB9/.claude/session-ledger.md"
TRANSCRIPT="$LAB9/transcript.jsonl"
python3 -c "import sys;open(sys.argv[1],'w').write('x'*10000)" "$TRANSCRIPT"
_nudge() {
  OUT="$(cd "$LAB9" && printf '{"transcript_path":"%s"}' "$TRANSCRIPT" \
    | SESSION_LEDGER_CHECKPOINT_TRIGGER=on SESSION_LEDGER_CHECKPOINT_TRIGGER_KB=50 \
      bash .claude/hooks/ledger-lint.sh 2>/dev/null)"
  case "$OUT" in *"checkpoint is overdue"*) echo yes ;; *) echo no ;; esac
}
_grow() { python3 -c "import sys;open(sys.argv[1],'a').write('y'*int(sys.argv[2]))" "$TRANSCRIPT" "$1"; }
FIRST="$(_nudge)"          # takes the baseline
_grow 20000; SMALL="$(_nudge)"
_grow 60000; FIRED="$(_nudge)"
AGAIN="$(_nudge)"
[ "$FIRST" = "no" ] && [ "$SMALL" = "no" ] && ok "no nudge before real work has piled up" \
                                           || bad "nudge fires too eagerly" "first=$FIRST small=$SMALL"
[ "$FIRED" = "yes" ] && ok "past the threshold the checkpoint is triggered once" \
                     || bad "nudge never fires" "the guardrail is left as the only mechanism"
[ "$AGAIN" = "no" ] && ok "it does not repeat on the next turn" \
                    || bad "nudge repeats" "a self-firing checkpoint every turn is worse than a late one"
# The default is the assertion here. A self-firing checkpoint interrupts work nobody asked
# to interrupt, so it must stay silent unless someone opts in. Threshold set to 1 KB, which
# every transcript passes: if the default were on, this would nudge.
OFF="$(cd "$LAB9" && printf '{"transcript_path":"%s"}' "$TRANSCRIPT" \
  | SESSION_LEDGER_CHECKPOINT_TRIGGER_KB=1 bash .claude/hooks/ledger-lint.sh 2>/dev/null)"
case "$OFF" in *"checkpoint is overdue"*) bad "self-firing checkpoint is on by default" "it nudged without an opt-in" ;;
               *) ok "the checkpoint never fires itself unless asked to" ;; esac

# Every session writes its own transcript, so a baseline carried over from the previous
# one is compared against a file that starts small again. Measured before the fix: the
# growth came out negative for the rest of the day and the nudge never fired again, which
# is the worst kind of defect, a mechanism that silently stops being one.
TRANSCRIPT="$LAB9/transcript-session-2.jsonl"
python3 -c "import sys;open(sys.argv[1],'w').write('x'*5000)" "$TRANSCRIPT"
NEW_FIRST="$(_nudge)"
_grow 80000
[ "$NEW_FIRST" = "no" ] && [ "$(_nudge)" = "yes" ] \
  && ok "a new session's transcript resets the baseline instead of muting the nudge" \
  || bad "nudge dies after the first session" "the baseline is still measured against the old transcript"

# ---------------------------------------------------------------------------
echo "hooks: the renderer is found wherever the hooks are installed"
# Regression: RENDER was hardcoded to ".claude/hooks/ledger_render.py". Install the hooks
# anywhere else, which is exactly what a plugin install does (${CLAUDE_PLUGIN_ROOT}/hooks/),
# and the renderer is simply not there. Nothing errors: the restore drops to the byte cut,
# loses the priority budgeting, and reports itself INCOMPLETE. A silent downgrade of the one
# component that exists to prevent silent downgrades.
LAB11="$TMP/lab11"; mkdir -p "$LAB11/elsewhere/hooks" "$LAB11/proj/.claude"
cp "$KIT/hooks/session-start-reinject.sh" "$KIT/hooks/ledger_render.py" "$LAB11/elsewhere/hooks/"
printf '# Session Ledger\n\n## TASK\nX\n\n## VERIFIED\n- FACT proven\n\n## DROPPED\n- PATH dropped\n' \
  > "$LAB11/proj/.claude/session-ledger.md"
OUT="$(cd "$LAB11/proj" && echo '{"source":"compact"}' \
  | bash ../elsewhere/hooks/session-start-reinject.sh 2>/dev/null)"
case "$OUT" in
  *CTX-LEDGER-RESTORED*) ok "a restore from outside .claude/hooks is still complete" ;;
  *) bad "renderer not found outside .claude/hooks" "a plugin install would silently degrade every restore" ;;
esac

# ---------------------------------------------------------------------------
echo "release: the plugin manifests are valid and point at files that exist"
# A plugin whose hooks.json names a script that is not there installs cleanly and does
# nothing, which is the failure mode this kit exists to argue against. So the wiring is
# checked against the filesystem, not read for plausibility.
MANIFEST_PROBLEMS="$(python3 - "$KIT" <<'PY'
import json, os, sys
kit = sys.argv[1]
bad = []
for rel in (".claude-plugin/plugin.json", ".claude-plugin/marketplace.json",
            "hooks/hooks.json", "settings-snippet.json"):
    try:
        json.load(open(os.path.join(kit, rel), encoding="utf-8"))
    except Exception:
        bad.append("unparsable:" + rel)
# The runtime loads hooks/hooks.json by itself. Naming it again under manifest.hooks
# makes the WHOLE plugin fail to load ("Duplicate hooks file detected"), and the manifest
# validator does not catch it: validate was green while a real install refused the plugin.
plugin = json.load(open(os.path.join(kit, ".claude-plugin/plugin.json"), encoding="utf-8"))
declared = plugin.get("hooks")
for d in ([declared] if isinstance(declared, str) else (declared or [])):
    if os.path.normpath(d).endswith(os.path.join("hooks", "hooks.json")):
        bad.append("duplicate-hooks-declaration:" + d)
hooks = json.load(open(os.path.join(kit, "hooks/hooks.json"), encoding="utf-8"))["hooks"]
for event, groups in hooks.items():
    for g in groups:
        for h in g.get("hooks", []):
            cmd = h["command"]
            if "${CLAUDE_PLUGIN_ROOT}" not in cmd:
                bad.append("unrooted:" + event)
            script = cmd.split("}\"", 1)[-1].lstrip("/")
            if not os.path.exists(os.path.join(kit, script)):
                bad.append("missing:" + script)
# The two install paths must cover the same events, or one of them silently does less.
snippet = json.load(open(os.path.join(kit, "settings-snippet.json"), encoding="utf-8"))
if set(snippet["hooks"]) != set(hooks):
    bad.append("event-drift:%s-vs-%s" % (sorted(hooks), sorted(snippet["hooks"])))
# And this repository has to actually RUN what it ships. sync.sh copies the files but not
# settings.json, which is a working file, so a newly wired hook lands everywhere except in
# the one installation that would have caught its defects first. Measured: prompt-checkpoint
# shipped and was wired in two foreign projects while the workshop itself never fired it.
# Every delivered file must have an installed counterpart. sync.sh used to carry a hardcoded
# table, so a newly added file was neither copied nor reported: prompt-checkpoint.sh shipped,
# the workshop installation never received it, and `sync.sh --check` still said "identical".
# The one command whose job is to prevent diverging copies was blind to the newest one.
for d in ("hooks", "skills", "commands", "tools"):
    base = os.path.join(kit, d)
    for root, _, files in os.walk(base) if os.path.isdir(base) else []:
        for f in files:
            if f in ("hooks.json", ".DS_Store"):
                continue
            rel = os.path.relpath(os.path.join(root, f), kit)
            if not os.path.exists(os.path.join(kit, ".claude", rel)):
                bad.append("never-installed:" + rel)

own = os.path.join(kit, ".claude/settings.json")
if os.path.exists(own):
    mine = json.load(open(own, encoding="utf-8"))
    for ev in snippet["hooks"]:
        if ev not in mine.get("hooks", {}):
            bad.append("not-dogfooded:" + ev)
    for key in snippet["env"]:
        if key not in mine.get("env", {}):
            bad.append("env-not-dogfooded:" + key)
print(",".join(bad) if bad else "OK")
PY
)"
[ "$MANIFEST_PROBLEMS" = "OK" ] && ok "plugin manifests parse and every wired script exists" \
                            || bad "plugin wiring is broken" "$MANIFEST_PROBLEMS"

# ---------------------------------------------------------------------------
echo "release: the version is one number, not two that happen to agree"
# The version lives in plugin.json AND in the marketplace entry, and the marketplace copy is
# the one the harness compares against to decide whether an installed plugin is out of date.
# Bumping only one is therefore not a cosmetic slip: it ships a release that existing users
# never receive. Two hand-typed copies of the same fact always drift eventually, so the
# agreement is checked rather than remembered.
VERSION_PROBLEMS="$(python3 - "$KIT" <<'PY'
import json, os, re, sys
kit = sys.argv[1]
bad = []
plugin = json.load(open(os.path.join(kit, ".claude-plugin/plugin.json"), encoding="utf-8"))
market = json.load(open(os.path.join(kit, ".claude-plugin/marketplace.json"), encoding="utf-8"))
want = plugin.get("version")
if not want:
    bad.append("plugin-json-has-no-version")
for entry in market.get("plugins", []):
    got = entry.get("version")
    if got is None:
        bad.append("marketplace-entry-has-no-version:" + str(entry.get("name")))
    elif got != want:
        bad.append("version-drift:plugin-%s-vs-marketplace-%s" % (want, got))
# The changelog is where a reader looks up what a version contains, so a release the
# changelog has never heard of is a release nobody can read.
path = os.path.join(kit, "CHANGELOG.md")
if want and os.path.exists(path):
    text = open(path, encoding="utf-8").read()
    if not re.search(r'^##\s+%s\b' % re.escape(want), text, re.M):
        bad.append("changelog-never-mentions:" + want)
print(",".join(sorted(set(bad))) if bad else "OK")
PY
)"
[ "$VERSION_PROBLEMS" = "OK" ] && ok "both manifests and the changelog state the same version" \
                              || bad "the version drifted between its copies" "$VERSION_PROBLEMS"

# ---------------------------------------------------------------------------
echo "release: every runtime file the kit writes is ignored, here and in the README"
# The kit writes state into the adopter's repository. A path that no .gitignore covers
# turns up as a committable file in someone else's project, which is the kind of mess a
# tool has no business making. The list is derived from the scripts, not maintained by
# hand, so a new state file cannot quietly skip both lists. This went red once: the probe
# token directory was written by tools/effect-probe.sh and covered nowhere.
IGNORE_PROBLEMS="$(python3 - "$KIT" <<'PY'
import os, re, sys
kit = sys.argv[1]
paths = set()
for d, pat in (("hooks", r"\.(sh|py)$"), ("tools", r"\.sh$")):
    base = os.path.join(kit, d)
    for f in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        if not re.search(pat, f):
            continue
        for m in re.findall(r'"(\.claude/[^"]+)"', open(os.path.join(base, f), encoding="utf-8").read()):
            # These four are where the kit is INSTALLED: source, versioned by the adopter,
            # never state. Everything else a script names under .claude/ is something it
            # writes, and that has to be ignorable. The list started at hooks/ alone and grew
            # when a hook first read a sibling SKILL.md and was reported as an unignored
            # runtime file.
            if not any(m.startswith(".claude/%s/" % d)
                       for d in ("hooks", "skills", "commands", "tools")):
                paths.add(m.rstrip("/"))

def covered(path, lines):
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.rstrip("/") == path or (line.endswith("/") and path.startswith(line)):
            return True
    return False

gitignore = open(os.path.join(kit, ".gitignore"), encoding="utf-8").read().splitlines()
readme = open(os.path.join(kit, "README.md"), encoding="utf-8").read()
block = re.search(r"```gitignore\n(.*?)```", readme, re.S)
block = block.group(1).splitlines() if block else []
bad = []
for p in sorted(paths):
    if not covered(p, gitignore):
        bad.append("unignored:" + p)
    if not covered(p, block):
        bad.append("missing-from-readme:" + p)
print(",".join(bad) if bad else "OK")
PY
)"
[ "$IGNORE_PROBLEMS" = "OK" ] && ok "no runtime file of the kit can land in someone's commit" \
                          || bad "runtime state is not ignored" "$IGNORE_PROBLEMS"

# ---------------------------------------------------------------------------
echo "degradation: without python3 the other two hooks degrade honestly too"
# The reinject hook has been covered above since the day the fallback lost content silently.
# The other two were not, and the README promises honest degradation for the whole kit, not
# for one third of it. prime must fall back to plain text, withhold the canary, say
# INCOMPLETE and still carry the content; the lint must simply stay quiet.
LAB_NP="$TMP/nopy"; mkdir -p "$LAB_NP/.claude/hooks" "$LAB_NP/fakebin"
cp "$KIT"/hooks/*.sh "$KIT/hooks/ledger_render.py" "$LAB_NP/.claude/hooks/"
printf '#!/bin/sh\nexit 127\n' > "$LAB_NP/fakebin/python3"; chmod +x "$LAB_NP/fakebin/python3"
printf '# Session Ledger\n\n## TASK\nX\n\n## NEXT\nY\n\n## DROPPED\n- NOPY-PATH dropped\n' \
  > "$LAB_NP/.claude/session-ledger.md"
NP_OUT="$(cd "$LAB_NP" && echo '{"source":"startup"}' \
  | PATH="$LAB_NP/fakebin:$PATH" bash .claude/hooks/session-start-prime.sh 2>/dev/null)"
NP_BAD=""
printf '%s' "$NP_OUT" | grep -q "CTX-LEDGER-RESTORED" && NP_BAD="$NP_BAD canary-over-a-degraded-restore"
printf '%s' "$NP_OUT" | grep -qi "incomplete"          || NP_BAD="$NP_BAD silent-about-its-own-damage"
printf '%s' "$NP_OUT" | grep -q "NOPY-PATH"             || NP_BAD="$NP_BAD content-lost-entirely"
[ -z "$NP_BAD" ] && ok "prime without python3 degrades and admits it" \
                 || bad "prime degrades badly" "$NP_BAD"
# Silence is the wanted outcome here, and a crashed hook is also silent, so the check may
# not read emptiness as success on its own. It reports a sentinel that only a hook that
# actually ran and actually said nothing can produce, exit code included.
NP_LINT="$(cd "$LAB_NP" && { OUT="$(printf '{"transcript_path":"/dev/null"}' \
    | PATH="$LAB_NP/fakebin:$PATH" bash .claude/hooks/ledger-lint.sh 2>/dev/null)"; RC=$?
  if [ -n "$OUT" ]; then printf 'spoke:%s' "$OUT"
  elif [ "$RC" -ne 0 ]; then printf 'rc:%s' "$RC"
  else printf 'silent-rc0'; fi; })"
[ "$NP_LINT" = "silent-rc0" ] && ok "the lint without python3 stays quiet and exits clean" \
                              || bad "lint misbehaves without python3" "$NP_LINT"

# ---------------------------------------------------------------------------
echo "carrier: the project state is pointed at, or it is write-only"
# A design review found this the hard way: the project state file had a write path specified in
# five places and no read path anywhere. A file on disk survives compaction by itself, but
# the model opens only what it was pointed at, so an unpointed carrier is write-only however
# carefully it is maintained. Two pointers make it readable, and both are checked here
# because losing either one silently restores the original defect: PLAN must be defined as
# carrying it, and the archive instruction (the one moment the ledger's content is about to
# die) must say to carry the durable half over first.
POINTER_PROBLEMS="$(python3 - "$KIT" <<'PY'
import os, sys
kit = sys.argv[1]
bad = []
skill = open(os.path.join(kit, "skills/session-ledger/SKILL.md"), encoding="utf-8").read().lower()
# The PLAN section has to name the project state, not just the plan file.
plan_block = skill.split("## plan", 1)[-1][:1200] if "## plan" in skill else ""
if "project state" not in plan_block:
    bad.append("PLAN-does-not-point-at-the-project-state")
prime = open(os.path.join(kit, "hooks/session-start-prime.sh"), encoding="utf-8").read().lower()
if "archive it first and start clean" in prime and "project state" not in prime:
    bad.append("archive-instruction-drops-the-durable-half")
if "project state" not in prime:
    bad.append("prime-never-names-the-project-state")
print(",".join(bad) if bad else "OK")
PY
)"
[ "$POINTER_PROBLEMS" = "OK" ] && ok "the project state is reachable, not just writable" \
                               || bad "a durable carrier has no reader" "$POINTER_PROBLEMS"

# ---------------------------------------------------------------------------
echo "release: the assertion count in the docs is the real one"
# Three documents advertise how many assertions this suite has, and the number drifted three
# separate times in one day: 39, 40, 41, 42, 43, 45, each time because a new assertion was
# added and one of the three copies was missed. A number that no longer matches its
# measurement is exactly the kind of claim this kit tells other people not to make, so the
# suite counts itself by counting its own success call sites, one per assertion, which is
# also why every assertion has exactly one. The pattern must not appear in prose above, or
# the counter counts the comment: that happened on the first attempt and reported 48 of 46.
COUNT_PROBLEMS="$(python3 - "$KIT" <<'PY'
import os, re, sys
kit = sys.argv[1]
# The pattern is assembled, never written out: a literal here would be found by the search
# it defines. First attempt reported 48 of 46 for exactly that reason, twice over. It is a
# plain string count, so a helper whose name ENDS in that pattern inflates it too: a function
# called _prompt_hook added five phantom assertions before it was renamed.
needle = "ok" + ' "'
real = open(os.path.join(kit, "tests/run.sh"), encoding="utf-8").read().count(needle)
bad = []
# The set of documents is DERIVED from the directory, not typed here. A typed list covers
# exactly the documents that existed when someone typed it, and the one it misses is always
# the newest, which is the one most likely to carry a fresh number. Deriving it also settles
# the other case for free: CLAUDE.md belongs to the workshop and is absent from an export, so
# it is simply not in the listing, instead of being an entry that has to be skipped by hand.
# Note for editors: no apostrophe in this comment. It sits in a heredoc inside a command
# substitution, and bash 3.2 loses the closing paren over one.
for rel in sorted(f for f in os.listdir(kit) if f.endswith(".md")):
    path = os.path.join(kit, rel)
    if not os.path.exists(path):
        continue
    text = open(path, encoding="utf-8").read()
    # (?:\s|%20) because the README carries the number in a badge URL too, where the space is
    # percent-encoded. A hand-typed number no checker can see is exactly how a stale claim
    # survives a release, and the badge is the most-read number in the file.
    # Three spellings of the same number, and the third was found the hard way: "64 of 64
    # green in each" sat in the README through two count bumps because the pattern only knew
    # the word assertion. A number is a claim in whatever grammar it is written.
    claims = (re.findall(r'(\d+)(?:\s|%20)+[Aa]ssertions?', text)
              + re.findall(r'(?:one|One) of the (\d+)', text)
              + [n for pair in re.findall(r'(\d+)\s+of\s+(\d+)\s+green', text) for n in pair])
    for claimed in claims:
        if int(claimed) != real:
            bad.append("%s:claims-%s-real-%d" % (rel, claimed, real))
print(",".join(sorted(set(bad))) if bad else "OK")
PY
)"
[ "$COUNT_PROBLEMS" = "OK" ] && ok "every document states the assertion count this suite really has" \
                             || bad "an advertised count drifted from the measurement" "$COUNT_PROBLEMS"

# ---------------------------------------------------------------------------
echo "release: the docs name the commands the way the install actually spells them"
# Two install paths, two spellings. As a plugin the commands are namespaced
# (/context-kit:checkpoint); standalone they are not. Measured in a real plugin install:
# plain /checkpoint answered "isn't available in this environment" while the namespaced form
# ran. Docs that only ever write the short form send a plugin user into a dead end on their
# first command, so the README has to name the namespaced form at least once, and every
# command the docs mention has to exist.
NAMING_PROBLEMS="$(python3 - "$KIT" <<'PY'
import os, re, sys
kit = sys.argv[1]
bad = []
readme = open(os.path.join(kit, "README.md"), encoding="utf-8").read()
plugin_ns = "context-kit"
if "/%s:" % plugin_ns not in readme:
    bad.append("readme-never-shows-the-namespaced-form")
# Every slash command the delivered docs name is either a harness builtin or a file here.
builtin = {"compact", "plugin", "reload-plugins", "reload-skills", "goal", "loop", "clear", "config", "help",
           # Named by the docs to mark the boundary: these answer what is configured, the
           # briefing answers what happened. Naming them is the point, so they belong here.
           "status", "permissions", "context",
           # Named as a hazard, not as a feature: "checkpoint" is an alias of this one, and
           # it restores code and conversation. The docs have to be able to say so.
           "rewind"}
have = {f[:-3] for f in os.listdir(os.path.join(kit, "commands")) if f.endswith(".md")}
docs = ["README.md", "GUIDE.md"] + ["commands/" + f for f in os.listdir(os.path.join(kit, "commands"))]
for rel in docs:
    text = open(os.path.join(kit, rel), encoding="utf-8").read()
    for name in re.findall(r'`/([a-z][a-z0-9-]*)`', text):
        if name not in builtin and name not in have:
            bad.append("%s-names-missing-command:%s" % (os.path.basename(rel), name))
print(",".join(sorted(set(bad))) if bad else "OK")
PY
)"
[ "$NAMING_PROBLEMS" = "OK" ] && ok "every command the docs name exists, and the plugin spelling is stated" \
                              || bad "docs and install disagree on command names" "$NAMING_PROBLEMS"

# ---------------------------------------------------------------------------
echo "release: everything that drives the checkpoint knows all three carriers"
# The kit keeps three durable carriers, separated by reach: the ledger per task, the project
# state per project, memory across projects. They are enumerated in more than one place, and
# an enumeration that falls out of step is not cosmetic: the command file is what runs when
# the user types the slash command, so a carrier missing there is a carrier the checkpoint
# does not reconcile. Measured: the project state was added to the skill and the manifest,
# while the command file and the guardrail message still listed the old two.
CARRIER_PROBLEMS="$(python3 - "$KIT" <<'PY'
import os, sys
kit = sys.argv[1]
need = {"ledger": ("ledger",), "project state": ("project-state", "project state"),
        "memory": ("memory",)}
bad = []
for rel in ("skills/checkpoint/SKILL.md", "commands/checkpoint.md",
            "hooks/precompact-guard.sh",
            # The lint tells the model where to move content it is asked to trim, and the
            # ledger skill says what to do before archiving. Both direct durable knowledge,
            # so both were sending project-scoped reasoning to the wrong store.
            "hooks/ledger-lint.sh", "skills/session-ledger/SKILL.md"):
    text = open(os.path.join(kit, rel), encoding="utf-8").read().lower()
    for label, forms in need.items():
        if not any(f in text for f in forms):
            bad.append("%s-misses-%s" % (os.path.basename(rel), label.replace(" ", "-")))
print(",".join(bad) if bad else "OK")
PY
)"
[ "$CARRIER_PROBLEMS" = "OK" ] && ok "no carrier is missing where the checkpoint is driven" \
                               || bad "a durable carrier is enumerated inconsistently" "$CARRIER_PROBLEMS"

# ---------------------------------------------------------------------------
echo "brief: the digest finds what happened, in a project it has never seen"
# The effect assertion for the briefing, and the only one here that measures result rather
# than mechanism. The carrier lesson applies: the project state file once had an assertion
# that checked document consistency against document consistency and proved nothing. So this
# builds a throwaway project with a synthetic transcript carrying a token no inference can
# produce, and requires the digest to surface it. It goes red if discovery, the window, or
# the failure extraction breaks.
PROBE="$TMP/brief-probe"
mkdir -p "$PROBE/proj" "$PROBE/cfg/projects/synthetic"
python3 - "$PROBE" <<'PY'
import json, os, sys, datetime
probe = sys.argv[1]
proj = os.path.join(probe, "proj")
now = datetime.datetime.now()
def ts(mins):
    return (now - datetime.timedelta(minutes=mins)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
rows = [
    {"type": "user", "timestamp": ts(300), "cwd": proj,
     "message": {"role": "user", "content": "<command-name>/brief</command-name>"}},
    {"type": "assistant", "timestamp": ts(200), "cwd": proj,
     "message": {"content": [{"type": "tool_use", "id": "t1", "name": "Agent"}]}},
    {"type": "user", "timestamp": ts(150), "cwd": proj,
     "message": {"role": "user", "content": [
         {"type": "tool_result", "is_error": True, "content": "QQ-PROBE-9931 exploded"}]}},
    {"type": "user", "timestamp": ts(100), "cwd": proj,
     "message": {"role": "user", "content": "check the QQ-PROBE-9931 path please"}},
    {"type": "user", "timestamp": ts(1), "cwd": proj,
     "message": {"role": "user", "content": "<command-name>/brief</command-name>"}},
]
with open(os.path.join(probe, "cfg/projects/synthetic/s.jsonl"), "w", encoding="utf-8") as fh:
    for r in rows:
        fh.write(json.dumps(r) + "\n")
PY
BEFORE="$(cd "$PROBE" && find . | sort | md5 2>/dev/null || (cd "$PROBE" && find . | sort | md5sum))"
BRIEF_OUT="$(cd "$PROBE/proj" && CLAUDE_CONFIG_DIR="$PROBE/cfg" bash "$KIT/tools/brief-digest.sh" 2>&1)"
AFTER="$(cd "$PROBE" && find . | sort | md5 2>/dev/null || (cd "$PROBE" && find . | sort | md5sum))"
BRIEF_PROBLEMS=""
case "$BRIEF_OUT" in *"QQ-PROBE-9931 exploded"*) ;; *) BRIEF_PROBLEMS="$BRIEF_PROBLEMS,failure-not-surfaced" ;; esac
case "$BRIEF_OUT" in *"since the last brief"*) ;; *) BRIEF_PROBLEMS="$BRIEF_PROBLEMS,window-not-taken-from-transcript" ;; esac
case "$BRIEF_OUT" in *"1 agent or workflow start"*) ;; *) BRIEF_PROBLEMS="$BRIEF_PROBLEMS,background-not-counted" ;; esac
# The current invocation is itself the newest user message. Counting it as the previous look
# would make every window empty, so it has to be excluded, and that is checked here.
case "$BRIEF_OUT" in *"check the QQ-PROBE-9931 path"*) ;; *) BRIEF_PROBLEMS="$BRIEF_PROBLEMS,own-invocation-swallowed-the-window" ;; esac
[ "$BEFORE" = "$AFTER" ] || BRIEF_PROBLEMS="$BRIEF_PROBLEMS,it-wrote-to-disk"
[ -z "$BRIEF_PROBLEMS" ] && BRIEF_PROBLEMS="OK"
[ "$BRIEF_PROBLEMS" = "OK" ] && ok "the briefing digest surfaces a planted event and leaves no trace" \
                             || bad "the briefing digest missed its own probe" "$BRIEF_PROBLEMS"

# ---------------------------------------------------------------------------
echo "brief: the character budget is a post-condition, like the renderer's"
# Same class of defect as the renderer's budget, and the same reason it matters: this digest
# is read inside a working session, so every character it spends is a character the work
# loses for the rest of the window. Measured on the first run: the truncation marker was
# appended after the cut and pushed the result 13 characters past its own cap.
# It is measured against a BUSY project, and in characters. Both details are the assertion:
# the first version of this check ran against the small probe above, where the mandatory head
# blocks are tiny, so it stayed green while the shipped digest emitted 21273 characters
# against a budget of 4000 in a real repository. And it counted bytes, which reports a false
# overrun on any umlaut; the budget is a character budget, exactly as the lint's is.
BUSY="$TMP/brief-busy"
mkdir -p "$BUSY/proj" "$BUSY/cfg/projects/synthetic"
python3 - "$BUSY" <<'PY'
import json, os, sys, datetime
busy = sys.argv[1]
proj = os.path.join(busy, "proj")
now = datetime.datetime.now()
def ts(mins):
    return (now - datetime.timedelta(minutes=mins)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
rows = []
# A fat head: 300 failures, which is the block that crowded out the narrative blocks.
for i in range(300):
    rows.append({"type": "user", "timestamp": ts(600 - i), "cwd": proj,
                 "message": {"role": "user", "content": [
                     {"type": "tool_result", "is_error": True,
                      "content": "failure number %d with a reasonably long message body" % i}]}})
for i in range(100):
    rows.append({"type": "user", "timestamp": ts(280 - i), "cwd": proj,
                 "message": {"role": "user", "content": "a user message number %d" % i}})
    rows.append({"type": "assistant", "timestamp": ts(279 - i), "cwd": proj,
                 "message": {"content": [{"type": "text", "text": "an assistant line number %d" % i}]}})
rows.append({"type": "user", "timestamp": ts(0), "cwd": proj,
             "message": {"role": "user", "content": "<command-name>/brief</command-name>"}})
with open(os.path.join(busy, "cfg/projects/synthetic/s.jsonl"), "w", encoding="utf-8") as fh:
    for r in rows:
        fh.write(json.dumps(r) + "\n")
PY
_busy_digest() {
  (cd "$BUSY/proj" && CLAUDE_CONFIG_DIR="$BUSY/cfg" SESSION_LEDGER_BRIEF_BUDGET="$1" \
     bash "$KIT/tools/brief-digest.sh" 2>/dev/null)
}
BUDGET_PROBLEMS="$(
  out=""
  for b in 800 1500 3000 4000 8000; do
    n="$(_busy_digest "$b" | sed -n '3,$p' | wc -m | tr -d ' ')"
    [ "$n" -gt "$b" ] && out="$out,budget-$b-emitted-$n"
  done
  # Starvation: a noisy head must not silence the tail. Every block that has something to say
  # at a large budget has to still appear at the default one, even if only in part.
  big="$(_busy_digest 40000 | grep -c '^== ')"
  small="$(_busy_digest 4000 | grep -c '^== ')"
  [ "$big" = "$small" ] || out="$out,blocks-$big-at-40000-but-$small-at-4000"
  [ -n "$out" ] && printf '%s' "$out" || printf 'OK'
)"
[ "$BUDGET_PROBLEMS" = "OK" ] && ok "the digest fills its budget exactly and starves no block" \
                              || bad "the digest overshot its budget or starved a block" "$BUDGET_PROBLEMS"

# ---------------------------------------------------------------------------
echo "brief: the read is bounded, and it says so instead of pretending it saw everything"
# Measured in a real repository: 26844 entries across 37 compactions in one day made the
# unbounded read take 285 seconds and hit a two minute timeout. Bounds are the fix, and a
# silent bound would be the worse defect: a digest that quietly saw less than it claims reads
# like a quiet day. So the bound is checked together with its announcement.
python3 - "$BUSY" <<'PY'
import json, os, sys, datetime
busy = sys.argv[1]
proj = os.path.join(busy, "proj")
old = os.path.join(busy, "cfg/projects/synthetic/ancient.jsonl")
t = (datetime.datetime.now() - datetime.timedelta(days=40)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
with open(old, "w", encoding="utf-8") as fh:
    fh.write(json.dumps({"type": "user", "timestamp": t, "cwd": proj,
                         "message": {"role": "user", "content": "ANCIENT-TOKEN-4417"}}) + "\n")
os.utime(old, (0, 0))
PY
BOUND_OUT="$(cd "$BUSY/proj" && CLAUDE_CONFIG_DIR="$BUSY/cfg" SESSION_LEDGER_BRIEF_BUDGET=40000 \
             bash "$KIT/tools/brief-digest.sh" 2>/dev/null)"
BOUND_PROBLEMS=""
# Not checked by the planted token: a 40 day old entry falls outside the window anyway, so
# its absence would prove nothing about the read. What proves it is the count of files opened.
case "$BOUND_OUT" in *"from 1 of 2 transcript file(s)"*) ;; *) BOUND_PROBLEMS="$BOUND_PROBLEMS,old-file-was-read-anyway" ;; esac
case "$BOUND_OUT" in *"read was bounded"*) ;; *) BOUND_PROBLEMS="$BOUND_PROBLEMS,bound-not-announced" ;; esac
[ -z "$BOUND_PROBLEMS" ] && BOUND_PROBLEMS="OK"
[ "$BOUND_PROBLEMS" = "OK" ] && ok "an out of range transcript is skipped, and the skip is reported" \
                             || bad "the read bound is silent or absent" "$BOUND_PROBLEMS"

# ---------------------------------------------------------------------------
echo "brief: an interrupted brief does not leave the next one with an empty window"
# Measured: a /brief was interrupted, and because the window hangs on the COMMAND and not on
# its result, the retry four minutes later reported a correct and useless "since the last
# brief, 10 entries, under a minute". The user had to guess a span by hand. The mark cannot be
# made to depend on the result, because this tool writes no file by design, so the fallback is
# measured on content: too little in the window reads as a repeated call, not as a quiet night.
RETRY="$TMP/brief-retry"
mkdir -p "$RETRY/proj" "$RETRY/cfg/projects/synthetic"
python3 - "$RETRY" <<'PY'
import json, os, sys, datetime
retry = sys.argv[1]
proj = os.path.join(retry, "proj")
now = datetime.datetime.now()
def ts(mins):
    return (now - datetime.timedelta(minutes=mins)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
rows = [{"type": "user", "timestamp": ts(600), "cwd": proj,
         "message": {"role": "user", "content": "<command-name>/brief</command-name>"}}]
# A real night of work between the two briefs.
for i in range(120):
    # Over 40 characters on purpose: the digest drops shorter assistant lines as noise, so a
    # terse fixture would fail this check for a reason that has nothing to do with the window.
    rows.append({"type": "assistant", "timestamp": ts(590 - i * 4), "cwd": proj,
                 "message": {"content": [{"type": "text",
                                          "text": "work step RETRY-TOKEN-8802 number %d, a line long enough to survive the noise filter" % i}]}})
# The interrupted brief, then almost nothing, then this invocation.
rows.append({"type": "user", "timestamp": ts(4), "cwd": proj,
             "message": {"role": "user", "content": "<command-name>/brief</command-name>"}})
rows.append({"type": "assistant", "timestamp": ts(3), "cwd": proj,
             "message": {"content": [{"type": "text", "text": "starting"}]}})
rows.append({"type": "user", "timestamp": ts(0), "cwd": proj,
             "message": {"role": "user", "content": "<command-name>/brief</command-name>"}})
with open(os.path.join(retry, "cfg/projects/synthetic/s.jsonl"), "w", encoding="utf-8") as fh:
    for r in rows:
        fh.write(json.dumps(r) + "\n")
PY
RETRY_OUT="$(cd "$RETRY/proj" && CLAUDE_CONFIG_DIR="$RETRY/cfg" SESSION_LEDGER_BRIEF_BUDGET=40000 \
             bash "$KIT/tools/brief-digest.sh" 2>/dev/null)"
RETRY_PROBLEMS=""
case "$RETRY_OUT" in *"repeated call"*) ;; *) RETRY_PROBLEMS="$RETRY_PROBLEMS,fallback-not-announced" ;; esac
case "$RETRY_OUT" in *RETRY-TOKEN-8802*) ;; *) RETRY_PROBLEMS="$RETRY_PROBLEMS,the-nights-work-stayed-outside-the-window" ;; esac
[ -z "$RETRY_PROBLEMS" ] && RETRY_PROBLEMS="OK"
[ "$RETRY_PROBLEMS" = "OK" ] && ok "a near empty window steps back instead of reporting silence" \
                             || bad "an interrupted brief still poisons the next one" "$RETRY_PROBLEMS"

# ---------------------------------------------------------------------------
echo "probe: the grader anchors on the human turn, not on the last slash command"
# Reported from a foreign project and confirmed here: the anchor tested isinstance(content,
# str) on the assumption that a typed message is a plain string. It is the reverse. Counted
# in three real transcripts, typed messages are lists of text blocks (1478/544/152101) and
# the plain strings are command echoes and the continuation summary (27/33/5144). The window
# therefore opened at the last slash command, and tool calls from earlier work were charged
# to the answer. This plants both shapes and requires the later, typed one to win.
GRADE_LAB="$TMP/probe-anchor"
mkdir -p "$GRADE_LAB"
python3 - "$GRADE_LAB" <<'PY'
import json, os, sys
lab = sys.argv[1]
# The ORDER is the assertion. The command echo has to come first, the earlier file read
# second, the typed question third. Anchor on the echo and the read falls inside the window,
# which is the false YELLOW this fixes; anchor on the question and it does not.
rows = [
    # A plain string, and exactly what the old anchor picked as "the last human turn".
    {"type": "user", "message": {"content": "<command-name>/prove</command-name>"}},
    # Earlier work, before the question was even asked. Must not be charged to the answer.
    {"type": "assistant", "message": {"content": [
        {"type": "tool_use", "id": "t1", "name": "Read",
         "input": {"file_path": ".claude/session-ledger.md"}}]}},
    # The real question, typed, which arrives as a LIST of text blocks.
    {"type": "user", "message": {"content": [
        {"type": "text", "text": "What happened with approach RC-D1, and why?"}]}},
    # Answered from context: no tool_use at all after the human turn.
    {"type": "assistant", "message": {"content": [
        {"type": "text", "text": "RC-D1 was dropped, it needed a second roundtrip."}]}},
]
with open(os.path.join(lab, "t.jsonl"), "w", encoding="utf-8") as fh:
    for r in rows:
        fh.write(json.dumps(r) + "\n")
open(os.path.join(lab, "answer.txt"), "w", encoding="utf-8").write(
    "RC-D1 was dropped because it needed a second roundtrip.")
PY
# The probe keeps its state outside the measured project, under a slug of the working
# directory, so the fixture has to be written where the tool will look for it.
GRADE_HOME="$TMP/probe-home"
GRADE_SLUG="$(printf '%s' "$GRADE_LAB" | tr -c 'A-Za-z0-9' '-')"
mkdir -p "$GRADE_HOME/$GRADE_SLUG"
printf '%s' '[{"id":"RC-D1","q":"?","must":["roundtrip"],"class":"dropped"}]' \
  > "$GRADE_HOME/$GRADE_SLUG/recall.json"
GRADE_OUT="$(cd "$GRADE_LAB" && SESSION_LEDGER_PROBE_HOME="$GRADE_HOME" \
  bash "$KIT/tools/effect-probe.sh" recall-grade "$GRADE_LAB/answer.txt" "$GRADE_LAB/t.jsonl" 2>&1 \
  || true)"
case "$GRADE_OUT" in
  *GREEN*1*|*"GREEN 1"*) ok "the read before the question is not charged to the answer" ;;
  *) bad "the grader anchored on the wrong turn" "$(printf '%s' "$GRADE_OUT" | tail -2 | tr '\n' ' ')" ;;
esac

# ---------------------------------------------------------------------------
echo "hooks: asking for the checkpoint in words still works after a compaction"
# The skill description carries trigger phrases, and that is the friendly path. It is also
# the one piece of startup content a compaction does not restore, so from the second
# compaction of a session the phrase route is gone while the user keeps typing the same
# words. A hook is configuration and survives, so the route lives there too. Both halves are
# checked: it fires on the intent, and it stays quiet on a discussion ABOUT the checkpoint,
# because injecting "go rewrite three files now" into a design conversation is worse than
# not firing at all.
_fire_prompt() {
  printf '{"prompt":%s}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")" \
    | bash "$KIT/hooks/prompt-checkpoint.sh" 2>/dev/null
}
TRIGGER_PROBLEMS=""
for phrase in "compact vorbereiten" "prepare for compact" "kontext sichern" "run the checkpoint"; do
  [ -n "$(_fire_prompt "$phrase")" ] || TRIGGER_PROBLEMS="$TRIGGER_PROBLEMS,silent-on:$phrase"
done
for phrase in "wo stehen wir" "what happened last night" \
  "Should the checkpoint also sync the plan file, or is it enough that it writes the ledger and leaves the rest to the lint? That is a design question and must not fire anything."; do
  [ -z "$(_fire_prompt "$phrase")" ] || TRIGGER_PROBLEMS="$TRIGGER_PROBLEMS,false-positive"
done
# It must never block or rewrite the prompt: the only permitted shape is additionalContext.
FIRED="$(_fire_prompt "compact vorbereiten")"
case "$FIRED" in *additionalContext*) ;; *) TRIGGER_PROBLEMS="$TRIGGER_PROBLEMS,wrong-delivery" ;; esac
case "$FIRED" in *'"decision"'*|*'"block"'*) TRIGGER_PROBLEMS="$TRIGGER_PROBLEMS,it-blocks-the-prompt" ;; esac
# And the instruction has to name the skill file, because the case it exists for is exactly
# the one where the skill is no longer in the model's list.
case "$FIRED" in *"skills/checkpoint/SKILL.md"*) ;; *) TRIGGER_PROBLEMS="$TRIGGER_PROBLEMS,no-fallback-path" ;; esac
[ -z "$(SESSION_LEDGER_PROMPT_TRIGGER=off _fire_prompt "compact vorbereiten")" ] \
  || TRIGGER_PROBLEMS="$TRIGGER_PROBLEMS,off-switch-does-not-switch-off"
[ -z "$TRIGGER_PROBLEMS" ] && TRIGGER_PROBLEMS="OK"
[ "$TRIGGER_PROBLEMS" = "OK" ] && ok "the phrase fires a checkpoint, a discussion about it does not" \
                               || bad "the prompt trigger misjudges" "$TRIGGER_PROBLEMS"

# ---------------------------------------------------------------------------
echo "docs: every phrase the README advertises actually fires the hook"
# The list above is typed here, so it can only ever check the phrases someone thought of
# while writing the test. The phrases a READER will type are the ones printed in the README,
# and those are a different list that nobody was checking. Measured: the README promised the
# trigger worked "in any language" while the matcher held patterns for two, so a French or
# Spanish user got silence from a documented feature. The advertised phrases are therefore
# read out of the README itself, which means a new example in the docs is covered the moment
# it is written, and a phrase that is only aspirational goes red instead of shipping.
ADVERTISED="$(python3 - "$KIT" <<'PY'
import os, re, sys
kit = sys.argv[1]
text = open(os.path.join(kit, "README.md"), encoding="utf-8").read()
# The paragraph that tells the reader what to say. Bounded to it, because quoted strings
# elsewhere in the README are prose, not promises.
m = re.search(r'\*\*Or just say it\.\*\*(.+?)\n\n', text, re.S)
print("\n".join(re.findall(r'"([^"\n]+)"', m.group(1))) if m else "")
PY
)"
ADVERT_PROBLEMS=""
[ -n "$ADVERTISED" ] || ADVERT_PROBLEMS=",readme-paragraph-not-found"
printf '%s\n' "$ADVERTISED" | while IFS= read -r phrase; do
  [ -n "$phrase" ] || continue
  [ -n "$(_fire_prompt "$phrase")" ] || printf '%s' ",advertised-but-silent:$phrase"
done > "$TMP/advert.txt"
ADVERT_PROBLEMS="$ADVERT_PROBLEMS$(cat "$TMP/advert.txt")"
[ -z "$ADVERT_PROBLEMS" ] && ADVERT_PROBLEMS="OK"
[ "$ADVERT_PROBLEMS" = "OK" ] && ok "the phrases the README prints are the phrases that work" \
                              || bad "the docs advertise a trigger the hook does not have" "$ADVERT_PROBLEMS"

# ---------------------------------------------------------------------------
echo "tools: the instructions locate the scripts instead of guessing at them"
# Measured on a standalone install: the skill named tools/brief-digest.sh and mentioned
# .claude/tools/ only as an aside, so /brief opened with a wrong path error, then a search for
# the file, then the real call. Three tool calls and a permission prompt for one report. A
# guessed path is a defect of the instruction, not of the reader, so the shipped line resolves
# the install itself and this checks that it does, in a layout where only one of them exists.
#
# WHY THIS EXECUTES THE LINE INSTEAD OF GREPPING FOR IT. The previous version demanded the
# substring CLAUDE_PLUGIN_ROOT in all three files and then ran the line in two layouts, both
# of which exist only inside this checkout. Both halves were wrong at once. That variable is
# substituted for HOOK commands; it is empty in a Bash call the model makes, so the plugin
# branch of the line could never resolve, and the assertion pinned the defect in place rather
# than catching it. Measured in a foreign project on 2026-08-15 and again on 2026-08-16: the
# line picked the project's own tools/ and the call exited 127, both times, and the model
# rescued itself by hand with the cache path. So the line is now taken out of each shipped
# file and executed, in four layouts. Two of them are the ones that were failing in the field:
# `plugin` is what a stranger gets, and `partial` is half a copy.
RESOLVE_PROBLEMS=""
# A cache that looks like the real one. CLAUDE_CONFIG_DIR points the shipped line at it, the
# same lever the degradation check further down uses.
PLUGCFG="$TMP/resolve-plugincache"
PLUGTOOLS="$PLUGCFG/plugins/cache/context-kit/context-kit/1.0.0/tools"
mkdir -p "$PLUGTOOLS"
printf 'echo REACHED\n' > "$PLUGTOOLS/brief-digest.sh"
printf 'echo REACHED\n' > "$PLUGTOOLS/effect-probe.sh"
EMPTYCFG="$TMP/resolve-nocache"; mkdir -p "$EMPTYCFG"
for f in skills/brief/SKILL.md commands/brief.md commands/prove.md; do
  case "$f" in
    *prove*) SCRIPT="effect-probe.sh"; OTHER="brief-digest.sh"; TAIL='; bash "$P"' ;;
    *)       SCRIPT="brief-digest.sh"; OTHER="effect-probe.sh"; TAIL='' ;;
  esac
  # A bare relative call is what sent the model down the wrong path in the first place.
  grep -qE 'bash (tools|\.claude/tools)/(brief-digest|effect-probe)\.sh' "$KIT/$f" \
    && RESOLVE_PROBLEMS="$RESOLVE_PROBLEMS,$f-still-names-a-bare-path"
  # Matched by shape, not by wording, so a rewrite of the line does not silently stop being
  # tested: an assignment or a loop, on one line, naming the script.
  LINE="$(grep -h -m1 -E "^[[:space:]]*.?(T=|P=|for d in).*$SCRIPT" "$KIT/$f" \
          | sed -e 's/^[[:space:]]*//' -e 's/^`//' -e 's/`$//' -e 's/\$ARGUMENTS//')"
  if [ -z "$LINE" ]; then
    RESOLVE_PROBLEMS="$RESOLVE_PROBLEMS,$f-has-no-resolver-line"
    continue
  fi
  for layout in standalone delivery plugin partial; do
    LAB="$TMP/resolve-$(printf '%s' "$f" | tr '/.' '--')-$layout"; rm -rf "$LAB"; mkdir -p "$LAB"
    CFG="$EMPTYCFG"
    case "$layout" in
      standalone) mkdir -p "$LAB/.claude/tools"; printf 'echo REACHED\n' > "$LAB/.claude/tools/$SCRIPT" ;;
      delivery)   mkdir -p "$LAB/tools";         printf 'echo REACHED\n' > "$LAB/tools/$SCRIPT" ;;
      # What a stranger gets: nothing of the kit in the project, the kit in a plugin cache, and
      # a tools/ directory that belongs to the project. This is the measured failure.
      plugin)     mkdir -p "$LAB/tools"; printf 'x = 1\n' > "$LAB/tools/unrelated.py"; CFG="$PLUGCFG" ;;
      # Half a copy: .claude/tools exists and holds the OTHER script. Also measured, in the
      # same project, after someone copied one file by hand to make the line work once.
      partial)    mkdir -p "$LAB/.claude/tools"; printf 'echo WRONG\n' > "$LAB/.claude/tools/$OTHER"; CFG="$PLUGCFG" ;;
    esac
    # Separated by ";" and not by "&&" on purpose: a resolver that probes for paths reports a
    # non zero status for the ones that do not exist, and under `set -o pipefail` that status
    # is the pipeline's. Chaining on it would test this suite's shell options, not the line.
    GOT="$(cd "$LAB"; CLAUDE_CONFIG_DIR="$CFG"; export CLAUDE_CONFIG_DIR; eval "$LINE$TAIL" 2>/dev/null)"
    [ "$GOT" = "REACHED" ] || RESOLVE_PROBLEMS="$RESOLVE_PROBLEMS,$f-$layout-not-resolved"
  done
done
[ -z "$RESOLVE_PROBLEMS" ] && RESOLVE_PROBLEMS="OK"
[ "$RESOLVE_PROBLEMS" = "OK" ] && ok "the documented line finds the scripts on every install path" \
                               || bad "an instruction still guesses where the tools live" "$RESOLVE_PROBLEMS"

# ---------------------------------------------------------------------------
echo "settings: no denial of a key that exists, and the switch names its cost"
# Two separate defects lived in the same sentence, in the files that teach the method.
# (1) Three places said `autoCompactEnabled` is not a real key and is silently ignored.
# Measured with `strings` on the installed binary: the schema carries it as an optional
# boolean, and the resolution is `if (DISABLE_AUTO_COMPACT) return false; return
# autoCompactEnabled ?? true`. The recommendation was right, the reason was invented, and an
# invented reason is what a reader repeats.
# (2) The kit asks you to switch off the harness's own net for a full window and used to say
# nothing about what that costs, while its own replacement net ships off. A switch whose
# downside is undocumented is a trap for the person who trusts the document.
AC_PROBLEMS=""
# Self-probe first. A grep that errors out prints nothing and reads exactly like a clean
# result, so both patterns are fired at a sentence they MUST match before they are trusted
# on real files. Not hypothetical: the first version of the second pattern used a repetition
# of 1200, which BSD grep refuses past 255, and the check went green while measuring nothing.
printf 'the autoCompactEnabled key does not exist in the schema' \
  | grep -qiE "autoCompactEnabled.{0,140}(does not exist|is not a real|not a real settings key|silently ignored)" \
  || AC_PROBLEMS="$AC_PROBLEMS,denial-pattern-does-not-match-a-known-denial"
printf 'a session that misses its cue runs into the wall' \
  | grep -qiE "runs into (a|the) (wall|full window)|net removed|no substitute" \
  || AC_PROBLEMS="$AC_PROBLEMS,cost-pattern-does-not-match-a-known-cost-sentence"
for f in settings-snippet.json skills/checkpoint/SKILL.md skills/session-ledger/SKILL.md \
         commands/checkpoint.md README.md GUIDE.md CLAUDE.example.md; do
  [ -f "$KIT/$f" ] || continue
  # Newlines folded, because in settings-snippet.json the claim is split across two array
  # entries and a line-wise grep walks straight past it.
  BLOB="$(tr '\n' ' ' < "$KIT/$f")"
  printf '%s' "$BLOB" \
    | grep -qiE "autoCompactEnabled.{0,140}(does not exist|is not a real|not a real settings key|silently ignored)" \
    && AC_PROBLEMS="$AC_PROBLEMS,$f-denies-a-key-that-exists"
  case "$f" in
    settings-snippet.json|skills/checkpoint/SKILL.md)
      printf '%s' "$BLOB" | grep -q "DISABLE_AUTO_COMPACT" || continue
      # Presence in the file, not proximity to the switch: BSD grep caps a repetition at 255,
      # so the window that would express "near it" cannot be written portably. Found that the
      # honest way, by writing `.{0,1200}` first and watching grep error out into a green.
      printf '%s' "$BLOB" \
        | grep -qiE "runs into (a|the) (wall|full window)|net removed|no substitute" \
        || AC_PROBLEMS="$AC_PROBLEMS,$f-recommends-the-switch-without-its-cost" ;;
  esac
done
[ -z "$AC_PROBLEMS" ] && AC_PROBLEMS="OK"
[ "$AC_PROBLEMS" = "OK" ] && ok "auto-compaction is described as it actually resolves" \
                          || bad "the kit states something about settings that is not true" "$AC_PROBLEMS"

# ---------------------------------------------------------------------------
echo "install: the printed blocks warn, install and uninstall when actually run"
# The install block used to be five `cp -R` lines, which overwrite a file of the same name
# without a word, and the names this kit claims are brief, checkpoint, prove and
# session-ledger. Nothing in README or GUIDE mentioned collisions, backups or removal.
# This runs the blocks as printed, in a project that owns one of those names, because a
# documented command that nobody executes is exactly the class of defect being fixed here.
# It also caught two real ones on the first run: `cp -R hooks/.` carried hooks.json, which
# belongs to the plugin wiring, and the uninstall then left it behind.
INST_PROBLEMS=""
_readme_block() {  # first fenced bash block whose body matches $1
  awk -v pat="$1" 'BEGIN{RS="```"} /^bash/ && $0 ~ pat {print substr($0,6); exit}' "$KIT/README.md"
}
CHECK_B="$(_readme_block 'WOULD OVERWRITE'          | sed "s|KIT=path/to/context-kit|KIT=$KIT|")"
INST_B="$( _readme_block 'kit-manifest .claude/'    | sed "s|KIT=path/to/context-kit|KIT=$KIT|")"
UNINST_B="$(_readme_block 'ledger-lint-state'       | sed "s|KIT=path/to/context-kit|KIT=$KIT|")"
for pair in "collision-check:$CHECK_B" "install:$INST_B" "uninstall:$UNINST_B"; do
  [ -n "${pair#*:}" ] || INST_PROBLEMS="$INST_PROBLEMS,${pair%%:*}-block-not-in-readme"
done
if [ -n "$CHECK_B" ] && [ -n "$INST_B" ] && [ -n "$UNINST_B" ]; then
  # A project that already owns one of the names the kit claims.
  LABA="$TMP/install-collide"; rm -rf "$LABA"; mkdir -p "$LABA/.claude/commands"
  printf 'mine\n' > "$LABA/.claude/commands/brief.md"
  WARN="$(cd "$LABA" && KIT="$KIT" bash -c "$CHECK_B" 2>&1)"
  printf '%s' "$WARN" | grep -q 'commands/brief.md' \
    || INST_PROBLEMS="$INST_PROBLEMS,check-does-not-name-the-collision"

  # A project with no collision: install, then uninstall, and see what survives either way.
  LABB="$TMP/install-clean"; rm -rf "$LABB"; mkdir -p "$LABB/.claude/hooks"
  printf 'mine\n' > "$LABB/.claude/hooks/my-own.sh"
  QUIET="$(cd "$LABB" && KIT="$KIT" bash -c "$CHECK_B" 2>&1)"
  [ -z "$QUIET" ] || INST_PROBLEMS="$INST_PROBLEMS,check-warns-about-nothing"
  ( cd "$LABB" && KIT="$KIT" bash -c "$INST_B" ) >/dev/null 2>&1
  [ -f "$LABB/.claude/hooks/ledger-lint.sh" ]  || INST_PROBLEMS="$INST_PROBLEMS,install-left-out-a-hook"
  [ -f "$LABB/.claude/tools/brief-digest.sh" ] || INST_PROBLEMS="$INST_PROBLEMS,install-left-out-a-tool"
  [ -f "$LABB/.claude/.kit-manifest" ]         || INST_PROBLEMS="$INST_PROBLEMS,install-left-out-the-manifest"
  [ -x "$LABB/.claude/hooks/ledger-lint.sh" ]  || INST_PROBLEMS="$INST_PROBLEMS,install-did-not-set-the-mode"
  # hooks.json is the plugin wiring and has no meaning in a standalone install.
  [ -f "$LABB/.claude/hooks/hooks.json" ]      && INST_PROBLEMS="$INST_PROBLEMS,install-copied-the-plugin-wiring"
  # The mode glob would have caught this file too.
  [ -x "$LABB/.claude/hooks/my-own.sh" ]       && INST_PROBLEMS="$INST_PROBLEMS,install-chmodded-a-foreign-script"
  if command -v python3 >/dev/null 2>&1; then
    ( cd "$LABB" && python3 .claude/hooks/kit_integrity.py .claude >/dev/null 2>&1 )
    [ $? -eq 0 ] || INST_PROBLEMS="$INST_PROBLEMS,fresh-install-does-not-match-its-own-manifest"
  fi
  ( cd "$LABB" && KIT="$KIT" bash -c "$UNINST_B" ) >/dev/null 2>&1
  LEFT="$(cd "$LABB" && find .claude -type f | sed 's|^\./||' | grep -v 'my-own.sh' || true)"
  [ -z "$LEFT" ] || INST_PROBLEMS="$INST_PROBLEMS,uninstall-left-$(printf '%s' "$LEFT" | tr '\n' '+' | tr -d ' ')"
  [ -f "$LABB/.claude/hooks/my-own.sh" ] || INST_PROBLEMS="$INST_PROBLEMS,uninstall-removed-a-foreign-file"
fi
[ -z "$INST_PROBLEMS" ] && INST_PROBLEMS="OK"
[ "$INST_PROBLEMS" = "OK" ] && ok "install and uninstall do what the README says they do" \
                            || bad "the documented install is not what actually happens" "$INST_PROBLEMS"

# ---------------------------------------------------------------------------
echo "brief: without python3 it says so, instead of reporting a quiet nothing"
# The kit's standing rule for degradation. Without python3 the transcript half is
# unreachable, and a digest that then prints an empty but well formed report would read as
# "nothing happened" when the truth is "nothing was looked at".
# The fake python3 EXISTS and fails, which is the harder case: a presence check on PATH would
# wave it through, every extraction would then return nothing, and the digest would print a
# well formed empty report. That was the first implementation, and this assertion changed it.
DEG_BIN="$TMP/brief-nopy"; mkdir -p "$DEG_BIN"
printf '#!/bin/sh\nexit 127\n' > "$DEG_BIN/python3"; chmod +x "$DEG_BIN/python3"
DEG_OUT="$(cd "$PROBE/proj" && PATH="$DEG_BIN:$PATH" CLAUDE_CONFIG_DIR="$PROBE/cfg" \
           bash "$KIT/tools/brief-digest.sh" 2>/dev/null)"
DEG_PROBLEMS=""
printf '%s' "$DEG_OUT" | grep -q "INCOMPLETE" || DEG_PROBLEMS="$DEG_PROBLEMS,no-incomplete-marker"
printf '%s' "$DEG_OUT" | grep -qi "python3"   || DEG_PROBLEMS="$DEG_PROBLEMS,does-not-name-the-cause"
[ -n "$DEG_OUT" ]                             || DEG_PROBLEMS="$DEG_PROBLEMS,said-nothing-at-all"
[ -z "$DEG_PROBLEMS" ] && DEG_PROBLEMS="OK"
[ "$DEG_PROBLEMS" = "OK" ] && ok "with a broken python3 the digest declares itself incomplete" \
                           || bad "the digest degraded silently" "$DEG_PROBLEMS"

# ---------------------------------------------------------------------------
echo "brief: skill and command agree on the blocks, and on their order"
# Two files drive the same output: the skill when the intent is recognised, the command file
# when the slash command is typed. The carrier defect was exactly this shape, an enumeration
# that fell out of step between skill and command, so the check is generalised here rather
# than repeated by hand.
BLOCK_PROBLEMS="$(python3 - "$KIT" <<'PY'
import os, sys
kit = sys.argv[1]
order = ["\U0001F7E2", "\U0001F7E1", "\U0001F534", "\U0001F4A1", "⚠", "➡"]
names = ["Progress", "In progress", "Blocked", "Learned", "Open problems", "Next"]
bad = []
for rel in ("skills/brief/SKILL.md", "commands/brief.md"):
    text = open(os.path.join(kit, rel), encoding="utf-8").read()
    seen = [text.find(e) for e in order]
    if -1 in seen:
        bad.append("%s-misses-%s" % (os.path.basename(rel), names[seen.index(-1)].replace(" ", "-")))
        continue
    if seen != sorted(seen):
        bad.append("%s-lists-the-blocks-out-of-order" % os.path.basename(rel))
    for n in names:
        if n.lower() not in text.lower():
            bad.append("%s-misses-name-%s" % (os.path.basename(rel), n.replace(" ", "-")))
    # The rule that a ticket or PR number never stands in for what the change does. Both files
    # have to carry it, for the same reason the blocks do: whichever one drives the run is the
    # one that decides. Observed in a real briefing, where four of five finished items were
    # reported as numbers, so the reader had to leave the report to learn what happened.
    if "identifier stand in" not in text:
        bad.append("%s-misses-the-identifier-rule" % os.path.basename(rel))
print(",".join(bad) if bad else "OK")
PY
)"
[ "$BLOCK_PROBLEMS" = "OK" ] && ok "both files that drive the briefing carry the same six blocks in the same order" \
                             || bad "skill and command disagree about the briefing" "$BLOCK_PROBLEMS"

# ---------------------------------------------------------------------------
echo "ledger: the hook and the skill agree on what makes the model write"
# Same shape of defect as the briefing blocks, and it happened while NEXT was demoted to a
# ride-along: the primed protocol had already dropped TASK as a trigger while the skill still
# listed it, so the two documents asked for different behaviour. It is not cosmetic. The hook
# is what the model sees unprompted at every session start, the skill is what it reads when it
# looks closer, and a section that is a trigger in one and not the other gets written on
# nobody's schedule.
APPEND_PROBLEMS="$(python3 - "$KIT" <<'PY'
import os, re, sys
kit = sys.argv[1]
bad = []
TRIGGERS = ("DECIDED", "VERIFIED", "OPEN", "DROPPED", "TASK")

# The hook side names its sections literally, so it can be read literally. Mentioning a
# section is not enough, though: the first cut of this check only asked whether TASK appeared
# somewhere in the protocol, and it stayed green against a protocol that had moved TASK into
# the ride-along clause. So the two clauses are separated and read against each other.
hook = open(os.path.join(kit, "hooks/session-start-prime.sh"), encoding="utf-8").read()
proto = " ".join(re.findall(r'^_add "(.*)"$', hook, re.M))
MARKER = "Append only on an event:"
sentences = re.split(r"(?<=\.)\s+", proto)
ride = [s for s in sentences if re.search(r"\brides? along\b", s)]
events = [s for s in sentences if MARKER in s]
if not ride:
    bad.append("hook-does-not-mark-NEXT-as-ride-along")
elif not events:
    bad.append("hook-has-no-event-list")
elif ride[0] is events[0]:
    # One sentence carrying both is not a wording preference, it is unreadable as a rule:
    # nothing then says whether a section named in it is a trigger or a passenger.
    bad.append("hook-runs-the-event-list-and-the-ride-along-clause-together")
else:
    listed = events[0][events[0].index(MARKER) + len(MARKER):]
    for s in TRIGGERS:
        if s not in listed:
            bad.append("hook-drops-trigger-%s" % s)
        if s in ride[0]:
            bad.append("hook-demotes-%s-to-ride-along" % s)
    if "NEXT" not in ride[0]:
        bad.append("hook-ride-along-clause-does-not-name-NEXT")
    if "NEXT" in listed:
        bad.append("hook-still-lists-NEXT-as-a-trigger")

# The skill side writes its triggers as prose bullets, so the invariant it can carry is the
# split itself: TASK is a bullet, NEXT is not one anywhere, and NEXT is named as riding along.
skill = open(os.path.join(kit, "skills/session-ledger/SKILL.md"), encoding="utf-8").read()
m = re.search(r"^## When to append$(.*?)^## ", skill, re.M | re.S)
if not m:
    bad.append("skill-has-no-when-to-append-section")
else:
    body = m.group(1)
    bullets = "\n".join(l for l in body.splitlines() if l.startswith("- "))
    if "TASK" not in bullets:
        bad.append("skill-drops-TASK-as-a-trigger")
    if "NEXT" in bullets:
        bad.append("skill-still-lists-NEXT-as-a-trigger")
    if "rides along" not in body:
        bad.append("skill-does-not-mark-NEXT-as-ride-along")
print(",".join(bad) if bad else "OK")
PY
)"
[ "$APPEND_PROBLEMS" = "OK" ] && ok "hook and skill name the same append triggers, with NEXT riding along" \
                              || bad "the two documents ask for different write behaviour" "$APPEND_PROBLEMS"

# ---------------------------------------------------------------------------
echo "install: the two CLAUDE.md blocks exist once, and the README quotes them exactly"
# The kit tells other people not to keep an unwatched second copy of anything, so it may not
# keep one itself. The blocks live in CLAUDE.example.md; the README shows the same text so a
# reader can copy it without opening a second file. That is a duplicate, therefore it gets a
# watcher instead of a promise. Both pieces are load bearing: without the canary line the
# model never learns to fall back to the file when a hook loses its race, and without the
# PLAN line it declines instead of reading the project state.
BLOCKS_PROBLEMS="$(python3 - "$KIT" <<'PY'
import os, re, sys
kit = sys.argv[1]
bad = []
path = os.path.join(kit, "CLAUDE.example.md")
if not os.path.exists(path):
    print("example-file-missing"); raise SystemExit
example = open(path, encoding="utf-8").read().strip()
for needle, label in (("CTX-LEDGER-RESTORED", "canary-line"),
                      ("`PLAN`", "project-state-pointer"),
                      ("# Compact instructions", "compact-instructions")):
    if needle not in example:
        bad.append("example-misses-" + label)
readme = open(os.path.join(kit, "README.md"), encoding="utf-8").read()
quoted = [b.strip() for b in re.findall(r"```markdown\n(.*?)```", readme, re.S)]
body = example.split("-->", 1)[-1].strip()
if not any(q == body for q in quoted):
    bad.append("readme-quote-differs-from-the-example-file")
# Nothing in this kit may hand a reader a line that replaces a CLAUDE.md they already have.
# That file carries their own rules; this only adds two blocks to it. So every instruction
# about it has to append, and a single redirect or a copy over it is a defect.
for text, where in ((readme, "readme"), (example, "example")):
    for m in re.findall(r"^.*CLAUDE\.md.*$", text, re.M):
        if re.search(r">\s*CLAUDE\.md", m) and ">>" not in m:
            bad.append("%s-truncates-an-existing-CLAUDE.md" % where)
        if re.search(r"\b(cp|mv)\b[^\n]*\bCLAUDE\.md\b", m):
            bad.append("%s-overwrites-an-existing-CLAUDE.md" % where)
print(",".join(bad) if bad else "OK")
PY
)"
[ "$BLOCKS_PROBLEMS" = "OK" ] && ok "the CLAUDE.md blocks are one text, and the README copy still matches it" \
                              || bad "the instruction blocks drifted" "$BLOCKS_PROBLEMS"

# ---------------------------------------------------------------------------
echo "probe: the answer key must not be readable inside the project it measures"
# The defect this locks down was found in a live run, not by reading. The probe kept its
# state in .claude/.effect-probe, inside the project. The checkpoint's job is to inventory
# every durable store it can find, so it found recall.json, read the questions and the
# required keywords, and wrote "answer the kit's recall probe" into NEXT. The following
# measurement was then taken from a model that knew the answers and knew it was being
# tested. Ten earlier passes never surfaced it, because none of them inventoried that
# thoroughly. So: after planting, nothing under the project may carry a question or a
# keyword. Only the planted ledger lines may mention the token at all.
PLAB="$TMP/probe-isolation"
rm -rf "$PLAB"; mkdir -p "$PLAB/.claude"
printf '# Session Ledger\n\n## TASK\nX\n\n## NEXT\nY\n\n## OPEN\n\n## DECIDED\n\n## VERIFIED\n\n## DROPPED\n\n## PLAN\n' \
  > "$PLAB/.claude/session-ledger.md"
PROBE_HOME="$TMP/probe-home"
(cd "$PLAB" && SESSION_LEDGER_PROBE_HOME="$PROBE_HOME" \
   bash "$KIT/tools/effect-probe.sh" recall-plant >/dev/null 2>&1)
ISO_PROBLEMS="$(python3 - "$PLAB" "$PROBE_HOME" <<'PY'
import os, sys
proj, home = sys.argv[1], sys.argv[2]
bad = []
# The answer key has to exist somewhere, or the probe cannot grade later.
if not os.path.isdir(home) or not os.listdir(home):
    bad.append("state-was-not-written-outside-at-all")
# and it must not be reachable from inside the project.
leak = ["What happened with approach", '"must"', "class\": \"dropped\""]
for root, dirs, files in os.walk(proj):
    for f in files:
        p = os.path.join(root, f)
        try:
            text = open(p, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for needle in leak:
            if needle in text:
                bad.append("leaks-into-project:%s" % os.path.relpath(p, proj))
                break
print(",".join(sorted(set(bad))) if bad else "OK")
PY
)"
[ "$ISO_PROBLEMS" = "OK" ] && ok "the probe keeps its questions and keywords out of the measured project" \
                          || bad "the probe can be read by what it measures" "$ISO_PROBLEMS"

# ---------------------------------------------------------------------------
echo "install: the standalone recipe copies every directory a command reaches into"
# Found by a user typing the command and getting "No matching commands". Two defects at once,
# both invisible from inside a working checkout. The recipe never copied tools/, while two
# commands call into .claude/tools/, so /prove and /brief were broken on that path from the
# day they shipped. And nothing told the reader that skill and command directories are read
# at startup, so a fresh install looks broken until /reload-skills runs. A recipe is only
# right if following it literally produces a working install.
#
# It used to read the recipe and look for `mkdir .claude/<dir>` and `cp -R <dir>/.`, which
# tied the check to one wording: rewriting the recipe into a derived file list broke the
# assertion while the recipe itself got better. So it now RUNS the block and looks at the
# directories that exist afterwards. Same question, no opinion about how it is written.
# Matched positively, on a token the block must contain, and not by testing the variable for
# emptiness: an extractor that breaks returns nothing, and "nothing" must not be the shape
# that passes. Same rule the meta check at the end of this file enforces.
RECIPE_B="$(_readme_block 'kit-manifest .claude/' | sed "s|KIT=path/to/context-kit|KIT=$KIT|")"
case "$RECIPE_B" in
  *.kit-manifest*) HAVE_RECIPE=yes ;;
  *)               HAVE_RECIPE=no ;;
esac
if [ "$HAVE_RECIPE" = "no" ]; then
  INSTALL_PROBLEMS="recipe-block-not-in-readme"
else
  LABR="$TMP/recipe-lab"; rm -rf "$LABR"; mkdir -p "$LABR"
  ( cd "$LABR" && KIT="$KIT" bash -c "$RECIPE_B" ) >/dev/null 2>&1
  INSTALL_PROBLEMS="$(python3 - "$KIT" "$LABR" <<'PY'
import os, re, sys
kit, lab = sys.argv[1], sys.argv[2]
readme = open(os.path.join(kit, "README.md"), encoding="utf-8").read()
bad = []
# Every .claude/<dir> a delivered command or skill reaches into has to exist AND hold files
# after the recipe ran, or the recipe hands the reader a broken install. The trailing class
# is deliberately wide: a path can appear as .claude/tools/x, "\.claude/tools" or bare.
wanted = set()
for sub in ("commands", "skills"):
    base = os.path.join(kit, sub)
    for root, _, files in os.walk(base):
        for f in files:
            if not f.endswith(".md"):
                continue
            text = open(os.path.join(root, f), encoding="utf-8").read()
            wanted |= set(re.findall(r'\.claude/([a-z][a-z0-9-]*)(?:[/"\s]|$)', text))
for d in sorted(wanted):
    p = os.path.join(lab, ".claude", d)
    if not os.path.isdir(p):
        bad.append("recipe-never-creates:%s" % d)
    elif not os.listdir(p):
        bad.append("recipe-never-fills:%s" % d)
if "/reload-skills" not in readme:
    bad.append("recipe-never-says-how-to-load-the-commands")
print(",".join(sorted(set(bad))) if bad else "OK")
PY
)"
fi
[ "$INSTALL_PROBLEMS" = "OK" ] && ok "following the standalone recipe literally yields a working install" \
                              || bad "the standalone recipe is incomplete" "$INSTALL_PROBLEMS"

# ---------------------------------------------------------------------------
echo "integrity: an installation that has fallen behind says so, a healthy one stays quiet"
# The defect this answers was measured, not imagined: one project ran a generation old for
# weeks, missing an entire hook file and holding three command files from before a language
# decision, and nothing anywhere reported it. sync.sh cannot see that, because a foreign
# install has no delivery next to it, so the comparison has to travel with the install.
# All four states are exercised, because three of them are ways to be wrong quietly: a clean
# install that cries wolf trains the reader to ignore the report, and an adopted file that
# keeps being reported does the same.
LAB_I="$TMP/labint"
rm -rf "$LAB_I"; mkdir -p "$LAB_I/.claude"
cp -R "$KIT/hooks" "$KIT/skills" "$KIT/commands" "$KIT/tools" "$LAB_I/.claude/" 2>/dev/null
rm -f "$LAB_I/.claude/hooks/hooks.json"
cp "$KIT/.kit-manifest" "$LAB_I/.claude/.kit-manifest" 2>/dev/null
_integrity_says() {   # -> the integrity report, or empty when the hook stayed quiet
  (cd "$LAB_I" && echo '{"source":"startup","session_id":"SI"}' \
    | bash .claude/hooks/session-start-prime.sh 2>/dev/null) \
    | python3 -c 'import json,sys
try:
    t = json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]
except Exception:
    sys.exit(0)
i = t.find("# Kit integrity")
sys.stdout.write(t[i:] if i >= 0 else "")' 2>/dev/null
}
INT_PROBLEMS=""
# The manifest has to cover every delivered file. It is generated, so this is really a check
# on the generator: a file the manifest never mentions is a file that can rot unwatched, and
# that is precisely the hardcoded-list defect that already bit sync.sh once.
DELIVERED="$(cd "$KIT" && find hooks skills commands tools -type f ! -name hooks.json ! -name '.DS_Store' 2>/dev/null | sort)"
LISTED="$(grep -v '^#' "$KIT/.kit-manifest" 2>/dev/null | awk '{print $2}' | sort)"
[ "$DELIVERED" = "$LISTED" ] || INT_PROBLEMS="$INT_PROBLEMS,manifest-does-not-cover-the-delivery"
[ -n "$(_integrity_says)" ] && INT_PROBLEMS="$INT_PROBLEMS,healthy-install-reports-drift"
rm -f "$LAB_I/.claude/hooks/prompt-checkpoint.sh"
printf '\nlocally changed\n' >> "$LAB_I/.claude/commands/brief.md"
REPORT="$(_integrity_says)"
case "$REPORT" in *"hooks/prompt-checkpoint.sh"*) ;; *) INT_PROBLEMS="$INT_PROBLEMS,missing-file-not-reported" ;; esac
case "$REPORT" in *"commands/brief.md"*) ;; *) INT_PROBLEMS="$INT_PROBLEMS,changed-file-not-reported" ;; esac
# Adoption is what keeps a deliberate local change from becoming a permanent false alarm.
printf 'commands/brief.md  # kept on purpose\n' > "$LAB_I/.claude/.kit-adopted"
REPORT="$(_integrity_says)"
case "$REPORT" in *"commands/brief.md"*) INT_PROBLEMS="$INT_PROBLEMS,adopted-file-still-reported" ;; esac
case "$REPORT" in *"hooks/prompt-checkpoint.sh"*) ;; *) INT_PROBLEMS="$INT_PROBLEMS,adoption-silences-everything" ;; esac
INT_PROBLEMS="${INT_PROBLEMS#,}"
[ -z "$INT_PROBLEMS" ] && INT_PROBLEMS="OK"
[ "$INT_PROBLEMS" = "OK" ] && ok "drift is reported, adoption silences only what was adopted" \
                           || bad "the integrity check misjudges an installation" "$INT_PROBLEMS"

# ---------------------------------------------------------------------------
echo "integrity: a stale manifest is caught, and the recipe carries it to a foreign install"
# Two ways this whole mechanism can be quietly useless. A manifest that is not regenerated
# reports drift on a healthy install, which is worse than no check at all. And a manifest
# that the standalone recipe never copies means every foreign install, which is the only
# place the check matters, silently cannot check at all.
MAN_PROBLEMS=""
LAB_M="$TMP/labman"; rm -rf "$LAB_M"; mkdir -p "$LAB_M"
cp -R "$KIT/hooks" "$KIT/skills" "$KIT/commands" "$KIT/tools" "$KIT/sync.sh" "$KIT/.kit-manifest" "$LAB_M/" 2>/dev/null
mkdir -p "$LAB_M/.claude"; cp -R "$KIT/.claude/hooks" "$KIT/.claude/skills" "$KIT/.claude/commands" "$KIT/.claude/tools" "$LAB_M/.claude/" 2>/dev/null
cp "$KIT/.kit-manifest" "$LAB_M/.claude/.kit-manifest" 2>/dev/null
(cd "$LAB_M" && bash sync.sh --check >/dev/null 2>&1) || MAN_PROBLEMS="$MAN_PROBLEMS,check-red-on-a-clean-copy"
# The edit goes into BOTH copies on purpose. Changing only the delivery would leave the file
# comparison red as well, and then this would pass while measuring nothing about the manifest:
# the first cut of this check did exactly that. With the two copies equal, a stale manifest is
# the only thing left that can turn it red.
printf '\n# an edit synced by hand, manifest not regenerated\n' >> "$LAB_M/hooks/ledger-lint.sh"
cp "$LAB_M/hooks/ledger-lint.sh" "$LAB_M/.claude/hooks/ledger-lint.sh"
(cd "$LAB_M" && bash sync.sh --check >/dev/null 2>&1) && MAN_PROBLEMS="$MAN_PROBLEMS,stale-manifest-passes-check"
grep -q 'kit-manifest' "$KIT/README.md" || MAN_PROBLEMS="$MAN_PROBLEMS,recipe-never-copies-the-manifest"
MAN_PROBLEMS="${MAN_PROBLEMS#,}"
[ -z "$MAN_PROBLEMS" ] && MAN_PROBLEMS="OK"
[ "$MAN_PROBLEMS" = "OK" ] && ok "a stale manifest goes red and the recipe ships the manifest" \
                           || bad "the manifest can be stale or absent unnoticed" "$MAN_PROBLEMS"

# ---------------------------------------------------------------------------
echo "plan: the size discipline reaches both files that drive the checkpoint"
# A plan is the most expensive file the checkpoint touches: measured in one real project, a
# single plan document had grown to 116000 characters, about 29000 tokens, and there were
# fourteen of them. Syncing one costs more window than the whole kit. The rule that keeps it
# affordable (spine, evidence, archive, and carried out means gone) has to be in the command
# file too, because that is what runs when the slash command is typed. This is the same
# defect shape as the carrier enumeration, which fell out of step exactly this way.
PLAN_PROBLEMS="$(python3 - "$KIT" <<'PY'
import os, sys
kit = sys.argv[1]
need = {"spine": ("spine",), "archive": ("archive",), "evidence": ("evidence",),
        "the carried-out rule": ("carried out means gone",)}
bad = []
for rel in ("skills/checkpoint/SKILL.md", "commands/checkpoint.md"):
    text = open(os.path.join(kit, rel), encoding="utf-8").read().lower()
    for label, forms in need.items():
        if not any(f in text for f in forms):
            bad.append("%s-misses-%s" % (os.path.basename(rel), label.replace(" ", "-")))
print(",".join(bad) if bad else "OK")
PY
)"
[ "$PLAN_PROBLEMS" = "OK" ] && ok "both files that drive the checkpoint carry the plan size discipline" \
                            || bad "the plan discipline is stated in only one place" "$PLAN_PROBLEMS"

# ---------------------------------------------------------------------------
echo "meta: a checker that crashes must go red, not silently green"
# The failure mode this suite is most exposed to is its own: a check that reports problems
# as text and is asserted with [ -z "$VAR" ] passes when the checker dies, because a dead
# checker prints nothing. Measured: a deliberate syntax error inside one block left the run
# at 40 green while that block measured nothing at all. So every captured checker must say
# OK out loud, and this rule reads the file to make sure the next one does too, including
# itself.
META="$(python3 - "$KIT" <<'PY'
import re, sys, os
src = open(os.path.join(sys.argv[1], "tests/run.sh"), encoding="utf-8").read()
bad = []
# Only one pattern is dangerous: a value produced by a command, then asserted by being
# EMPTY. A checker that dies produces exactly that. Checkers asserted positively (grep for
# a token, compare to a value) already go red when they die, so they are left alone.
for var in set(re.findall(r'^([A-Z_]+)="\$\(', src, re.M)):
    if '[ -z "$%s" ]' % var in src:
        bad.append("emptiness-means-pass:" + var)
print(",".join(bad) if bad else "OK")
PY
)"
[ "$META" = "OK" ] && ok "every captured checker proves it ran, instead of proving nothing" \
                   || bad "an assertion can pass without measuring" "$META"

# ---------------------------------------------------------------------------
echo "shell: every shipped shell file parses under bash 3.2 (the macOS default)"
# Tools are in scope too, not only hooks: a tool that fails to parse is a command the user
# types and gets nothing back from, which looks exactly like a quiet day.
for f in "$KIT"/hooks/*.sh "$KIT"/tools/*.sh; do
  bash -n "$f" 2>/dev/null || bad "syntax" "$(basename "$f") does not parse"
done
ok "all hooks and tools parse"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
