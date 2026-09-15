# As It Was

A World of Warcraft Retail addon for playing one expansion or patch as it was. Later-season quests stay marked so the map does not pull you into content that did not exist yet.

Session notes, git/tag recipe, wow-ui clone, and the in-game test list live in `HANDOFF.md` (this folder). Table rebuild lives in `UPDATE.md`. CurseForge paste is `README.md`.

## Goals

- **Zero story spoilers.** Mark quest markers and UI text that belong to a future patch or season relative to the player's chosen milestone. Never block taking a quest.
- **Universal coverage.** Track all quests, including minor side quests, filling gaps left by story-tree addons such as BtWQuests.
- **Lightweight.** No heavy runtime database work and no dependency on addons such as All The Things.
- **Client-derived data.** Quest-to-patch mapping comes from Blizzard client files, not third-party websites or guessed zone timelines.

## Architecture

The project splits into a static offline parser and a live runtime UI filter:

`historical client DB2 (wago)` → `tools/build_quest_patches.py` → `data/QuestPatches.lua` → `AsItWas` runtime filter

Display name **As It Was**. Technical name **AsItWas** (folder, toc, Lua global). SavedVariables are **per character** (`AsItWasDB`).

### Data harvesting (offline)

Mechanical. Re-run the script after each retail patch. No AI, no Wowhead scrape.

```bash
python3 tools/build_quest_patches.py
```

- **Source.** Retail `QuestV2` and `QuestPOIBlob` CSVs from wago.tools (Blizzard client tables, newest live build per `X.Y.Z`). Walk starts at **BfA**. Baseline is **7.3.5** (end of Legion, oldest dump on wago live `wow`) so Legion-and-older stay one bucket. Do not start mid-expansion. There is no retail **8.0.0**; BfA launch is **8.0.1**.
- **Assignment.** `patch = later(first QuestV2, first QuestPOIBlob)`. Catches IDs shipped in files early whose map pin appears only with the later patch. Quests with no POI stay `id_only` (weaker). CSV `source=poi_after_id` is the grey/spoiler-bridge set.
- **Output.** `data/quest_patches.csv`, `data/QuestPatches.lua`, `data/PatchList.lua`, `data/quest_patches_meta.json`. The script fails if hardcoded probes (83137, 92924, …) drift. Do not commit or ship `.cache/wago/`.

### Runtime evaluation

The packaged addon ships `data/QuestPatches.lua`. Compare numeric patch codes (`MMmmpp`), not strings. Filter Off marks nothing. Unknown IDs (not in the table) are marked with `?` / `[?]`, not treated as in-range.

**Widget.** One dropdown (Off, Legion and older, whole expansion, each real `X.Y.Z`) plus checkbox **Include older quests**. Internally each dropdown row is `min`/`max`.

- **Include older on:** unmarked if `patch <= max`
- **Include older off:** unmarked if `min <= patch <= max`

Built from the same wago live `X.Y.Z` snapshots as the quest table (8.0.1, 8.1.5, 8.2.5, … — never invent 8.0.0). Dropdown/HUD identity tokens are wiki abbreviations: Legion, BfA, SL, DF, TWW, MN. Full names stay out of those labels.

- **BfA (whole)** → min 8.0.1, max 8.3.7 (all BfA, not Legion, unless Include older is on)
- **BfA 8.0.1** → min = max = 8.0.1
- Same pattern for SL / DF / TWW / MN
- Baseline row **Legion and older** (7.3.5 bucket only; we have no 7.0–7.3 split)

**First-run** (once per character): same dropdown (no Off row) + Include older + Confirm. Close / Esc / No filter = Off, never ask again on that character. Later changes go to Options.

**Options:** Options → AddOns → As It Was. Same dropdown (including Off) + Include older. Applies immediately; no Confirm.

### World map and minimap

Do not delete pins. Overlay era badges on every out-of-range quest pin, not only the classic bang:

- **newer** — `textures/newer.png` (blue up)
- **older** — `textures/older.png` (grey down; only when Include older is off)
- **unknown** — `INV_Misc_QuestionMark`

World-map pin tooltips use the same arrows (or nothing when in range) plus expansion chip + patch. Minimap quest bangs are engine-drawn; the overlay is a custom texture pass using `C_Minimap.GetViewRadius` and instance-space rotation.

Icon art is `Enum.QuestClassification` on the **same questID** (classic `!`, campaign, important, world quest, hub, bonus, threat). Style is display-only. Filter still uses `questID`. AreaPOI / vignette pins without a questID are out of this table.

**Same giver, mixed quests:** if that NPC/pin has at least one known in-range quest, the in-range icon wins. Mixed older+newer with no in-range quest: newer badge.

3D bangs over NPC heads cannot be reliably removed.

### Titles (quest log, tracker, NPC)

Every known quest, in range or not: expansion chip (`textures/chips/<legion|bfa|sl|df|tww|mn>.png`) + `X.Y.Z` + title. Out of range also gets Blizzard's warning icon. Unknown IDs: `?` + `[?]` + title. Rows stay clickable.

### HUD

Active filter under the minimap zone name (`GameFontNormalSmall`). Off hides it. Click opens Options.

### Auto-accept, mass abandon

Auto-accepted seasonal quests get the same mark. No auto-abandon.

**Mass abandon** lives on the quest log settings gear (`MENU_QUEST_MAP_FRAME_SETTINGS`): checkbox **Don't abandon older quests** (default on — only `patch > max`) + **Abandon later quests** + confirm. `/aiw abandon` is the same action. Only the **current character** quest log.

## Maintenance

1. Blizzard ships a new patch (for example 12.2).
2. Run `python3 tools/build_quest_patches.py`.
3. Ship the regenerated Lua with the unchanged UI filter.

## Status

Parser, generated table (~66448 quests, newest `12.1.0.69814`), and addon UI are on disk. Version `0.1.0`. GitHub [Winring/AsItWas](https://github.com/Winring/AsItWas). Icon is `AsItWas.png` — do not overwrite it. In-game verification belongs to the owner.
