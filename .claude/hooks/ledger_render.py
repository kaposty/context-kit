#!/usr/bin/env python3
"""Render a session ledger into a budgeted re-inject block.

Shared by session-start-prime.sh (restore on startup) and session-start-reinject.sh
(restore after compaction/resume), so the budgeting rules exist once instead of twice.

Usage:  ledger_render.py <ledger-path> <budget-chars>
Exit:   0 = COMPLETE block on stdout, every canonical section carried in full
        4 = PARTIAL block on stdout, something canonical was clipped or omitted
        3 = ledger holds nothing but an untouched skeleton, caller must stay silent
        1 = unusable input, caller should fall back

THE 0-VERSUS-4 SPLIT IS THE POINT. The caller prints a canary line that tells a later
turn "the reasoning is in context, no need to read the file". If that canary is printed
whenever a hook merely ran, then every restore defect ends in the same state: the
reasoning is gone AND the fallback that would have recovered it is suppressed, while the
user sees a success signal. That is worse than having no kit at all, because without one
the model distrusts a summary and re-reads. So completeness is reported, not assumed, and
the canary is coupled to exit 0.

Why this file exists at all, and why the logic is not inline in the hooks:

1. BUDGET, not truncation. Hook output is capped (10,000 characters in current Claude
   Code) and past the cap the whole block is replaced by a file pointer, so a fat
   re-inject silently becomes no re-inject. The naive fix, cutting the joined text at N
   bytes, was measured against a real 18 KB ledger and failed badly: VERIFIED started at
   byte 11677 and DROPPED at 13839, so a 6000-byte cut delivered TASK + DECIDED + half of
   OPEN and dropped exactly the two sections that carry the point of the whole kit (a
   fact with the command that proved it, an abandoned path with the reason not to retry
   it). Worse, non-canonical bloat sections sitting earlier in the file actively pushed
   them out. So budget is allocated by PRIORITY: every canonical section gets a floor,
   the rest grows in priority order, and non-canonical sections are served last and cut
   first. Emission order stays restore-first because that is the reading order.

   THE BUDGET IS A POST-CONDITION, not an intention. An earlier version charged only
   headers and bodies while emitting separators, per-section truncation notes and two
   footnotes on top: measured, it overshot on 4001 of 4001 sampled budgets (up to +491
   characters), which is exactly how a block crosses the 10,000 cap and turns into a
   pointer. Allocation now iterates against the real rendered length and a final
   enforcement pass guarantees the contract even if allocation is imperfect.

2. CHARACTERS, not bytes. Cutting bytes splits multi-byte characters and produces
   mojibake at the seam. Clipping happens on line boundaries, counted in characters.

3. ONE ENTRY PER SECTION NAME. A model told "a decision gets locked -> ## DECIDED" will
   sooner or later append a second ## DECIDED instead of writing into the first. A
   dict comprehension keyed by name silently kept only the last one: measured on a 252
   character ledger with a 5000 budget, so under no budget pressure at all, the first
   VERIFIED fact and the first DROPPED path vanished with no note anywhere. Duplicate
   sections are merged now, in file order.

4. One file, not two copies. The same rendering ran in both hooks; duplicated logic
   drifts, and this kit exists to fight stale duplication.
"""

import re
import sys

# Emission order: how a compacted window reads a ledger (orientation, then reference).
CANON = ["TASK", "NEXT", "OPEN", "DECIDED", "VERIFIED", "DROPPED", "PLAN"]

# Budget order: who survives when space is short. TASK/NEXT/PLAN are one-liners, so the
# real contention is between OPEN, DECIDED and the two delta sections. DROPPED and
# VERIFIED outrank DECIDED because they are what a summary cannot reconstruct: a dropped
# path gets retried and a verified fact gets re-verified, both expensively.
PRIORITY = ["TASK", "NEXT", "DROPPED", "VERIFIED", "OPEN", "DECIDED", "PLAN"]

# Per-section floor. Capped by a fair share when the budget cannot fund every floor: the
# earlier version handed the full floor to whoever came first in PRIORITY and left the
# rest with nothing, so at budget 500 to 700 the very sections this file exists to
# protect were evicted again. A floor that only the lucky get is not a floor.
FLOOR = 320

BLOAT_NOTE = (
    "_This ledger carries non-canonical sections. Durable knowledge belongs in "
    "the knowledge docs or memory of the project, not in the session ledger._"
)


def split_sections(text):
    """Return [(canonical_name_or_None, header, body)], duplicates merged, in file order.

    Fence-aware: a "## " line inside a fenced code block is content, not a header. A
    ledger that quotes markdown (a VERIFIED line citing this hook's own output, say)
    otherwise gets split mid-quote, the tail is re-sorted to the end as a phantom
    non-canonical section, and the lint then reports a section that does not exist.
    """
    lines = text.split("\n")
    fenced = False
    blocks = []  # [[header_or_None, [body lines]]]
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            fenced = not fenced
        if not fenced and re.match(r"^## ", line):
            blocks.append([line.strip(), []])
        elif blocks:
            blocks[-1][1].append(line)
        # Content before the first header is preamble; it is not a section and is
        # reported by main() rather than silently dropped.

    merged = []  # [(name_or_None, header, body)]
    index = {}
    for header, body_lines in blocks:
        body = "\n".join(body_lines).rstrip()
        if not body.strip():
            continue  # untouched skeleton section, never re-inject as noise
        label = header[3:].strip()
        word = label.split()[0].strip(":*_-") if label.split() else ""
        name = word.upper() if word.upper() in CANON else None
        if name and name in index:
            pos = index[name]
            merged[pos] = (name, merged[pos][1], merged[pos][2] + "\n" + body)
            continue
        if name:
            index[name] = len(merged)
        merged.append((name, header, body))
    return merged


def allocate(by_name, extras, budget):
    """Split the budget across sections, canonical floors first, bloat last.

    Extras are charged only from what is left after the canonical floors. Charging their
    headers up front was measured to evict every canonical section: 200 bloat headers ate
    3000 characters of budget before TASK got its first byte.
    """
    alloc = {}
    present = [n for n in PRIORITY if n in by_name]
    remaining = budget
    for name in present:
        remaining -= len(by_name[name][0]) + 2  # header plus its separator
    remaining = max(remaining, 0)

    if present:  # pass 1: floors, capped by an equal share so nobody starves
        share = remaining // len(present)
        for name in present:
            take = min(len(by_name[name][1]), FLOOR, share, remaining)
            take = max(take, 0)
            alloc[name] = take
            remaining -= take
    for name in present:  # pass 2: grow to full size, in priority order
        if remaining <= 0:
            break
        take = min(len(by_name[name][1]) - alloc.get(name, 0), remaining)
        alloc[name] = alloc.get(name, 0) + take
        remaining -= take

    extra_alloc = []  # pass 3: leftovers only. Bloat is cut before the deltas.
    for header, body in extras:
        cost = len(header) + 2
        take = min(len(body), remaining - cost) if remaining > cost else 0
        take = max(take, 0)
        extra_alloc.append(take)
        if take:
            remaining -= take + cost
    return alloc, extra_alloc


def clip(body, limit):
    """Truncate on a line boundary, counting characters. Returns (kept, dropped_lines)."""
    if limit >= len(body):
        return body, 0
    if limit <= 0:
        return "", body.count("\n") + 1
    head = body[:limit]
    cut = head.rfind("\n")
    if cut >= 0:  # >= 0, not > 0: a body starting with "\n" has its only boundary at 0,
        head = head[:cut]  # and the old > 0 test then cut mid-word instead.
    dropped = body[len(head) :].strip().count("\n") + 1
    return head.rstrip(), dropped


def render(by_name, extras, alloc, extra_alloc, budget):
    """Build the block. Returns (text, canonical_loss, dropped_extras).

    The two footnotes are advice, not payload, so they are appended only if they still
    fit. Charging them unconditionally starved the payload at small budgets: with two
    bloat sections present, the 148-character bloat note plus the omission list consumed
    a 500-character budget entirely and the restore came out empty.
    """
    out, notes = [], []
    canonical_loss = False
    for name in CANON:  # emit in reading order, not in budget order
        if name not in by_name:
            continue
        header, body = by_name[name]
        kept, dropped = clip(body, alloc.get(name, 0))
        if not kept.strip():
            notes.append("%s (omitted, over budget)" % name)
            canonical_loss = True
            continue
        out.append(header + "\n" + kept)
        if dropped:
            canonical_loss = True
            out.append("_... %d more line(s) in this section, see the file._" % dropped)

    dropped_extras = 0
    for (header, body), take in zip(extras, extra_alloc):
        kept, dropped = clip(body, take)
        if not kept.strip():
            dropped_extras += 1
            continue
        out.append(header + "\n" + kept)
        if dropped:
            out.append("_... %d more line(s) in this section, see the file._" % dropped)

    if not out:
        return "", True, dropped_extras

    text = "\n\n".join(out)
    if notes:
        line = "\n\n_Not restored (budget): " + "; ".join(notes) + ". Read the file._"
        short = "\n\n_Sections omitted over budget. Read the file._"
        if len(text) + len(line) <= budget:
            text += line
        elif len(text) + len(short) <= budget:
            text += short  # the fact that something is missing outranks naming it
    if extras and len(text) + len(BLOAT_NOTE) + 2 <= budget:
        text += "\n\n" + BLOAT_NOTE
    return text, canonical_loss, dropped_extras


def main():
    if len(sys.argv) < 3:
        return 1
    try:
        budget = int(sys.argv[2])
        text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
    except (OSError, ValueError):
        return 1
    if budget <= 0:
        return 3  # nothing can be carried: stay silent rather than emit only footnotes

    sections = split_sections(text)
    if not sections:
        return 3  # nothing filled in: caller stays silent rather than emit a shell

    by_name = {n: (h, b) for n, h, b in sections if n}
    extras = [(h, b) for n, h, b in sections if not n]

    # Allocate against the REAL rendered length. The separators, the per-section
    # truncation notes and the two footnotes are all emitted text and all used to be
    # unbudgeted. Rather than model each of them (which drifts the moment a note changes
    # wording), measure the overshoot and give the allocator that much less to spend.
    # The block is written with a trailing newline, which is emitted text like any other,
    # so the body ceiling is one below the budget. Leaving it out was a silent +1 on 69
    # of 1984 sampled budgets: harmless in isolation, and exactly the kind of "almost"
    # that makes a contract untestable.
    ceiling = budget - 1
    reserve = 0
    body = ""
    canonical_loss = True
    for _ in range(8):
        alloc, extra_alloc = allocate(by_name, extras, ceiling - reserve)
        body, canonical_loss, _dropped_extras = render(
            by_name, extras, alloc, extra_alloc, ceiling
        )
        if len(body) <= ceiling:
            break
        reserve += len(body) - ceiling

    if not body.strip():
        return 3  # only footnotes would be left, which is noise, not a restore

    # Post-condition. Allocation is iterative and could still land over on a pathological
    # input, so the contract is enforced here rather than hoped for. A hard clip is a
    # defect for the reader, hence canonical_loss.
    if len(body) > ceiling:
        body = clip(body, ceiling - 30)[0] + "\n_[hard-clipped at budget]_"
        canonical_loss = True

    sys.stdout.write(body + "\n")
    return 4 if canonical_loss else 0


if __name__ == "__main__":
    sys.exit(main())
