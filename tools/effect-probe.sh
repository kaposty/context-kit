#!/usr/bin/env bash
# effect-probe.sh: does this kit actually rescue reasoning, or do the hooks merely fire?
#
# THE GAP THIS CLOSES. Everything else here proves MECHANISM: the hook log shows a hook ran,
# the renderer shows which sections it emitted, the test suite shows the pieces behave. None
# of that proves EFFECT, that a path the session abandoned is not proposed again after a
# compaction. That is the whole claim of the kit, and firing is not effect. Treating one as
# the other is the proxy trap this kit exists to fight.
#
# The probe plants a fact nobody could know without the ledger, then makes the model answer
# for it after a real compaction. The expected answer lives OUTSIDE the ledger and outside
# the context, so the check cannot be passed by guessing or by self-grading.
#
# Usage, from the project root of an installed kit:
#   effect-probe.sh plant                    before /checkpoint and /compact
#   effect-probe.sh verify                   mechanical half: what would a restore deliver?
#   effect-probe.sh ask                      the question to put to the model after /compact
#   effect-probe.sh grade "<the answer>"     compares against the stored expectation
#
# Wider measurement, one item per reasoning section instead of a single token:
#   effect-probe.sh recall-plant                       plants a dropped, a decided, a verified
#   effect-probe.sh recall-ask                         the three questions to put after /compact
#   effect-probe.sh recall-grade <answers> <transcript>  grades each GREEN / YELLOW / RED

set -uo pipefail

LEDGER=".claude/session-ledger.md"
# The second carrier. It is NOT injected at session start by design, so its success class is
# YELLOW (found once the model went looking), never GREEN. A probe that demanded GREEN here
# would measure a property the carrier deliberately does not have.
PROJECT_STATE="${SESSION_LEDGER_PROJECT_STATE:-.claude/project-state.md}"
# THE OBSERVER MUST NOT BE READABLE BY THE SUBJECT. This used to be .claude/.effect-probe,
# inside the very project the probe measures, and that quietly destroyed the measurement: the
# checkpoint's job is to inventory every durable store it can find, so it found this one,
# read recall.json, and thereby learned the questions AND the required keywords before the
# probe ran. It then wrote "answer the kit's recall probe" into NEXT. A model that knows the
# answers and knows it is being tested produces a green result that proves nothing.
# Caught in a live run on 2026-08-01, after ten earlier passes had not surfaced it.
# So the state lives outside the project, keyed by the project path, where no inventory of
# the project can reach it.
_probe_home() {
  base="${SESSION_LEDGER_PROBE_HOME:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/effect-probe}"
  slug="$(printf '%s' "$PWD" | tr -c 'A-Za-z0-9' '-')"
  printf '%s/%s' "$base" "$slug"
}
STATE="$(_probe_home)"
# Same resolution rule as the hooks: next to this script first, classic install path second.
_SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
RENDER="${_SELF_DIR%/tools}/hooks/ledger_render.py"
[ -f "$RENDER" ] || RENDER=".claude/hooks/ledger_render.py"

# A token no model could produce by inference: this is what makes the answer checkable.
TOKEN_FILE="$STATE/token"

cmd="${1:-}"

case "$cmd" in
plant)
  mkdir -p "$STATE" 2>/dev/null || true
  [ -f "$LEDGER" ] || { echo "No ledger at $LEDGER. Start a session with the kit installed first." >&2; exit 1; }
  TOKEN="ZX-$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d ' ' || echo 4711)"
  printf '%s\n' "$TOKEN" > "$TOKEN_FILE"

  # The planted entries sit in the two sections a naive byte cut evicted first. That is
  # deliberate: if the budgeting ever regresses, this probe goes red.
  python3 - "$LEDGER" "$TOKEN" <<'PY'
import sys
path, token = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
drop = ("- Approach %s dropped: it would have cost a second network roundtrip per request\n"
        "  with no gain over the existing solution. Do not propose it again.\n" % token)
ver = "- Probe fact %s-OK: the measurement ran via [effect-probe.sh plant]\n" % token
for sec, line in (("## DROPPED", drop), ("## VERIFIED", ver)):
    if sec in text:
        i = text.index(sec) + len(sec)
        text = text[:i] + "\n" + line + text[i:].lstrip("\n")
    else:
        text = text.rstrip() + "\n\n" + sec + "\n" + line
open(path, "w", encoding="utf-8").write(text)
print("Planted in DROPPED and VERIFIED: %s" % token)
PY
  echo
  echo "Next:"
  echo "  1. /checkpoint"
  echo "  2. /compact        (the actual test)"
  echo "  3. $0 ask"
  ;;

verify)
  # Mechanical half: would a restore right now actually carry the planted entries?
  [ -f "$TOKEN_FILE" ] || { echo "No probe token. Run: $0 plant" >&2; exit 1; }
  TOKEN="$(cat "$TOKEN_FILE")"
  echo "Token: $TOKEN"
  if [ -f "$RENDER" ]; then
    # Probe the SMALLEST restore budget (prime, 6000), not the roomier re-inject body
    # (6550). A probe that only passes on the generous path would go green on a ledger
    # that the strict path clips. Keep this in step with RESTORE_BUDGET in
    # session-start-prime.sh.
    OUT="$(python3 "$RENDER" "$LEDGER" 6000 2>/dev/null)"
    printf '%s' "$OUT" | grep -q "$TOKEN" \
      && echo "MECHANICALLY GREEN: the restore carries the token (DROPPED and VERIFIED survive the budget)" \
      || echo "MECHANICALLY RED: the token falls out of the restore, the budget is evicting the delta sections"
    printf '%s' "$OUT" | grep -cE '^## ' | xargs echo "  sections in the restore:"
    printf '%s' "$OUT" | python3 -c "import sys;print('  characters:',len(sys.stdin.read()))"
  else
    echo "Renderer missing at $RENDER, the mechanical half cannot be checked." >&2
  fi
  ;;

ask)
  [ -f "$TOKEN_FILE" ] || { echo "No probe token. Run: $0 plant" >&2; exit 1; }
  TOKEN="$(cat "$TOKEN_FILE")"
  cat <<MSG
After the /compact, put EXACTLY this question to the model, with no other hint:

    "What happened with approach $TOKEN, and why?"

Grading:
  GREEN   The model names the reason (a second network roundtrip for no gain) and that the
          approach is dropped, without reading a file first.
          -> the reasoning survived the compaction inside the context.
  YELLOW  The model knows it only after reading $LEDGER.
          -> the hooks lost the race and the file plus the re-read line carried it. This is
             the documented normal case, not a failure.
  RED     The model does not know $TOKEN, guesses, or proposes the approach as an idea.
          -> the kit failed its core claim.

Then:  $0 grade "<the model's answer>"
MSG
  ;;

grade)
  [ -f "$TOKEN_FILE" ] || { echo "No probe token. Run: $0 plant" >&2; exit 1; }
  TOKEN="$(cat "$TOKEN_FILE")"
  ANSWER="${2:-}"
  [ -n "$ANSWER" ] || { echo "Usage: $0 grade \"<answer>\"" >&2; exit 1; }
  HIT=0
  printf '%s' "$ANSWER" | grep -qi "$TOKEN" && HIT=$((HIT+1))
  printf '%s' "$ANSWER" | grep -qiE 'roundtrip|network' && HIT=$((HIT+1))
  printf '%s' "$ANSWER" | grep -qiE 'dropped|abandoned|not again|do not propose' && HIT=$((HIT+1))
  echo "Hits: $HIT of 3 (token, reason, dropped status)"
  [ "$HIT" -ge 2 ] && echo "VERDICT: the reasoning was available after the compaction." \
                   || echo "VERDICT: RED, the reasoning did not arrive."
  ;;

# --- recall: the same idea, widened from one fact to a set -------------------
# WHY A SECOND MODE. The single token above answers "does anything arrive at all", which
# is a yes/no. It cannot answer "how much of what this session worked out survives", and
# that is the question a user actually has. So this mode plants one item in each of the
# three sections that carry reasoning, then grades each into three classes:
#   GREEN   answered, and the transcript shows NO file was opened in that turn
#   YELLOW  answered, but only after reading the carrier from disk
#   RED     not answered
# The class split is read from the transcript, not from the model's own account of how it
# knew, because a model asked "did you read a file" reports its impression, not the fact.

recall-plant)
  mkdir -p "$STATE" 2>/dev/null || true
  [ -f "$LEDGER" ] || { echo "No ledger at $LEDGER." >&2; exit 1; }
  T="$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d ' ' || echo 4711)"
  python3 - "$LEDGER" "$STATE" "$T" "$PROJECT_STATE" <<'PY'
import sys, os, json
ledger, state, t = sys.argv[1], sys.argv[2], sys.argv[3]
pstate = sys.argv[4] if len(sys.argv) > 4 else ""
items = [
    {"id": "RC-D%s" % t, "section": "## DROPPED",
     "line": "- Approach RC-D%s dropped: it needed a second network roundtrip per request "
             "with no gain. Never propose it again.\n" % t,
     "q": "What happened with approach RC-D%s, and why?" % t,
     "must": ["roundtrip"], "class": "dropped"},
    {"id": "RC-E%s" % t, "section": "## DECIDED",
     "line": "- RC-E%s chosen over polling: it removes the missed-event failure mode "
             "entirely.\n" % t,
     "q": "Why was RC-E%s chosen over polling?" % t,
     "must": ["missed", "failure mode", "verpasst", "fehlermodus"], "class": "decided"},
    {"id": "RC-V%s" % t, "section": "## VERIFIED",
     "line": "- RC-V%s holds at 12 concurrent writers [measured with the soak script]\n" % t,
     "q": "What proved RC-V%s, and at what scale?" % t,
     "must": ["12", "soak"], "class": "verified"},
]
# One more, in the OTHER carrier. Same shape, different expectation: this one is only
# reachable if the model follows the PLAN pointer, so YELLOW is the pass.
# The heading is looked up first and only created if the file has none, so a project that
# keeps its state file in another language keeps its own headings.
psection = "## Dropped"
try:
    ptext = open(pstate, encoding="utf-8").read()
    for cand in ("## Dropped", "## DROPPED", "## Verworfen", "## Descartado", "## Abandonne"):
        if cand in ptext:
            psection = cand
            break
except OSError:
    pass
pitem = {"id": "RC-P%s" % t, "section": psection,
         "line": "- Approach RC-P%s dropped: it needed a second service in the path with no\n"
                 "  gain. Never propose it again.\n" % t,
         "q": "What happened with approach RC-P%s, and why?" % t,
         "must": ["service", "dienst"], "class": "project-state", "expect": "YELLOW",
         "carrier": "project-state"}
text = open(ledger, encoding="utf-8").read()
for it in items:
    sec = it["section"]
    if sec in text:
        i = text.index(sec) + len(sec)
        text = text[:i] + "\n" + it["line"] + text[i:].lstrip("\n")
    else:
        text = text.rstrip() + "\n\n" + sec + "\n" + it["line"]
open(ledger, "w", encoding="utf-8").write(text)
if pstate and os.path.exists(pstate):
    ptext = open(pstate, encoding="utf-8").read()
    sec = pitem["section"]
    if sec in ptext:
        i = ptext.index(sec) + len(sec)
        ptext = ptext[:i] + "\n" + pitem["line"] + ptext[i:].lstrip("\n")
    else:
        ptext = ptext.rstrip() + "\n\n" + sec + "\n" + pitem["line"]
    open(pstate, "w", encoding="utf-8").write(ptext)
    items.append(pitem)
json.dump(items, open(os.path.join(state, "recall.json"), "w", encoding="utf-8"))
print("Planted %d items: %s" % (len(items), ", ".join(i["id"] for i in items)))
PY
  ;;

recall-ask)
  python3 - "$STATE" <<'PY'
import sys, os, json
items = json.load(open(os.path.join(sys.argv[1], "recall.json"), encoding="utf-8"))
print("Put these to the model after the compaction, in one message, with no other hint:\n")
for it in items:
    print("  " + it["q"])
PY
  ;;

recall-grade)
  # usage: recall-grade <answers-file> <transcript.jsonl>
  ANSWERS="${2:-}"; TRANSCRIPT="${3:-}"
  [ -f "$ANSWERS" ] || { echo "Usage: $0 recall-grade <answers-file> <transcript.jsonl>" >&2; exit 1; }
  python3 - "$STATE" "$ANSWERS" "${TRANSCRIPT:-}" <<'PY'
import sys, os, json
state, answers_path, transcript = sys.argv[1], sys.argv[2], sys.argv[3]
items = json.load(open(os.path.join(state, "recall.json"), encoding="utf-8"))
text = open(answers_path, encoding="utf-8").read().lower()

# Did the model open a file in the turn that answered? Look at the LAST user turn and
# everything after it. No tool_use means the reasoning was already in context.
# Which carrier did the model actually open? Per ITEM, not per turn: once one item
# legitimately sends the model to a file, a per-turn flag would downgrade every other item
# in the same answer, and the instrument would report a regression that did not happen.
# Measured: it did exactly that once, turning three GREEN items YELLOW.
# FINDING THE ANSWERING TURN, and the trap this walked into. The first version anchored on
# `isinstance(content, str)`, on the assumption that a typed message is a plain string. It is
# the other way round: a typed message arrives as a LIST of text blocks, and the plain strings
# are the command echoes and the continuation summary. Counted across three real projects:
# 1478 list against 27 str, 544 against 33, 152101 against 5144. So the anchor landed on the
# last slash command instead of the question, the scan window opened too early, and tool calls
# from earlier work were charged to the answer.
#
# The error direction is worth stating, because it decides whether past runs still hold: a
# window that is too WIDE can only find extra file access, so it turns a real GREEN into a
# YELLOW. It cannot invent a GREEN. Every green result measured with the old code was
# therefore graded under a harder rule than intended, not an easier one.
INJECTED = ("<command-name>", "<command-message>", "<ide_opened_file>", "<ide_selection>",
            "<local-command", "<system-reminder>")

def human_turn(e):
    """The text of a real human turn, or None. Tool results, injected context blocks and
    the harness's own continuation summary are not human turns."""
    if e.get("type") != "user" or e.get("isMeta"):
        return None
    c = (e.get("message") or {}).get("content")
    if isinstance(c, str):
        t = c
    elif isinstance(c, list):
        t = "\n".join(b.get("text", "") for b in c
                      if isinstance(b, dict) and b.get("type") == "text")
    else:
        return None
    t = t.strip()
    if not t or t.startswith("This session is being continued"):
        return None
    if any(tag in t[:200] for tag in INJECTED):
        return None
    return t

opened = None
if transcript and os.path.exists(transcript):
    lines = [json.loads(l) for l in open(transcript, encoding="utf-8") if l.strip()]
    idx = [i for i, e in enumerate(lines) if human_turn(e)]
    opened = set()
    for e in lines[(idx[-1] if idx else 0):]:
        if e.get("type") != "assistant":
            continue
        for b in (e.get("message") or {}).get("content", []):
            if isinstance(b, dict) and b.get("type") == "tool_use":
                blob = json.dumps(b.get("input", {}))
                if "project-state" in blob:
                    opened.add("project-state")
                if "session-ledger" in blob:
                    opened.add("ledger")

counts = {"GREEN": 0, "YELLOW": 0, "RED": 0}
for it in items:
    ok = it["id"].lower() in text and any(m.lower() in text for m in it["must"])
    carrier = it.get("carrier", "ledger")
    if not ok:
        cls = "RED"
    elif opened is None:
        cls = "UNKNOWN"
    else:
        cls = "YELLOW" if carrier in opened else "GREEN"
    # An item whose carrier is never injected passes on YELLOW. Demanding GREEN there would
    # score it against a property it was deliberately not given.
    want = it.get("expect", "GREEN")
    verdict = "pass" if (cls != "RED" and (want == "YELLOW" or cls == "GREEN")) else "FAIL"
    counts[cls] = counts.get(cls, 0) + 1
    print("%-10s %-14s %-12s want=%-6s %s" % (cls, it["class"], it["id"], want, verdict))
print("\nGREEN %d   YELLOW %d   RED %d   of %d"
      % (counts.get("GREEN", 0), counts.get("YELLOW", 0), counts.get("RED", 0), len(items)))
print("RED is the only failure: it means the reasoning did not survive at all.")
sys.exit(1 if counts.get("RED", 0) else 0)
PY
  ;;

*)
  sed -n '2,20p' "$0"
  exit 1
  ;;
esac
