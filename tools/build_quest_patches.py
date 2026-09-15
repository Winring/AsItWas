#!/usr/bin/env python3
"""Build QuestID -> patch from historical retail client DB2 dumps.

Re-run whenever a new retail patch exists. No AI, no Wowhead.

  python3 tools/build_quest_patches.py

Source: wago.tools CSV exports of Blizzard tables (same bytes as the client).
For each retail patch X.Y.Z we take the newest `wow` build of that triple.

Assignment (safe for hiding later content):
  patch = later of
    - first snapshot where the ID exists in QuestV2
    - first snapshot where that QuestID exists in QuestPOIBlob
  If the quest never got a map POI, fall back to QuestV2 and mark source=id_only.

Quests already present in the baseline snapshot (newest 7.x, i.e. 7.3.5) are
tagged as that baseline with source=at_or_before — not a real add date.
Walk starts at 8.0.0 (BfA) so we slice whole expansions, not mid-Legion.
"""

from __future__ import annotations

import argparse
import csv
import json
import subprocess
import sys
import time
from pathlib import Path

WAGO_BUILDS = "https://wago.tools/api/builds"
WAGO_CSV = "https://wago.tools/db2/{table}/csv?build={build}"

# Mechanical regression checks from known live vs file dates.
# Fail the run if assignment drifts — means the rule or dumps changed.
PROBES = {
    83137: "11.1.0",  # Undermine start: ID+POI both on 11.1.0
    83151: "11.1.0",
    84876: "11.2.0",  # K'aresh
    84905: "11.2.0",
    92895: "12.0.7",  # Hagar's Invitation, shipped/playable in 12.0.7
    92924: "12.1.0",  # Fog unlock: QuestV2 in 12.0.1, POI only in 12.1.0
    93387: "12.1.0",  # Coiled Isle side quest
}


def patch_tuple(patch: str) -> tuple[int, int, int]:
    a, b, c = patch.split(".")
    return int(a), int(b), int(c)


def patch_code(patch: str) -> int:
    a, b, c = patch_tuple(patch)
    return a * 10000 + b * 100 + c


def later_patch(a: str | None, b: str | None) -> str | None:
    if a is None:
        return b
    if b is None:
        return a
    return a if patch_tuple(a) >= patch_tuple(b) else b


def run_curl(url: str, dest: Path | None = None) -> bytes:
    cmd = ["curl", "-fsSL", "--retry", "3", "--retry-delay", "2", url]
    if dest is not None:
        dest.parent.mkdir(parents=True, exist_ok=True)
        cmd.extend(["-o", str(dest)])
        subprocess.run(cmd, check=True)
        return b""
    return subprocess.check_output(cmd)


def load_wow_snapshots(from_major: int) -> list[tuple[str, str]]:
    """Return [(patch X.Y.Z, newest full build), ...] oldest first, wow live only."""
    data = json.loads(run_curl(WAGO_BUILDS))
    by_patch: dict[str, str] = {}
    for entry in data.get("wow", []):
        version = entry.get("version") or ""
        parts = version.split(".")
        if len(parts) != 4:
            continue
        try:
            major, minor, patch, _build = (int(p) for p in parts)
        except ValueError:
            continue
        if major < from_major:
            continue
        patch_s = f"{major}.{minor}.{patch}"
        prev = by_patch.get(patch_s)
        if prev is None or tuple(int(x) for x in version.split(".")) > tuple(
            int(x) for x in prev.split(".")
        ):
            by_patch[patch_s] = version

    baseline_patch = None
    baseline_build = None
    for entry in data.get("wow", []):
        version = entry.get("version") or ""
        parts = version.split(".")
        if len(parts) != 4:
            continue
        try:
            major, minor, patch, _build = (int(p) for p in parts)
        except ValueError:
            continue
        if major != from_major - 1:
            continue
        patch_s = f"{major}.{minor}.{patch}"
        if baseline_build is None or tuple(int(x) for x in version.split(".")) > tuple(
            int(x) for x in baseline_build.split(".")
        ):
            baseline_patch, baseline_build = patch_s, version

    snapshots: list[tuple[str, str]] = []
    if baseline_patch and baseline_build:
        snapshots.append((baseline_patch, baseline_build))
    snapshots.extend(sorted(by_patch.items(), key=lambda kv: patch_tuple(kv[0])))

    dedup: list[tuple[str, str]] = []
    seen_build: set[str] = set()
    for patch, build in snapshots:
        if build in seen_build:
            continue
        seen_build.add(build)
        dedup.append((patch, build))
    return dedup


def csv_ids(path: Path, column: str) -> set[int]:
    ids: set[int] = set()
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        if column not in (reader.fieldnames or []):
            raise SystemExit(f"{path} has no column {column}: {reader.fieldnames}")
        for row in reader:
            raw = row.get(column) or ""
            if not raw:
                continue
            try:
                qid = int(raw)
            except ValueError:
                continue
            if qid > 0:
                ids.add(qid)
    return ids


def download_table(cache: Path, table: str, build: str, sleep_s: float) -> Path:
    dest = cache / table / f"{build}.csv"
    if dest.exists() and dest.stat().st_size > 0:
        return dest
    url = WAGO_CSV.format(table=table, build=build)
    print(f"  download {table} {build}", flush=True)
    run_curl(url, dest)
    if sleep_s > 0:
        time.sleep(sleep_s)
    return dest


def source_label(
    assigned: str,
    id_first: str,
    poi_first: str | None,
    baseline: str,
) -> str:
    if id_first == baseline and assigned == baseline:
        return "at_or_before"
    if poi_first is None:
        return "id_only"
    if patch_tuple(poi_first) > patch_tuple(id_first):
        return "poi_after_id"
    return "poi"


def write_csv(
    path: Path,
    rows: list[tuple[int, str, str, str | None, str]],
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            ["quest_id", "patch", "patch_code", "id_first", "poi_first", "source"]
        )
        for quest_id, patch, id_first, poi_first, src in rows:
            writer.writerow(
                [
                    quest_id,
                    patch,
                    patch_code(patch),
                    id_first,
                    poi_first or "",
                    src,
                ]
            )


def write_lua(
    path: Path,
    rows: list[tuple[int, str, str, str | None, str]],
    newest_build: str,
    snapshots: list[tuple[str, str]],
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    snap = ", ".join(f"{p}={b}" for p, b in snapshots)
    lines = [
        "-- Generated by tools/build_quest_patches.py. Do not edit.",
        f"-- Newest retail snapshot: {newest_build}",
        "-- Patch codes are MMmmpp (12.1.0 = 120100).",
        "-- Value is the later of first QuestV2 and first QuestPOIBlob on live wow.",
        f"-- Snapshots: {snap}",
        "AsItWasQuestPatchNewestBuild = " + json.dumps(newest_build),
        "AsItWasQuestPatch = {",
    ]
    for quest_id, patch, _id_first, _poi_first, _src in rows:
        lines.append(f"[{quest_id}]={patch_code(patch)},")
    lines.append("}")
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def write_patch_list(
    path: Path,
    snapshots: list[tuple[str, str]],
    newest_build: str,
    baseline: str,
) -> None:
    """Snapshot list. Addon builds whole-expansion + per-patch dropdown rows."""
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "-- Generated by tools/build_quest_patches.py. Do not edit.",
        "-- Live retail wow X.Y.Z (newest build of each triple on wago.tools).",
        f"-- Newest retail snapshot: {newest_build}",
        f"-- Baseline: {baseline}",
        "AsItWasPatches = {",
    ]
    for patch, build in snapshots:
        lines.append(
            f'    {{patch="{patch}", code={patch_code(patch)}, build="{build}"}},'
        )
    lines.append("}")
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def verify(assigned: dict[int, str]) -> list[str]:
    failures = []
    for quest_id, expected in PROBES.items():
        got = assigned.get(quest_id)
        if got != expected:
            failures.append(f"  {quest_id}: expected {expected}, got {got}")
    return failures


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-dir", type=Path, default=root / ".cache" / "wago")
    parser.add_argument("--out-dir", type=Path, default=root / "data")
    parser.add_argument(
        "--from-major",
        type=int,
        default=8,
        help="First expansion major to walk (8=BfA). Baseline is newest 7.x (7.3.5).",
    )
    parser.add_argument("--sleep", type=float, default=0.25)
    parser.add_argument(
        "--skip-verify",
        action="store_true",
        help="Do not fail on hardcoded probe mismatches.",
    )
    args = parser.parse_args()

    print("Loading wago retail build list…", flush=True)
    snapshots = load_wow_snapshots(args.from_major)
    if len(snapshots) < 2:
        print("Need at least baseline + one later patch.", file=sys.stderr)
        return 1
    baseline = snapshots[0][0]
    print(f"Snapshots ({len(snapshots)}), baseline {baseline}:", flush=True)
    for patch, build in snapshots:
        print(f"  {patch:8}  {build}", flush=True)

    id_first: dict[int, str] = {}
    poi_first: dict[int, str] = {}
    seen_ids: set[int] = set()
    seen_poi: set[int] = set()

    for patch, build in snapshots:
        print(f"Scan {patch} ({build})", flush=True)
        qv2 = download_table(args.cache_dir, "QuestV2", build, args.sleep)
        poi = download_table(args.cache_dir, "QuestPOIBlob", build, args.sleep)
        ids = csv_ids(qv2, "ID")
        pois = csv_ids(poi, "QuestID")
        new_ids = ids - seen_ids
        new_poi = pois - seen_poi
        for qid in new_ids:
            id_first[qid] = patch
        for qid in new_poi:
            poi_first[qid] = patch
        seen_ids |= ids
        seen_poi |= pois
        print(
            f"  +{len(new_ids)} ids, +{len(new_poi)} poi quests "
            f"(now {len(seen_ids)} ids, {len(seen_poi)} with poi)",
            flush=True,
        )

    rows: list[tuple[int, str, str, str | None, str]] = []
    assigned: dict[int, str] = {}
    counts = {"poi": 0, "id_only": 0, "poi_after_id": 0, "at_or_before": 0}
    for qid in sorted(id_first):
        first_id = id_first[qid]
        first_poi = poi_first.get(qid)
        patch = later_patch(first_id, first_poi) or first_id
        src = source_label(patch, first_id, first_poi, baseline)
        counts[src] = counts.get(src, 0) + 1
        assigned[qid] = patch
        rows.append((qid, patch, first_id, first_poi, src))

    args.out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = args.out_dir / "quest_patches.csv"
    lua_path = args.out_dir / "QuestPatches.lua"
    meta_path = args.out_dir / "quest_patches_meta.json"
    write_csv(csv_path, rows)
    write_lua(lua_path, rows, snapshots[-1][1], snapshots)
    patch_list_path = args.out_dir / "PatchList.lua"
    write_patch_list(patch_list_path, snapshots, snapshots[-1][1], baseline)
    meta_path.write_text(
        json.dumps(
            {
                "newest_build": snapshots[-1][1],
                "baseline": baseline,
                "snapshots": [{"patch": p, "build": b} for p, b in snapshots],
                "quest_count": len(rows),
                "counts": counts,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    print(f"Wrote {csv_path} ({len(rows)} quests)")
    print(f"Wrote {lua_path}")
    print(f"Wrote {patch_list_path}")
    print("Sources:", counts)

    failures = verify(assigned)
    if failures:
        print("Probe mismatches:", file=sys.stderr)
        print("\n".join(failures), file=sys.stderr)
        if not args.skip_verify:
            return 1
    else:
        print("Probes ok:", ", ".join(f"{k}={v}" for k, v in PROBES.items()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
