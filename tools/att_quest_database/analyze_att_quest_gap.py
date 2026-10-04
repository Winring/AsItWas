#!/usr/bin/env python3
"""Measure the direct quest export produced by ATT's C# parser."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def analyze(path: Path) -> dict[str, object]:
    values = {int(k): v for k, v in json.loads(path.read_text(encoding="utf-8")).items()}
    with_awp = {quest_id for quest_id, awps in values.items() if awps}
    without_awp = set(values) - with_awp
    return {
        "source": str(path),
        "unique_quest_ids": len(values),
        "unique_quest_ids_with_awp": len(with_awp),
        "unique_quest_ids_without_awp": len(without_awp),
        "quest_ids_without_awp": sorted(without_awp),
        "quest_ids_with_awp": sorted(with_awp),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("att", type=Path, help="ATT git checkout")
    parser.add_argument("--json-out", type=Path, help="Optional JSON report path")
    args = parser.parse_args()
    att = Path(str(args.att).strip().strip('"')).resolve()
    source = att / "db" / "Standard" / "QuestPatches.att.json"
    if not source.exists():
        raise SystemExit(f"ATT direct quest export not found: {source}; run the database builder first")
    report = analyze(source)
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in report.items() if not key.startswith("quest_ids_")}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
