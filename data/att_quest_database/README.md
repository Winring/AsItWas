# ATT quest database snapshot

Canonical ATT-parser snapshot copied from `Downloads/data (4).zip` on 2026-10-04.

- `QuestPatches.lua` — addon-ready `questID -> latest awp` mapping
- `quest_patches_att.json` — final mapping with `latest_awp` and all distinct `awp` values
- `quest_patches_att.csv` — tabular copy of the final mapping
- `QuestPatches.att.json` — ATT intermediate output, including IDs without `awp`

The snapshot contains 55,667 IDs with `awp`; the intermediate output contains
58,696 processed `questID` objects, including 3,029 without `awp`.
