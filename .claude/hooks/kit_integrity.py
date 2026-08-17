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
        "Say this in one line and carry on, it is the user's call and not yours. DO NOT "
        "OFFER TO OVERWRITE: a file can differ because it is older than what shipped or "
        "because it was improved here, and a digest cannot tell the two apart. Measured in "
        "a real project: the installation was AHEAD of the kit, and copying from the kit "
        "would have deleted the better files. If a change here is deliberate, add its path "
        "to `%s` (one per line) and it stops being reported." % ADOPTED
    )
    if adopted_count:
        lines.append("(%d file(s) already adopted and not counted above.)" % adopted_count)
    return "\n".join(lines)


SHADOW_DIRS = ("hooks", "tools", "commands", "skills")


def render_shadow(differing, adopted_count):
    lines = ["# Kit integrity", ""]
    lines.append(
        "%d file(s) under `.claude/` differ from the context-kit plugin installed on this "
        "machine, and the local copy is the one that runs: the commands probe `.claude/` "
        "first, so an old file there overrides a current plugin instead of sitting beside it."
        % len(differing)
    )
    lines.append("")
    shown = sorted(differing)[:NAME_LIMIT]
    rest = len(differing) - len(shown)
    line = "differ: %s" % ", ".join(shown)
    if rest > 0:
        line += " and %d more" % rest
    lines.append(line)
    lines.append("")
    lines.append(
        "Say this in one line and carry on, it is the user's call and not yours. WHICH WAY "
        "IS NOT KNOWN FROM HERE: the local copy can be older than the plugin or newer than "
        "it, and nothing on disk says which, so do not offer to overwrite either side. If "
        "the local version is deliberate, add its path to `%s` (one per line) and it stops "
        "being reported." % ADOPTED
    )
    if adopted_count:
        lines.append("(%d file(s) already adopted and not counted above.)" % adopted_count)
    return "\n".join(lines)


def shadow(kit_root, project_root):
    """Compare the copy under <project_root>/.claude against the kit at <kit_root>.

    This is the one question the manifest alone cannot answer. The header above says so:
    an installation is offline, so its manifest can only report "are my files the ones that
    shipped", never "am I up to date". A plugin changes that, because the cache on this
    machine is a second, independent reference. Only files present on BOTH sides are
    compared: a file that exists only in the kit is reached through the lookup fallback and
    shadows nothing, and reporting it would turn this into noise.
    """
    # The kit's own repository is excluded, and not as a convenience. There `.claude/` is a
    # working copy of the delivery kept current by sync.sh, while the installed plugin is an
    # older RELEASE, so the two differ permanently and by design. sync.sh --check is the
    # mechanism there. A report that is always on is a report nobody reads.
    if os.path.isfile(os.path.join(project_root, ".claude-plugin", "plugin.json")):
        return 0
    local_root = os.path.join(project_root, ".claude")
    if not os.path.isdir(local_root):
        return 3
    adopted = read_adopted(local_root)
    differing, skipped, compared = [], 0, 0
    for d in SHADOW_DIRS:
        base = os.path.join(kit_root, d)
        if not os.path.isdir(base):
            continue
        for cur, _dirs, files in os.walk(base):
            for name in files:
                if name in ("hooks.json", ".DS_Store"):
                    continue
                rel = os.path.relpath(os.path.join(cur, name), kit_root)
                mine = os.path.join(local_root, rel)
                if not os.path.isfile(mine):
                    continue
                if rel in adopted:
                    skipped += 1
                    continue
                compared += 1
                if digest(mine) != digest(os.path.join(kit_root, rel)):
                    differing.append(rel)
    if not compared and not skipped:
        return 3
    if not differing:
        return 0
    sys.stdout.write(render_shadow(differing, skipped))
    return 4


def main():
    argv = sys.argv[1:]
    if "--shadow" in argv:
        i = argv.index("--shadow")
        kit_root = argv[0] if i > 0 else "."
        project_root = argv[i + 1] if len(argv) > i + 1 else "."
        return shadow(kit_root, project_root)
    root = argv[0] if argv else "."
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
