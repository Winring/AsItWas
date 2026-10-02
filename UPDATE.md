# Updating the quest-to-patch table

Re-run this after every new live retail patch. Mechanical only: no AI, no Wowhead scrape.

```bash
python3 tools/build_quest_patches.py
```

Needs `python3` and `curl`. Downloads go to `.cache/wago/` (gitignored). Never commit or ship those CSVs. Never republish wago's table layout. The addon ships only the derived integer map.

## What it writes

* `data/QuestPatches.lua` — QuestID → patch code (`12.1.0` = `120100`). This is what the addon loads.
* `data/PatchList.lua` — live `X.Y.Z` snapshots for the dropdown.
* `data/quest_patches.csv` and `data/quest_patches_meta.json` — maintainer copies, not loaded by the client.

Ship the regenerated Lua with the same UI. Do not hand-edit generated files.

Until the table is rebuilt, quests added after the last snapshot show as unknown (`?` / `[?]`) in the UI. That is expected, not a filter bug.

## Source and rule

Retail `wow` builds from [wago.tools](https://wago.tools) (same bytes as the client). For each `X.Y.Z`, the newest live build of that triple.

Walk starts at Battle for Azeroth. Baseline is **7.3.5** (oldest live dump, Legion-and-older as one bucket). There is no 8.0.0 on retail; BfA launch is **8.0.1**.

Assignment:

```text
patch = later(first QuestV2, first QuestPOIBlob)
```

Quests with no map POI stay `id_only`. IDs that appear in files before their pin is `poi_after_id` (grey / spoiler-bridge). Baseline leftovers are `at_or_before`, not a real add date.

## Checks

The script fails if these probes drift. That means the rule or the dumps changed — fix the cause, do not skip unless you are debugging with `--skip-verify`.

| QuestID | Expected patch |
| --- | --- |
| 83137, 83151 | 11.1.0 |
| 84876, 84905 | 11.2.0 |
| 92895 | 12.0.7 |
| 92924, 93387 | 12.1.0 |

Useful flags: `--from-major 8` (default), `--cache-dir`, `--out-dir`.

## Supplementing Legion and older quests

Wago's retail history is still the primary source. Its oldest retail snapshot
is 7.3.5, however, so its `at_or_before` rows do not distinguish Legion and
older patches. The supplementary workflow below uses committed ATT database
data and the public Warcraft Wiki API. It does not scrape Wowhead.

The commands intentionally write to `.cache/` first. Review
`quest_patches_meta.json` and `quest_patches_conflicts.json` before writing to
`data/`.

1. Obtain a local ATT checkout (the repository is MIT-licensed):

   ```bash
   git clone --depth 1 --filter=blob:none \
     https://github.com/ATTWoWAddon/AllTheThings.git .cache/AllTheThings
   ```

2. Extract direct and inherited ATT timelines:

   ```bash
   python3 tools/analyze_att_quest_patches.py \
     .cache/AllTheThings/.contrib/.db \
     --out .cache/att-quest-patches
   ```

   This produces `.csv` and `.json`. By default the parser is Retail-only: it
   excludes data inside ATT's `applyclassicphase(...)` and
   `expansion(EXPANSION.CLASSIC, ...)` branches. Use `--include-classic` only
   for a separate audit. ATT timeline suffixes such as `_LAUNCH`,
   `_SEASONSTART`, and `_PHASEONE` are normalized to their numeric patch.
   Ambiguous IDs are reported, not guessed.

3. Fetch the Wiki's explicit `Added in patch` categories into staging:

   ```bash
   python3 tools/build_quest_patches_wiki.py \
     --out-dir .cache/quest-patches-wiki
   ```

4. Build and inspect the hybrid result:

   ```bash
   python3 tools/build_quest_patches_hybrid.py \
     --att .cache/att-quest-patches.csv \
     --wiki .cache/quest-patches-wiki/quest_patches.csv \
     --out-dir .cache/quest-patches-hybrid
   cat .cache/quest-patches-hybrid/quest_patches_meta.json
   cat .cache/quest-patches-hybrid/quest_patches_conflicts.json
   ```

   `unresolved_candidate_ids` only checks coverage of the union of the input
   Wago, ATT, and Wiki CSVs. It is not a proof that the sources contain every
   Retail quest ID.

   Precedence is: exact Wago row, direct ATT timeline, inherited ATT timeline,
   explicit Wiki row, then the original Wago baseline. When ATT has several
   Retail candidates, the latest candidate is selected and the ambiguity stays
   in the audit report. An ATT/Wiki disagreement selects ATT and remains listed
   as a conflict for review.

5. After review, promote the staged four data files:

   ```bash
   cp .cache/quest-patches-hybrid/{QuestPatches.lua,PatchList.lua,quest_patches.csv,quest_patches_meta.json} data/
   ```

   Do not copy `quest_patches_conflicts.json` into the addon data directory;
   it is a maintainer audit artifact.
