#!/usr/bin/env python3
"""Run ATT's own parser and export its processed questID -> awp database.

Usage:
    python3 tools/build_att_quest_database.py /path/to/att

The ATT checkout is the source of truth. This script does not interpret ATT
source Lua or reimplement ATT processing; it installs a tiny exporter into the
C# parser shipped in ``.contrib/Source Code/Parser`` and reads the JSON emitted
by ATT immediately after ``Framework.Process()``.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import shutil
import subprocess
import time
from pathlib import Path

def parser_paths(att: Path) -> tuple[Path, Path, Path]:
    parser_dir = att / ".contrib" / "Source Code" / "Parser"
    project = parser_dir / "Parser.csproj"
    output = att / ".contrib" / ".tools" / "Parser.exe"
    final_db = att / "db" / "Standard"
    if not project.exists():
        raise SystemExit(f"ATT parser project not found: {project}")
    return parser_dir, output, final_db


def install_direct_export(parser_dir: Path) -> bool:
    """Install the small ATT-side exporter and wire it into Program.cs."""
    changed = False
    bundle_source = Path(__file__).with_name("QuestPatchExport.cs")
    if not bundle_source.exists():
        bundle_source = Path(__file__).parent / "att_quest_database" / "QuestPatchExport.cs"
    target = parser_dir / "QuestPatchExport.cs"
    source_text = bundle_source.read_text(encoding="utf-8")
    if not target.exists() or target.read_text(encoding="utf-8") != source_text:
        target.write_text(source_text, encoding="utf-8")
        changed = True
    project = parser_dir / "Parser.csproj"
    text = project.read_text(encoding="utf-8-sig")
    if 'Compile Include="QuestPatchExport.cs"' not in text:
        text = text.replace('    <Compile Include="Program.cs" />', '    <Compile Include="Program.cs" />\n    <Compile Include="QuestPatchExport.cs" />')
        project.write_text(text, encoding="utf-8")
        changed = True
    program = parser_dir / "Program.cs"
    source = program.read_text(encoding="utf-8-sig")
    marker = "                Framework.Export(addonRootFolder, dbRootFolder, outputFolder);"
    call = "                QuestPatchExport.Export(outputFolder.FullName);\n\n" + marker
    if "QuestPatchExport.Export(outputFolder.FullName);" not in source:
        if marker not in source:
            raise SystemExit(f"ATT parser Program.cs does not contain export marker: {program}")
        program.write_text(source.replace(marker, call), encoding="utf-8")
        changed = True
    return changed


def build_parser(parser_dir: Path, no_build: bool, force_build: bool = False) -> Path:
    exe = parser_dir.parent.parent / ".tools" / "Parser.exe"
    source_changed = install_direct_export(parser_dir)
    if exe.exists() and not source_changed and not force_build:
        return exe
    if no_build:
        raise SystemExit(f"ATT parser executable not found: {exe}")
    builder = shutil.which("msbuild") or shutil.which("xbuild")
    if not builder and os.name == "nt":
        roots = {
            Path(os.environ.get("ProgramFiles", r"C:\Program Files")),
            Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")),
        }
        candidates = [
            root / "Microsoft Visual Studio" / year / edition / "MSBuild" / "Current" / "Bin" / suffix / "MSBuild.exe"
            for root in roots
            for year in ("2022", "2026")
            for edition in ("BuildTools", "Community", "Professional", "Enterprise")
            for suffix in ("", "amd64")
        ]
        builder = next((str(path) for path in candidates if path.exists()), None)
    if not builder:
        raise SystemExit(
            "ATT Parser.exe is not present and neither msbuild nor xbuild is installed. "
            "Build Parser.csproj with MSBuild (Release|x64), then rerun this script."
        )
    subprocess.run(
        [builder, "Parser.csproj", "/p:Configuration=Release", "/p:Platform=x64"],
        cwd=parser_dir,
        check=True,
    )
    if not exe.exists():
        raise SystemExit(f"Build completed but parser executable is missing: {exe}")
    return exe


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    default_root = script_dir.parent.parent if script_dir.parent.name.lower() == "tools" else script_dir
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("att", type=Path, help="ATT git checkout")
    cli.add_argument("--out", type=Path, default=default_root / "data" / "QuestPatches.lua")
    cli.add_argument("--json-out", type=Path, default=default_root / "data" / "quest_patches_att.json")
    cli.add_argument("--csv-out", type=Path, default=default_root / "data" / "quest_patches_att.csv")
    cli.add_argument("--no-build", action="store_true")
    args = cli.parse_args()

    # PowerShell/cmd can pass a literal trailing quote when a relative
    # directory argument ends in a backslash. Normalize it before resolving.
    att = Path(str(args.att).strip().strip('"')).resolve()
    parser_dir, _unused, final_db = parser_paths(att)
    direct_json = final_db / "QuestPatches.att.json"
    print("Building/running ATT parser...", flush=True)
    parser_exe = build_parser(parser_dir, args.no_build, force_build=not direct_json.exists())
    subprocess.run([str(parser_exe), "auto"], cwd=parser_exe.parent, check=True)
    if not direct_json.exists():
        raise SystemExit(f"ATT parser did not produce direct quest export: {direct_json}")
    values = {int(quest_id): sorted(map(int, awps)) for quest_id, awps in json.loads(direct_json.read_text(encoding="utf-8")).items()}
    if not values:
        raise SystemExit("ATT parser output contained no questID objects with awp")

    revision = subprocess.check_output(["git", "-C", str(att), "rev-parse", "HEAD"], text=True).strip()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    values_with_awp = {quest_id: awps for quest_id, awps in values.items() if awps}
    if not values_with_awp:
        raise SystemExit("ATT parser output contained no questID objects with awp")
    # Keep a narrow legacy fallback for BfA+ IDs that ATT does not expose at all.
    # ATT always wins when the same questID exists in both sources.
    fallback_path = args.out.parent / "att_quest_database" / "legacy_wago_fallback.json"
    fallback = {}
    if fallback_path.exists():
        fallback = {int(k): int(v) for k, v in json.loads(fallback_path.read_text(encoding="utf-8")).items()}
        for quest_id, awp in fallback.items():
            values_with_awp.setdefault(quest_id, [awp])
    latest = {quest_id: max(awps) for quest_id, awps in values_with_awp.items()}
    lua = [
        "-- Generated by tools/build_att_quest_database.py. Do not edit.",
        f"-- ATT revision: {revision}",
        'AsItWasQuestPatchNewestBuild = "ATT-parser"',
        "AsItWasQuestPatch = {",
        *(f"[{quest_id}]={awp}," for quest_id, awp in latest.items()),
        "}",
    ]
    args.out.write_text("\n".join(lua) + "\n", encoding="utf-8")
    args.json_out.parent.mkdir(parents=True, exist_ok=True)
    args.json_out.write_text(json.dumps({str(k): {"latest_awp": max(v), "all_awp": v, **({"source": "legacy_wago_fallback", "audit_note": "Added because ATT has no effective awp for this ID."} if k in fallback else {})} for k, v in values_with_awp.items()}, indent=2) + "\n", encoding="utf-8")
    with args.csv_out.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["quest_id", "latest_awp", "all_awp", "source"])
        writer.writerows((quest_id, max(awps), "|".join(map(str, awps)), "legacy_wago_fallback" if quest_id in fallback else "ATT") for quest_id, awps in values_with_awp.items())
    print(f"Writing database: {len(values_with_awp)} quests, {sum(len(v) > 1 for v in values_with_awp.values())} with multiple awp values", flush=True)
    print(json.dumps({"att_revision": revision, "quests": len(values_with_awp), "quest_ids_seen": len(values), "quest_ids_without_awp": sum(not v for v in values.values()), "multi_awp_quests": sum(len(v) > 1 for v in values_with_awp.values()), "output": str(args.out)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
