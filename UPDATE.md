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
