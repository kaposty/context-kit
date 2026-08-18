#!/usr/bin/env bash
# brief-digest.sh: the facts a briefing is built from, and nothing else.
#
# WHAT THIS IS FOR. The built in displays answer "what is configured": /status shows the
# active settings sources, /permissions the resolved rules, /context what is loaded. None of
# them answers "what happened while I was away". That is the gap this fills, and it is the
# question a person has after leaving an agent to work.
#
# WHY A SCRIPT AND NOT JUST THE MODEL. The curated files can be stale: in this kit's own
# history the ledger went nine full passes without a flush, and a briefing built from it
# alone would have reported silence while work was happening. The transcript cannot lie
# about activity, so the transcript is the spine and the curated files supply the reasons.
#
# WHAT IT DELIBERATELY DOES NOT DO. It writes nothing. No marker, no cache, no report file.
# The window is derived from the transcript itself, which already records every earlier run.
# A briefing is re-derivable by construction, so storing one would only create a file that
# goes stale.
#
# Usage, from the project root:
#   brief-digest.sh              window: since the last brief in the transcript, else 24h
#   brief-digest.sh 24h          explicit span, also 90m, 3d
#   brief-digest.sh 2026-07-27   explicit start date
#
# Output is plain text for a model to read, capped at SESSION_LEDGER_BRIEF_BUDGET
# characters (default 4000). Truncation is announced, never silent.

set -uo pipefail

BUDGET="${SESSION_LEDGER_BRIEF_BUDGET:-4000}"
LEDGER=".claude/session-ledger.md"
PROJECT_STATE="${SESSION_LEDGER_PROJECT_STATE:-.claude/project-state.md}"
HOOK_LOG=".claude/log/session-ledger-hook.log"
PROJECTS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
WINDOW_ARG="${1:-}"

# The transcript directory name is a lossy slug of the working directory: an underscore and
# a slash both become a hyphen, so two different projects can map to the same name. Matching
# on the cwd field recorded inside the transcript is exact, and it costs one line per file.
# Measured: a directory named my_project lands under a transcript directory spelled
# my-project, so the underscore is already gone by the time you could match on the name.
find_transcripts() {
  [ -d "$PROJECTS_DIR" ] || return 0
  python3 - "$PROJECTS_DIR" "$PWD" <<'PY' 2>/dev/null
import json, os, sys
root, want = sys.argv[1], sys.argv[2]
hits = []
for d in os.listdir(root):
    p = os.path.join(root, d)
    if not os.path.isdir(p):
        continue
    files = [os.path.join(p, f) for f in os.listdir(p) if f.endswith(".jsonl")]
    if not files:
        continue
    newest = max(files, key=os.path.getmtime)
    cwd = None
    try:
        with open(newest, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    o = json.loads(line)
                except Exception:
                    continue
                if o.get("cwd"):
                    cwd = o["cwd"]
                    break
    except OSError:
        continue
    if cwd == want:
        hits.extend(files)
for f in hits:
    print(f)
PY
}

# Without python3 the transcript half is unreachable. Say so out loud and deliver the half
# that shell can do. A degradation that looks like a quiet success is the failure mode this
# kit argues against, so the header carries INCOMPLETE and the caller has to repeat it.
degraded() {
  echo "BRIEF DIGEST INCOMPLETE: python3 is missing, so the transcript could not be read."
  echo "Everything below is from git, the hook log and the carrier files only. Say this in"
  echo "the briefing: progress, learned and in progress are guesses without the transcript."
  echo
  echo "== WINDOW =="
  echo "requested: ${WINDOW_ARG:-since the last brief} | determined: last 24h fallback"
  echo
  echo "== GIT =="
  git log --since="24 hours ago" --format='%h %ad %s' --date=format:'%d.%m %H:%M' 2>/dev/null | head -30
  echo "working tree: $(git status --porcelain 2>/dev/null | wc -l | tr -d ' ') uncommitted path(s)"
  echo
  echo "== HOOK LOG =="
  [ -f "$HOOK_LOG" ] && tail -20 "$HOOK_LOG"
  echo
  echo "== CARRIERS =="
  for f in "$LEDGER" "$PROJECT_STATE"; do
    [ -f "$f" ] && echo "$f last written $(date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null)"
  done
}

# Presence on PATH is not the same as working. A python3 that exists and exits non zero would
# pass a `command -v` check, then every extraction would return nothing and the digest would
# print an empty but well formed report, which reads as "a quiet day". So it is executed once.
if ! python3 -c "" >/dev/null 2>&1; then
  degraded
  exit 0
fi

TRANSCRIPTS="$(find_transcripts)"

GIT_LOG="$(git log --format='%h|%aI|%s' -n 200 2>/dev/null)"
GIT_DIRTY="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
# IS THE TREE WE ARE MEASURING THE CURRENT ONE? Everything below reads the local checkout, and
# a checkout that is behind its upstream produces facts that are false without looking it.
# Measured in a real project on 2026-08-18: a detached HEAD 32 commits back made the digest
# report "no commits in window" while 24 commits sat on the upstream inside that window, and
# call a carrier file unsaved that had been written an hour earlier. Two lines in the voice of
# a measurement, both wrong, in a report whose only promise is facts.
#
# The tree is NOT swapped for the upstream: the local checkout is what the session worked in,
# and measuring somewhere else would answer a different question. It is declared instead, the
# same way every other bound in here is declared, so the briefing carries the caveat.
GIT_UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"
GIT_BEHIND=""
if [ -n "$GIT_UPSTREAM" ]; then
  GIT_BEHIND="$(git rev-list --count "HEAD..$GIT_UPSTREAM" 2>/dev/null)"
else
  # A detached HEAD has no upstream at all, which is exactly the shape the field hit. Fall back
  # to the default remote branch so the case that caused this is the one that is covered.
  for _r in origin/HEAD origin/main origin/master; do
    _t="$(git rev-parse --verify --quiet "$_r" 2>/dev/null)" || continue
    [ -n "$_t" ] || continue
    GIT_UPSTREAM="$(git rev-parse --abbrev-ref "$_r" 2>/dev/null)"
    GIT_BEHIND="$(git rev-list --count "HEAD..$_r" 2>/dev/null)"
    break
  done
fi
case "${GIT_BEHIND:-0}" in ''|*[!0-9]*|0) GIT_BEHIND="" ;; esac

# The file list travels as an environment variable, not on stdin: python3 reads the program
# itself from stdin here, so a pipe would be swallowed by the heredoc and arrive empty.
export BRIEF_TRANSCRIPTS="$TRANSCRIPTS"
export BRIEF_BUDGET="$BUDGET"
export BRIEF_WINDOW_ARG="$WINDOW_ARG"
export BRIEF_GIT_LOG="$GIT_LOG"
export BRIEF_GIT_DIRTY="$GIT_DIRTY"
export BRIEF_GIT_BRANCH="$GIT_BRANCH"
export BRIEF_GIT_BEHIND="$GIT_BEHIND"
export BRIEF_GIT_UPSTREAM="$GIT_UPSTREAM"
export BRIEF_LEDGER="$LEDGER"
export BRIEF_PROJECT_STATE="$PROJECT_STATE"
export BRIEF_HOOK_LOG="$HOOK_LOG"

python3 - <<'PY'
import json, os, re, sys, datetime

budget = int(os.environ.get("BRIEF_BUDGET", "4000"))
window_arg = os.environ.get("BRIEF_WINDOW_ARG", "").strip()
files = [f for f in os.environ.get("BRIEF_TRANSCRIPTS", "").split("\n") if f.strip()]

# Reading every transcript this directory ever produced does not scale, and it fails in the
# one place the briefing is worth most: a busy project. Measured in a real repository, 26844
# entries across 37 compactions in a single day, the unbounded read took 285 seconds and blew
# past a two minute timeout. So the input carries two bounds, and both are reported rather
# than applied quietly, because a digest that silently saw less than it claims is worse than
# a slow one.
#   - by age: a file whose mtime predates the floor cannot hold an in-window entry.
#   - by count: newest file first, stop once the cap is reached.
# The newest file is always read, whatever the floor says, otherwise a quiet day would leave
# the window with nothing to anchor on.
import collections
max_age_days = float(os.environ.get("BRIEF_MAX_AGE_DAYS", "7") or 7)
max_entries = int(os.environ.get("BRIEF_MAX_ENTRIES", "20000") or 20000)

def parse(path, limit):
    out = []
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            # deque reads the lines but parses only the tail: json.loads is what costs, not
            # the read, so this is where the seconds actually go.
            for line in collections.deque(fh, maxlen=limit):
                try:
                    out.append(json.loads(line))
                except Exception:
                    continue
    except OSError:
        pass
    return out

def mtime(p):
    try:
        return os.path.getmtime(p)
    except OSError:
        return 0.0

files = sorted(files, key=mtime, reverse=True)
floor = (datetime.datetime.now() - datetime.timedelta(days=max_age_days)).timestamp()
entries, skipped_old, capped, files_read = [], 0, False, 0
for i, f in enumerate(files):
    if i and mtime(f) < floor:
        skipped_old += 1
        continue
    if len(entries) >= max_entries:
        capped = True
        break
    entries.extend(parse(f, max_entries - len(entries)))
    files_read += 1
entries = [e for e in entries if e.get("timestamp")]
entries.sort(key=lambda e: e["timestamp"])
bounds = []
if skipped_old:
    bounds.append("%d transcript file(s) older than %g days not read" % (skipped_old, max_age_days))
if capped or len(entries) >= max_entries:
    bounds.append("stopped at %d entries, older ones not read" % max_entries)

def text_of(entry):
    m = entry.get("message")
    if not isinstance(m, dict):
        return ""
    c = m.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        parts = []
        for b in c:
            if isinstance(b, dict) and b.get("type") == "text":
                parts.append(b.get("text", ""))
        return "\n".join(parts)
    return ""

# The window. An earlier run of this command is recorded in the transcript like any other
# slash command, so the last look needs no file on disk. The current invocation is itself
# the newest user message, so anything at or after that timestamp is this run and is
# excluded, otherwise the window would always be empty.
last_user = ""
for e in entries:
    if e.get("type") == "user" and not e.get("isMeta"):
        last_user = e["timestamp"]

marks = []
for e in entries:
    if e.get("type") != "user":
        continue
    t = text_of(e)
    if "<command-name>" in t and re.search(r"<command-name>/(context-kit:)?brief</command-name>", t):
        if e["timestamp"] < last_user:
            marks.append(e["timestamp"])

def span_to_delta(s):
    m = re.match(r"^(\d+)\s*([mhd])$", s.lower())
    if not m:
        return None
    n, unit = int(m.group(1)), m.group(2)
    return datetime.timedelta(minutes=n) if unit == "m" else \
           datetime.timedelta(hours=n) if unit == "h" else datetime.timedelta(days=n)

newest = entries[-1]["timestamp"] if entries else ""

def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%S")

def as_dt(s):
    try:
        return datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).replace(tzinfo=None)
    except Exception:
        return None

origin = ""
cut = ""
if window_arg:
    d = span_to_delta(window_arg)
    if d is not None and newest:
        base = as_dt(newest)
        cut = iso(base - d) if base else ""
        origin = "explicit span %s" % window_arg
    else:
        cut = window_arg
        origin = "explicit start %s" % window_arg
elif marks:
    cut = marks[-1]
    origin = "since the last brief"
elif newest:
    base = as_dt(newest)
    cut = iso(base - datetime.timedelta(hours=24)) if base else ""
    origin = "no earlier brief found, fell back to 24h"
else:
    # No transcript at all. The only remaining reference is the machine clock, and that one
    # is not to be trusted here: a session can span days, so a 24h window by clock can be
    # empty while there is plenty to report. It is used, and the header says it was used.
    cut = iso(datetime.datetime.now() - datetime.timedelta(hours=24))
    origin = "no transcript for this directory, fell back to 24h by the machine clock"

win = [e for e in entries if e["timestamp"] >= cut] if cut else []

# A window with almost nothing in it is far more often a repeated call than a quiet period.
# Measured: a /brief was interrupted, and because the mark hangs on the COMMAND and not on its
# result, the retry four minutes later reported a correct and useless "since the last brief,
# 10 entries, under a minute". The user then had to guess a span by hand. The mark cannot be
# made to depend on the result, because this tool deliberately writes no file, so the fallback
# is measured on content instead: step back to an earlier brief, and failing that widen to 24h.
# Announced either way, never silently.
min_entries = int(os.environ.get("BRIEF_MIN_ENTRIES", "25") or 25)
if origin == "since the last brief" and len(win) < min_entries:
    thin = len(win)
    for cand in reversed(marks[:-1]):
        w = [e for e in entries if e["timestamp"] >= cand]
        if len(w) >= min_entries:
            cut, win = cand, w
            origin = ("the last brief was %d entries ago, which reads as a repeated call, "
                      "so this steps back to the brief before it" % thin)
            break
    else:
        base = as_dt(newest)
        cand = iso(base - datetime.timedelta(hours=24)) if base else ""
        w = [e for e in entries if e["timestamp"] >= cand] if cand else []
        if len(w) > thin:
            cut, win = cand, w
            origin = ("the last brief was %d entries ago, which reads as a repeated call, "
                      "so this widened to 24h" % thin)

def human_span(a, b):
    da, db = as_dt(a), as_dt(b)
    if not da or not db:
        return "unknown"
    s = int((db - da).total_seconds())
    d, r = divmod(s, 86400)
    h, r = divmod(r, 3600)
    m = r // 60
    bits = []
    if d:
        bits.append("%dd" % d)
    if h:
        bits.append("%dh" % h)
    if not d and m:
        bits.append("%dmin" % m)
    return " ".join(bits) or "under a minute"

# Facts, gathered per class. Each class is emitted separately so the budget can drop the
# cheap tail (prose) without ever dropping the expensive head (failures).
user_msgs, assistant_tail, failures, denials = [], [], [], []
started, finished, compactions = [], set(), 0
tools = {}

for e in win:
    ts = e["timestamp"][:16].replace("T", " ")
    t = e.get("type")
    if e.get("isCompactSummary"):
        compactions += 1
    # Failures first, before any branch that can skip the rest of the loop body. A tool
    # result carries no text, so the prose branch below leaves early on exactly the entries
    # that hold the errors, and the probe caught that on its first run.
    if e.get("toolDenialKind"):
        denials.append("%s  denied: %s" % (ts, e.get("toolDenialKind")))
    m = e.get("message")
    if isinstance(m, dict) and isinstance(m.get("content"), list):
        for b in m["content"]:
            if isinstance(b, dict) and b.get("is_error"):
                body = b.get("content")
                if isinstance(body, list):
                    body = " ".join(str(x.get("text", "")) for x in body if isinstance(x, dict))
                failures.append("%s  %s" % (ts, " ".join(str(body or "").split())[:200]))
    if t == "user" and not e.get("isMeta"):
        raw = text_of(e).strip()
        if not raw:
            continue
        if "<task-notification>" in raw:
            for tid in re.findall(r"<task-id>([^<]+)</task-id>", raw):
                finished.add(tid)
            continue
        if raw.startswith("<") and "command-name" not in raw:
            continue
        user_msgs.append("%s  %s" % (ts, " ".join(raw.split())[:160]))
    elif t == "assistant":
        m = e.get("message") or {}
        for b in (m.get("content") or []):
            if not isinstance(b, dict):
                continue
            if b.get("type") == "tool_use":
                name = b.get("name", "?")
                tools[name] = tools.get(name, 0) + 1
                if name in ("Agent", "Workflow"):
                    started.append(b.get("id", "?"))
            elif b.get("type") == "text":
                txt = " ".join((b.get("text") or "").split())
                if len(txt) > 40:
                    assistant_tail.append("%s  %s" % (ts, txt[:240]))

# Staleness measured in WORK, not in clock time. An idle weekend leaves a carrier untouched
# and nothing is lost; an afternoon of unflushed work is the actual risk. So the number
# reported is how many transcript entries landed after the file was last written.
def carrier(path):
    if not os.path.exists(path):
        return "%s missing" % path
    mt = datetime.datetime.fromtimestamp(os.path.getmtime(path))
    since = 0
    for e in win:
        d = as_dt(e["timestamp"])
        if d and d > mt:
            since += 1
    tail = " UNSAVED: %d entries of work since it was last written" % since if since else " current"
    return "%s written %s,%s" % (path, mt.strftime("%Y-%m-%d %H:%M"), tail)

blocks = []
blocks.append(("WINDOW", "\n".join([
    "from %s to %s (%s)" % ((cut or "?")[:16].replace("T", " "),
                            (newest or "?")[:16].replace("T", " "),
                            human_span(cut, newest) if cut else "?"),
    "determined: %s" % origin,
    "entries in window: %d, compactions: %d" % (len(win), compactions),
    # What was actually read, so a bound is visible as a number and not only as a note.
    "read: %d entries from %d of %d transcript file(s)" % (len(entries), files_read, len(files)),
] + (["NOTE: read was bounded, %s. Say so in the briefing." % "; ".join(bounds)] if bounds else [])
  + (["NOTE: no transcript for this directory was found, the transcript half is empty."] if not files else [])
  + (["NOTE: this working tree is %s commit(s) behind %s, so the GIT and CARRIERS facts below "
      "describe an older state than the branch. Say so in the briefing."
      % (os.environ.get("BRIEF_GIT_BEHIND"), os.environ.get("BRIEF_GIT_UPSTREAM") or "its upstream")]
     if os.environ.get("BRIEF_GIT_BEHIND") else []))))

git_lines = []
for row in (os.environ.get("BRIEF_GIT_LOG") or "").split("\n"):
    if not row.strip():
        continue
    sha, when, subj = (row.split("|", 2) + ["", ""])[:3]
    if cut and when[:19] < cut[:19]:
        continue
    git_lines.append("%s %s %s" % (sha, when[5:16].replace("T", " "), subj))
blocks.append(("GIT", "\n".join(
    (git_lines or ["no commits in window"]) +
    ["branch %s, %s uncommitted path(s)" % (os.environ.get("BRIEF_GIT_BRANCH", "?"),
                                            os.environ.get("BRIEF_GIT_DIRTY", "?"))])))

blocks.append(("FAILURES", "\n".join(failures + denials) or "none recorded"))

pending = len(started) - len(finished)
blocks.append(("BACKGROUND", "%d agent or workflow start(s), %d completion notice(s), %d never reported back"
               % (len(started), len(finished), pending if pending > 0 else 0)))

hook_log = os.environ.get("BRIEF_HOOK_LOG", "")
hl = []
if os.path.exists(hook_log):
    try:
        for line in open(hook_log, encoding="utf-8", errors="replace"):
            if cut and line[:19] < cut[:19]:
                continue
            if any(k in line for k in ("BLOCK", "WARN", "nudge", "INCOMPLETE")):
                hl.append(line.rstrip())
    except OSError:
        pass
blocks.append(("HOOKS", "\n".join(hl[-12:]) or "nothing notable"))

blocks.append(("CARRIERS", "\n".join([
    carrier(os.environ.get("BRIEF_LEDGER", "")),
    carrier(os.environ.get("BRIEF_PROJECT_STATE", "")),
])))

blocks.append(("TOOLS", ", ".join("%s %d" % kv for kv in sorted(tools.items(), key=lambda x: -x[1])[:8]) or "none"))
blocks.append(("YOUR MESSAGES", "\n".join(user_msgs[-25:]) or "none"))
blocks.append(("WHAT WAS SAID", "\n".join(assistant_tail[-60:]) or "none"))

# The budget binds EVERY block, not only the tail. The first version capped the three prose
# blocks and let the head run free, which reads as a working budget in a small project and
# inverts in a busy one: measured at 21273 characters against a budget of 4000, with the
# unbounded git and failure blocks eating the whole allowance and the three blocks that
# actually say what happened dropped for space. So no block may take more than a third, and
# nothing is ever emitted past the budget.
# The blank line between blocks is part of what is emitted, so it is part of what is counted.
# Leaving it out of the arithmetic put the first fix a few characters over its own cap, which
# is the same defect the renderer had.
# Every block gets an equal share, and whatever a block leaves unused flows to the next one.
# A plain "first come, first served" order starves the tail in exactly the projects where the
# briefing matters: the git and failure blocks arrive first, so in a busy repository they ate
# the allowance and the three blocks that narrate what happened were dropped whole. A share
# per block means a noisy head can no longer silence the tail.
out, spent, dropped = [], 0, []
share = max(budget // max(len(blocks), 1), 200)
for i, (name, body) in enumerate(blocks):
    chunk = "== %s ==\n%s\n\n" % (name, body)
    # Everything not yet spent, minus the shares still owed to the blocks after this one.
    owed = share * (len(blocks) - i - 1)
    limit = max(min(budget - spent - owed, budget - spent), 0)
    if len(chunk) > limit:
        marker = "\n[TRUNCATED]\n"
        room = limit - len(marker)
        if room > 120:
            chunk = chunk[:room] + marker
            dropped.append(name + " (partly)")
        else:
            dropped.append(name)
            continue
    out.append(chunk)
    spent += len(chunk)

header = "BRIEF DIGEST, facts only. Budget %d characters, used %d." % (budget, spent)
if dropped:
    header += " CUT FOR SPACE: %s. Say so in the briefing." % ", ".join(dropped)
print(header)
print()
sys.stdout.write("".join(out))
PY
