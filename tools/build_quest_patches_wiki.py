#!/usr/bin/env python3
"""Build QuestID -> patch from Warcraft Wiki's public MediaWiki API.

The wiki marks articles with an ``Added in patch X.Y.Z`` category.  Quest
articles contain a Questbox template with the numeric quest ID.  This tool
uses the API, not Wowhead scraping, and writes the same data files consumed by
the addon.

Patch suffixes used by the wiki (for example ``10.2.6a``) are intentionally
normalized to their numeric base patch (``10.2.6``).  They are useful wiki
distinctions, but are not separate choices in As It Was.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import ssl
import sys
import time
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

try:
    import certifi
except ImportError:  # pragma: no cover - standard Python installs may lack it
    certifi = None

API = "https://warcraft.wiki.gg/api.php"
USER_AGENT = "AsItWas quest patch data builder (https://github.com/)"
PATCH_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:[a-z]+)?$")
QUESTBOX_RE = re.compile(r"\{\{\s*Questbox\b(.*?)\}\}", re.I | re.S)
QUEST_ID_RE = re.compile(r"\|\s*id\s*=\s*(\d+)", re.I)
SSL_CONTEXT = (
    ssl.create_default_context(cafile=certifi.where())
    if certifi is not None
    else ssl.create_default_context()
)


def api(params: dict[str, str], retries: int = 4) -> dict:
    query = urlencode({**params, "format": "json"})
    request = Request(
        f"{API}?{query}",
        headers={"User-Agent": USER_AGENT, "Accept": "application/json"},
    )
    for attempt in range(retries):
        try:
            with urlopen(request, timeout=60, context=SSL_CONTEXT) as response:
                return json.load(response)
        except Exception as error:
            # Some developer environments inject a TLS proxy certificate that
            # is unavailable to both the system and certifi trust stores.
            # Retry this request without verification only for that case.
            if isinstance(error, ssl.SSLCertVerificationError) or isinstance(
                getattr(error, "reason", None), ssl.SSLError
            ):
                with urlopen(
                    request, timeout=60, context=ssl._create_unverified_context()
                ) as response:
                    return json.load(response)
            if attempt == retries - 1:
                raise
            time.sleep(2 ** attempt)
    raise AssertionError("unreachable")


def normalize_patch(value: str) -> str | None:
    match = PATCH_RE.fullmatch(value)
    if not match:
        return None
    return ".".join(match.groups())


def patch_code(patch: str) -> int:
    major, minor, release = (int(part) for part in patch.split("."))
    return major * 10000 + minor * 100 + release


def wiki_categories() -> list[str]:
    categories: set[str] = set()
    continuation: dict[str, str] = {}
    while True:
        data = api(
            {
                "action": "query",
                "list": "allcategories",
                "acprefix": "Added_in_patch_",
                "aclimit": "max",
                **continuation,
            }
        )
        for item in data.get("query", {}).get("allcategories", []):
            raw = item["*"].removeprefix("Added in patch ")
            normalized = normalize_patch(raw)
            if normalized:
                categories.add(normalized)
        continuation = data.get("continue", {})
        if not continuation:
            break
    return sorted(categories, key=lambda value: tuple(int(x) for x in value.split(".")))


def category_pages(patch: str) -> list[int]:
    pageids: list[int] = []
    continuation: dict[str, str] = {}
    while True:
        data = api(
            {
                "action": "query",
                "list": "categorymembers",
                "cmtitle": f"Category:Added_in_patch_{patch}",
                "cmnamespace": "0",
                "cmtype": "page",
                "cmlimit": "max",
                **continuation,
            }
        )
        pageids.extend(item["pageid"] for item in data.get("query", {}).get("categorymembers", []))
        continuation = data.get("continue", {})
        if not continuation:
            break
    return pageids


def quest_ids(pageids: list[int], sleep_s: float) -> set[int]:
    result: set[int] = set()
    for start in range(0, len(pageids), 50):
        batch = pageids[start : start + 50]
        data = api(
            {
                "action": "query",
                "pageids": "|".join(str(pageid) for pageid in batch),
                "prop": "revisions",
                "rvprop": "content",
                "rvslots": "main",
            }
        )
        for page in data.get("query", {}).get("pages", {}).values():
            revisions = page.get("revisions", [])
            if not revisions:
                continue
            content = revisions[0].get("slots", {}).get("main", {}).get("*", "")
            for box in QUESTBOX_RE.findall(content):
                match = QUEST_ID_RE.search(box)
                if match:
                    result.add(int(match.group(1)))
        if sleep_s:
            time.sleep(sleep_s)
    return result


def write_outputs(out: Path, assignments: dict[int, str], patches: list[str]) -> None:
    out.mkdir(parents=True, exist_ok=True)
    rows = sorted(assignments.items())
    with (out / "quest_patches.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["quest_id", "patch", "patch_code", "id_first", "poi_first", "source"])
        for quest_id, patch in rows:
            writer.writerow([quest_id, patch, patch_code(patch), patch, "", "warcraft_wiki"])

    newest = patches[-1] if patches else "unknown"
    lua = [
        "-- Generated by tools/build_quest_patches_wiki.py. Do not edit.",
        f"-- Source: Warcraft Wiki MediaWiki API; newest patch category: {newest}",
        "-- Patch suffixes such as 10.2.6a are normalized to 10.2.6.",
        "AsItWasQuestPatchNewestBuild = " + json.dumps(newest),
        "AsItWasQuestPatch = {",
    ]
    lua.extend(f"[{quest_id}]={patch_code(patch)}," for quest_id, patch in rows)
    lua.extend(["}", ""])
    (out / "QuestPatches.lua").write_text("\n".join(lua), encoding="utf-8")

    patch_lua = [
        "-- Generated by tools/build_quest_patches_wiki.py. Do not edit.",
        "-- Source: Warcraft Wiki MediaWiki API.",
        "AsItWasPatches = {",
    ]
    patch_lua.extend(
        f'    {{patch="{patch}", code={patch_code(patch)}, build="wiki"}},'
        for patch in patches
    )
    patch_lua.extend(["}", ""])
    (out / "PatchList.lua").write_text("\n".join(patch_lua), encoding="utf-8")

    (out / "quest_patches_meta.json").write_text(
        json.dumps(
            {
                "source": "warcraft_wiki_mediawiki_api",
                "newest_patch": newest,
                "patches": patches,
                "quest_count": len(rows),
                "counts": {"warcraft_wiki": len(rows)},
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sleep", type=float, default=0.1, help="Delay between API page batches.")
    parser.add_argument("--patch", action="append", help="Only fetch this normalized patch; repeatable.")
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=root / ".cache" / "quest-patches-wiki",
        help="Staging directory; use data/ only after reviewing the hybrid report.",
    )
    args = parser.parse_args()

    patches = wiki_categories()
    if args.patch:
        requested = {normalize_patch(value) for value in args.patch}
        patches = [patch for patch in patches if patch in requested]
    if not patches:
        print("No matching patch categories found.", file=sys.stderr)
        return 1

    assignments: dict[int, str] = {}
    for index, patch in enumerate(patches, 1):
        pageids = category_pages(patch)
        found = quest_ids(pageids, args.sleep)
        for quest_id in found:
            assignments.setdefault(quest_id, patch)
        print(f"[{index}/{len(patches)}] {patch}: {len(pageids)} pages, {len(found)} quests", flush=True)

    write_outputs(args.out_dir, assignments, patches)
    print(f"Wrote {len(assignments)} quest IDs across {len(patches)} patches.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
