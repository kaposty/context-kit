#!/usr/bin/env bash
# prompt-checkpoint.sh: turn "prepare for compaction" into an actually fired checkpoint.
#
# Wire to: UserPromptSubmit, matcher "*"
#
# WHY THIS EXISTS, and why the obvious route is not enough. The checkpoint skill already
# carries trigger phrases in its description, so asking for it in words works, and it works
# in any language because the model reads intent rather than strings. But skill descriptions
# are the one piece of startup content a compaction does NOT restore (documented, and the
# whole reason this kit exists is that compaction loses things). From the second compaction
# of a session onward the description route is gone, silently: the user types the same words
# that worked an hour ago and nothing happens. That is the worst shape a feature can have,
# working until exactly the moment it is needed most, because "prepare for compaction" is
# said before a compaction, and by then there has usually already been one.
#
# A hook does not live in the context window. It is configuration, it is re-read every turn,
# and it therefore survives every compaction. So the phrase route is moved here, and the
# description keeps its triggers as the friendly path for a fresh session.
#
# WHAT IT DOES NOT DO. It does not run the checkpoint, and it cannot: a hook has no model
# turn. It injects one instruction, the model does the pass. It also never blocks the prompt
# and never rewrites it. On any error it exits 0 and the turn proceeds untouched.
#
# Off switch: SESSION_LEDGER_PROMPT_TRIGGER=off

set -uo pipefail

[ "${SESSION_LEDGER_PROMPT_TRIGGER:-on}" = "off" ] && exit 0

INPUT="$(cat 2>/dev/null || true)"

# The skill body, resolved relative to this file, so it is right on both install paths:
# .claude/hooks -> .claude/skills, and ${CLAUDE_PLUGIN_ROOT}/hooks -> ${CLAUDE_PLUGIN_ROOT}/skills.
_SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
SKILL="${_SELF_DIR:-.claude/hooks}/../skills/checkpoint/SKILL.md"
[ -f "$SKILL" ] || SKILL=".claude/skills/checkpoint/SKILL.md"

command -v python3 >/dev/null 2>&1 || exit 0

printf '%s' "$INPUT" | SKILL_PATH="$SKILL" python3 -c '
import json, os, re, sys

try:
    data = json.loads(sys.stdin.read() or "{}")
except Exception:
    sys.exit(0)
prompt = (data.get("prompt") or "").strip()
if not prompt:
    sys.exit(0)

# A LENGTH GATE, and it is the whole false positive defence. These phrases appear inside
# ordinary discussion too ("should the checkpoint also sync the plan?"), and firing there
# would inject an instruction to go and rewrite three files in the middle of a conversation
# ABOUT the checkpoint. A request to prepare is short. A discussion is not.
if len(prompt) > 160:
    sys.exit(0)

low = prompt.lower()
# Written out per language rather than as one clever regex, because this list is meant to be
# edited by whoever adds a language, and a regex that only its author can read gets deleted.
PATTERNS = [
    r"compact\w*\s+vorbereit",           # compact vorbereiten, compaction vorbereiten
    r"vorbereit\w*\s+(auf|f[uü]r)\s+.*compact",
    r"prepare\w*\s+(for\s+|the\s+)?compact",
    r"before\s+(the\s+)?compact",
    r"vor\s+dem\s+compact",
    r"ready\s+to\s+compact",
    r"bereit\s+f[uü]r\s+.*compact",
    r"kontext\s+sichern",
    r"save\s+(the\s+)?context\s+before",
    r"checkpoint\s+(fahren|laufen|machen|run)",
    r"run\s+.*checkpoint",
]
if not any(re.search(p, low) for p in PATTERNS):
    sys.exit(0)

skill = os.environ.get("SKILL_PATH", ".claude/skills/checkpoint/SKILL.md")
msg = (
    "The user asked to prepare for compaction. Run the checkpoint pass NOW, before "
    "answering anything else, and work all of its phases in order.\n\n"
    "If the checkpoint skill is not in your available skills, do not stop there and do not "
    "improvise a shorter version: read %s and follow it. A compaction drops skill "
    "descriptions from context while leaving the files on disk, so a missing skill here "
    "means it was dropped, not that it is absent.\n\n"
    "Finish with the hand-off the skill specifies, at most four lines, ending exactly with "
    "\"Checkpoint saved. Safe to run /compact now.\" Do not run /compact yourself; you "
    "cannot, and the user does it next."
) % skill

print(json.dumps({"suppressOutput": True,
                  "hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                         "additionalContext": msg}}))
' 2>/dev/null

exit 0
