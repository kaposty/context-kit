#!/usr/bin/env bash
# sync.sh: delivery -> installation.
#
# This repository holds the same files twice: once as what the kit delivers (hooks/, skills/,
# commands/, tools/), and once as the installation under .claude/, so the repository runs its
# own mechanism. Two copies drift, and that is not a guess: exactly this class (the kit and
# two target projects running apart) was the most common source of defects here. So the
# reconciliation is a command, not a matter of discipline.
#
#   bash sync.sh           copies delivery into .claude/ and sets the permissions
#   bash sync.sh --check   changes nothing, reports differences, exit 1 on drift
#
# A skill in .claude/skills/ that the kit does not deliver is left alone. It belongs to the
# project, not to the kit, so it has no counterpart at the top level and nothing to sync.

set -uo pipefail
cd "$(dirname "$0")" || exit 1

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

# The pair list is DERIVED, never typed. It used to be a hardcoded table, and that table did
# exactly what a hardcoded table does: prompt-checkpoint.sh was added to the delivery, nobody
# added the line, so the installation never got it AND `--check` reported "identical". The one
# command whose whole job is to prevent diverging copies was blind to the newest file. Now the
# delivery decides, so a new file is synced the moment it exists.
#
# hooks/hooks.json is the plugin wiring and has no place in a standalone installation, so it
# is the single deliberate exception.
PAIRS="$(
  for d in hooks skills commands tools; do
    [ -d "$d" ] || continue
    find "$d" -type f ! -name hooks.json ! -name '.DS_Store' 2>/dev/null \
      | while IFS= read -r f; do printf '%s:.claude/%s\n' "$f" "$f"; done
  done | sort
)"

# The manifest travels with an installation so a foreign copy can answer "are my files the
# ones that shipped" without a delivery to compare against. It is DERIVED from the same pair
# list as the copy above, for the reason stated there: a second, typed list is a list that
# goes stale. Generating it here rather than by hand is also why there is no version number
# to forget to bump.
_write_manifest() {
  python3 - "$1" <<'PY' 2>/dev/null
import hashlib, os, sys
out = sys.argv[1]
rows = []
for d in ("hooks", "skills", "commands", "tools"):
    if not os.path.isdir(d):
        continue
    for root, _, files in os.walk(d):
        for f in sorted(files):
            if f in ("hooks.json", ".DS_Store"):
                continue
            rel = os.path.join(root, f)
            h = hashlib.sha256()
            with open(rel, "rb") as fh:
                for chunk in iter(lambda: fh.read(65536), b""):
                    h.update(chunk)
            rows.append((h.hexdigest(), rel))
rows.sort(key=lambda r: r[1])
body = "".join("%s  %s\n" % r for r in rows)
fp = hashlib.sha256(body.encode("utf-8")).hexdigest()[:16]
with open(out, "w", encoding="utf-8") as fh:
    fh.write("# context-kit manifest, written by sync.sh. Do not edit by hand.\n")
    fh.write("# fingerprint %s  files %d\n" % (fp, len(rows)))
    fh.write(body)
PY
}

DRIFT=0
COPIED=0
for pair in $PAIRS; do
  src="${pair%%:*}"
  dst="${pair##*:}"
  if [ ! -f "$src" ]; then
    echo "MISSING from the delivery: $src"
    DRIFT=1
    continue
  fi
  if [ ! -f "$dst" ] || ! cmp -s "$src" "$dst"; then
    if [ "$CHECK" -eq 1 ]; then
      echo "DRIFT: $dst differs from $src"
      DRIFT=1
    else
      mkdir -p "$(dirname "$dst")"
      cp "$src" "$dst"
      COPIED=$((COPIED + 1))
    fi
  fi
done

# The manifest is checked the same way the files are: recompute it and compare, never trust
# that the stored one is current. A stale manifest is worse than none, because it reports
# drift on a healthy install and trains the reader to ignore the report.
_TMP_MANIFEST="$(mktemp 2>/dev/null || echo .kit-manifest.tmp)"
_write_manifest "$_TMP_MANIFEST"
if [ "$CHECK" -eq 1 ]; then
  if [ ! -s "$_TMP_MANIFEST" ]; then
    echo "MANIFEST: cannot be computed (python3 missing), so integrity is unverifiable"
    DRIFT=1
  elif ! cmp -s "$_TMP_MANIFEST" .kit-manifest; then
    echo "DRIFT: .kit-manifest is stale, run sync.sh"
    DRIFT=1
  elif ! cmp -s .kit-manifest .claude/.kit-manifest; then
    echo "DRIFT: .claude/.kit-manifest differs from .kit-manifest"
    DRIFT=1
  fi
  rm -f "$_TMP_MANIFEST"
  [ "$DRIFT" -eq 0 ] && echo "Installation is identical to the delivery."
  exit "$DRIFT"
fi

if [ -s "$_TMP_MANIFEST" ]; then
  cp "$_TMP_MANIFEST" .kit-manifest
  cp "$_TMP_MANIFEST" .claude/.kit-manifest
else
  echo "WARNING: no python3, so .kit-manifest was not written and installs cannot self-check."
fi
rm -f "$_TMP_MANIFEST"

chmod +x .claude/hooks/*.sh .claude/tools/*.sh 2>/dev/null
echo "Synchronised: ${COPIED} file(s) copied, permissions set."
