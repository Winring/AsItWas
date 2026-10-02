#!/usr/bin/env python3
"""Extract the useful part of ATT's committed quest database.

This is deliberately an audit/import helper, not a Wowhead harvester.  ATT's
database is Lua and frequently puts a timeline on a parent ``bubbleDown``
group, so a regular expression over ``q(...)`` entries would miss most of the
available information.

The script writes a supplementary CSV and a JSON report.  It never changes
the addon's generated data files.  ATT is distributed under MIT (see its
repository LICENSE); keep the source revision in the report when publishing
an extracted file.

Example:
  python3 tools/analyze_att_quest_patches.py /path/to/AllTheThings/.contrib/.db
"""

from __future__ import annotations

import argparse
import bisect
import csv
import json
import re
import subprocess
from collections import Counter, defaultdict
from pathlib import Path

# ATT uses semantic suffixes such as _LAUNCH, _SEASONSTART and _PHASEONE.
# They describe the release event, while As It Was stores the numeric patch.
PATCH_RE = re.compile(r"^ADDED_(\d+)_(\d+)_(\d+)(?:_[A-Z0-9]+)*$")
TOKEN_RE = re.compile(
    r"--[^\n]*|\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|[A-Za-z_][A-Za-z0-9_]*|\d+|[^\s]",
)


def patch_name(token: str) -> str | None:
    match = PATCH_RE.fullmatch(token)
    return ".".join(match.groups()) if match else None


def tokens(text: str) -> list[str]:
    # Strip Lua long comments separately; keeping this out of TOKEN_RE avoids
    # catastrophic backtracking on large files containing an unfinished/comment
    # marker that resembles a long comment.
    text = re.sub(r"--\[\[.*?\]\]", "", text, flags=re.S)
    return [token for token in TOKEN_RE.findall(text) if not token.startswith("--")]


def matching_braces(items: list[str]) -> dict[int, int]:
    stack: list[int] = []
    pairs: dict[int, int] = {}
    for index, token in enumerate(items):
        if token == "{":
            stack.append(index)
        elif token == "}" and stack:
            opening = stack.pop()
            pairs[opening] = index
    return pairs


def matching_parentheses(items: list[str]) -> dict[int, int]:
    stack: list[int] = []
    pairs: dict[int, int] = {}
    for index, token in enumerate(items):
        if token == "(":
            stack.append(index)
        elif token == ")" and stack:
            opening = stack.pop()
            pairs[opening] = index
    return pairs


def timeline_in(start: int, end: int, item: list[str], positions: list[int]) -> set[str]:
    found: set[str] = set()
    for position in positions[bisect.bisect_left(positions, start) : bisect.bisect_left(positions, end)]:
        value = patch_name(item[position])
        if value:
            found.add(value)
    return found


def extract_file(path: Path, retail_only: bool = True) -> dict[int, set[tuple[str, str]]]:
    text = path.read_text(encoding="utf-8", errors="replace")
    # Most ATT files are unrelated item/achievement data.  Avoid tokenizing
    # multi-megabyte generated files when they cannot contain q(ID, ...).
    if "q(" not in text and "q (" not in text:
        return defaultdict(set)
    item = tokens(text)
    pairs = matching_braces(item)
    parentheses = matching_parentheses(item)
    excluded_ranges: list[tuple[int, int]] = []
    if retail_only:
        # These wrappers select data for a Classic client/phase.  They are
        # distinct from the ordinary expansion(EXPANSION.CATA/...) wrappers:
        # the latter describe the original Retail release and must remain.
        classic_calls = {"applyclassicphase"}
        for index, name in enumerate(item):
            if name == "expansion" and index + 3 < len(item):
                if item[index + 1] == "(" and item[index + 2] == "EXPANSION" and item[index + 3] == ".":
                    if index + 4 < len(item) and item[index + 4] == "CLASSIC":
                        classic_calls.add("expansion")
            if name not in classic_calls or index + 1 >= len(item) or item[index + 1] != "(":
                continue
            end = parentheses.get(index + 1)
            if end is not None:
                excluded_ranges.append((index, end + 1))

    def is_excluded(position: int) -> bool:
        return any(start <= position < end for start, end in excluded_ranges)

    timeline_positions = [index for index, value in enumerate(item) if value.startswith("ADDED_")]
    result: dict[int, set[tuple[str, str]]] = defaultdict(set)

    # Direct q(ID, { ... timeline ... }) values.
    q_ranges: list[tuple[int, int, int]] = []
    for index in range(len(item) - 2):
        if item[index] != "q" or item[index + 1] != "(" or not item[index + 2].isdigit():
            continue
        quest_id = int(item[index + 2])
        if is_excluded(index):
            continue
        opening = next((n for n in range(index + 3, min(index + 15, len(item))) if item[n] == "{"), None)
        if opening is not None and opening in pairs:
            q_ranges.append((quest_id, opening, pairs[opening]))
            for patch in timeline_in(opening, pairs[opening] + 1, item, timeline_positions):
                result[quest_id].add((patch, "direct"))

    # Parent metadata table followed by a child/content table.  ATT uses this
    # shape for bubbleDown*, timelineSelf, and similar helpers.  The bounded
    # search avoids treating unrelated later tables as children.
    wrappers = {"bubbleDown", "bubbleDownSelf", "timelineSelf", "timeline"}
    starts = [q_open for _quest_id, q_open, _q_end in q_ranges]
    for index, name in enumerate(item):
        if name not in wrappers or index + 1 >= len(item) or item[index + 1] != "(":
            continue
        first = next((n for n in range(index + 2, min(index + 80, len(item))) if item[n] == "{"), None)
        if first is None or first not in pairs:
            continue
        first_end = pairs[first]
        patches = timeline_in(first, first_end + 1, item, timeline_positions)
        if not patches:
            continue
        second = next((n for n in range(first_end + 1, min(first_end + 80, len(item))) if item[n] == "{"), None)
        if second is None or second not in pairs:
            continue
        second_end = pairs[second]
        # q_ranges is in source order, so only inspect the interval covered by
        # this wrapper.  This matters for ATT's several-thousand-entry files.
        left = bisect.bisect_right(starts, second)
        right = bisect.bisect_left(starts, second_end)
        for quest_id, _q_open, _q_end in q_ranges[left:right]:
            if is_excluded(_q_open):
                continue
            for patch in patches:
                result[quest_id].add((patch, "inherited"))
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("att_db", type=Path, help="ATT checkout's .contrib/.db directory")
    parser.add_argument("--out", type=Path, default=Path("att_quest_patches"))
    parser.add_argument(
        "--include-classic",
        action="store_true",
        help="Include ATT data wrapped for Classic clients/phases (not recommended)",
    )
    args = parser.parse_args()
    files = sorted(args.att_db.rglob("*.lua"))
    candidates: dict[int, set[tuple[str, str]]] = defaultdict(set)
    for path in files:
        for quest_id, values in extract_file(path, retail_only=not args.include_classic).items():
            candidates[quest_id].update(values)

    att_root = args.att_db.parent.parent
    try:
        revision = subprocess.check_output(
            ["git", "-C", str(att_root), "rev-parse", "HEAD"], text=True
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        revision = None

    assignments = {}
    conflicts = {}
    for quest_id, values in candidates.items():
        patches = sorted({patch for patch, _source in values}, key=lambda p: tuple(map(int, p.split("."))))
        direct = sorted({patch for patch, source in values if source == "direct"}, key=lambda p: tuple(map(int, p.split("."))))
        if len(patches) > 1:
            conflicts[quest_id] = patches
        # An explicit quest timeline is stronger than inherited group context.
        if len(direct) == 1:
            assignments[quest_id] = (direct[0], "direct")
        elif direct:
            # After Classic branches are removed, an ID can still have several
            # Retail timelines (for example, a reused quest ID).  Keep the
            # latest explicit ATT timeline rather than dropping the ID.
            assignments[quest_id] = (direct[-1], "direct_conflict_latest")
        elif len(patches) == 1:
            assignments[quest_id] = (patches[0], "inherited")
        elif patches:
            assignments[quest_id] = (patches[-1], "inherited_conflict_latest")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    csv_path = args.out.with_suffix(".csv")
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["quest_id", "patch", "source", "all_candidates"])
        for quest_id in sorted(assignments):
            patch, source = assignments[quest_id]
            all_values = sorted({p for p, _ in candidates[quest_id]}, key=lambda p: tuple(map(int, p.split("."))))
            writer.writerow([quest_id, patch, source, "|".join(all_values)])

    report = {
        "source": "ATT committed database",
        "input": str(args.att_db),
        "revision": revision,
        "license": "MIT (ATT repository LICENSE)",
        "lua_files": len(files),
        "quest_candidates": len(candidates),
        "assignments": len(assignments),
        "direct_assignments": sum(source.startswith("direct") for _, source in assignments.values()),
        "inherited_assignments": sum(source.startswith("inherited") for _, source in assignments.values()),
        "conflicts": len(conflicts),
        "conflict_examples": {str(k): v for k, v in sorted(conflicts.items())[:50]},
        "patch_counts": dict(Counter(patch for patch, _ in assignments.values())),
    }
    args.out.with_suffix(".json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
