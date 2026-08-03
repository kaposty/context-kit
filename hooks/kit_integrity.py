#!/usr/bin/env python3
"""kit_integrity.py: does this installation still match what it shipped with.

WHY THIS EXISTS. An installed copy of the kit falls behind silently. Measured, not feared:
one project ran a whole generation old for weeks, missing an entire hook file and holding
three command files from before a language decision, and nothing anywhere said so. The
person who could have fixed it in a minute had no way to learn of it. `sync.sh` catches
this inside the kit's own repository, because there the delivery sits next to the
installation, but a foreign install has no delivery to compare against.

So the comparison has to travel WITH the installation. `sync.sh` writes `.kit-manifest`, a
digest per delivered file, and that file is copied along with everything else. This script
reads it back and reports what no longer matches.

WHAT IT CANNOT DO, stated plainly so nobody reads more into a green result: it does not know
whether a NEWER version exists. An install is offline and standalone, and the only truth
available locally is what shipped with it. This answers "are my files the ones that shipped",
which is what caught both real defects, and it does not answer "am I up to date".

DELIBERATE LOCAL CHANGES are a legitimate answer, not a defect. A project that adapts a
delivered file lists it in `.kit-adopted`, one relative path per line, and it stops being
reported. That file doubles as the record of WHY a copy diverges, which is otherwise the
kind of decision that survives in nobody's head.

Contract, so a caller can rely on the exit code rather than on parsing:
  0  checked, everything matches (prints nothing)
  3  cannot check (no manifest, or it is unreadable)
  4  checked, something drifted (prints the report on stdout)
"""

import hashlib
import os
import sys

MANIFEST = ".kit-manifest"
ADOPTED = ".kit-adopted"
# How many paths to name per class before summarising. The report is injected into a session
# start, so it competes with the restore for the same output cap; a fully drifted install
# would otherwise push the ledger out of the window to report something less important.
NAME_LIMIT = 6


def digest(path):
    h = hashlib.sha256()
    try:
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(65536), b""):
                h.update(chunk)
    except OSError:
        return None
    return h.hexdigest()


def read_manifest(root):
    """Returns [(sha, relpath)], or None when there is nothing usable to check against."""
    try:
        with open(os.path.join(root, MANIFEST), encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return None
    entries = []
    for line in lines:
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.split(None, 1)
        if len(parts) != 2:
            continue
        entries.append((parts[0], parts[1].strip()))
    return entries or None


def read_adopted(root):
    """Paths this project has deliberately taken over. A `#` starts a comment, so the reason
    for adopting a file can live on the same line as the path."""
    out = set()
    try:
        with open(os.path.join(root, ADOPTED), encoding="utf-8") as fh:
            for line in fh:
                line = line.split("#", 1)[0].strip()
                if line:
                    out.add(line)
    except OSError:
        pass
    return out


def render(missing, changed, adopted_count):
    lines = ["# Kit integrity", ""]
    total = len(missing) + len(changed)
    lines.append(
        "%d delivered file(s) no longer match the manifest this installation shipped with, "
        "so it is running a version nobody can name." % total
    )
    lines.append("")
    for label, group in (("missing", missing), ("changed", changed)):
        if not group:
            continue
        shown = sorted(group)[:NAME_LIMIT]
        rest = len(group) - len(shown)
        line = "%s: %s" % (label, ", ".join(shown))
        if rest > 0:
            line += " and %d more" % rest
        lines.append(line)
    lines.append("")
    lines.append(
        "Say this in one line and carry on, it is the user's call and not yours. Copy the "
        "files from the kit to update, or, if a change here is deliberate, add its path to "
        "`%s` (one per line) and it stops being reported." % ADOPTED
    )
    if adopted_count:
        lines.append("(%d file(s) already adopted and not counted above.)" % adopted_count)
    return "\n".join(lines)


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    entries = read_manifest(root)
    if entries is None:
        return 3
    adopted = read_adopted(root)
    missing, changed, skipped = [], [], 0
    for sha, rel in entries:
        if rel in adopted:
            skipped += 1
            continue
        got = digest(os.path.join(root, rel))
        if got is None:
            missing.append(rel)
        elif got != sha:
            changed.append(rel)
    if not missing and not changed:
        return 0
    sys.stdout.write(render(missing, changed, skipped))
    return 4


if __name__ == "__main__":
    sys.exit(main())
