# As It Was — handoff notes

Working notes for whoever picks this up next. This file sits in `MK/AsItWas/` next to the addon.
It is **not** listed in `AsItWas.toc`, so the client never loads it. GitHub is
[Winring/AsItWas](https://github.com/Winring/AsItWas). The owner may later move this file out of
the tree like MemoryKeeper's handoff.

Start a session by reading this file, then `SPEC.md` and `UPDATE.md`. Do not implement until the
owner has agreed. Conversation is Czech; code, README, CHANGELOG, UPDATE, SPEC, and this file are
English.

The Cursor workspace is often `MK/MemoryKeeper/MemoryKeeper`. **As It Was is not that repo.** Addon
code is this folder. Do not write As It Was files into MemoryKeeper. Writes from a MemoryKeeper
workspace into `AsItWas/` may need extra permissions (`all`).

## Read this before writing a single line: verify the API against live sources

Work based on a model's memory of the WoW API is garbage. The API changes every patch. **Look it
up. Every time. Even for things that feel obvious.**

Where to look, in order of authority:

1. **Blizzard's own UI source** — ground truth. Mirror: `https://github.com/Gethe/wow-ui-source`,
   branch `live`. Keep a **local clone** and grep that. Do **not** clone the whole tree every
   session.

   The clone lives at **`E:\Tvorba Her\Addony\wow-ui-source`** (owner's machine, PowerShell).
   Moved there on 16 September 2026 out of `%TEMP%\wowui`, which Windows cleanup can wipe.

   ```powershell
   $CLONE = 'E:\Tvorba Her\Addony\wow-ui-source'
   git -C $CLONE fetch --depth 1 origin live
   git -C $CLONE checkout --detach origin/live
   ```

   **Never re-clone if that folder already has `.git` — fetch/reset only.** The owner has
   already said not to clone wow-ui again when it is there. Only if the folder is gone:
   `git clone --depth 1 --branch live https://github.com/Gethe/wow-ui-source $CLONE`.

   Generated API docs: `Interface/AddOns/Blizzard_APIDocumentationGenerated/`. Usage:
   `Interface/AddOns/Blizzard_*`. How Blizzard calls a function beats wiki and training data.
   For this addon, the files that already settled behaviour are:

   * `Blizzard_Menu` — `WowStyle1DropdownTemplate`, `DropdownButtonMixin:SetupMenu`,
     `Menu.ModifyMenu`, `SetScrollMode`
   * `Blizzard_Settings_Shared` — `Settings.RegisterCanvasLayoutCategory`,
     `Settings.OpenToCategory`
   * `Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua` — quest log gear menu tag
     `MENU_QUEST_MAP_FRAME_SETTINGS` (set in `QuestMapFrame_SetupSettingsDropdown`)
   * POI / map pins — `POIButtonMixin`, `QuestOfferPinMixin`, `QuestHubPinMixin`,
     `WorldQuestPinMixin`, `BonusObjectivePinMixin`
   * Gossip / greeting — `GossipSharedQuestButtonMixin.UpdateTitleForQuest`,
     `QuestFrameGreetingPanel_OnShow`. **`CreateFromMixins` copies methods**, so
     `GossipSharedAvailableQuestButtonMixin`, `GossipSharedActiveQuestButtonMixin` and the
     Mainline `Gossip*QuestButtonMixin` tables already hold their own copy when the addon
     loads. Wrapping only the shared table never reaches a single button.
   * Quest titles — `QuestUtils_DecorateQuestText` (log + details),
     `ObjectiveTrackerBlockMixin:SetHeader` (called from
     `QuestObjectiveTrackerMixin:UpdateSingle`). Same copy problem: hook the live module
     frames (`QuestObjectiveTracker`, `CampaignQuestObjectiveTracker`, …), not the mixin.
     `ObjectiveTrackerManager:UpdateAll` is a **dirty** update — a module that is not
     `MarkDirty()` keeps its cached layout and never re-runs `UpdateSingle`
     (`Blizzard_ObjectiveTrackerModule.lua:134`).
   * Minimap overlay — `C_Minimap.GetViewRadius`, `UnitPosition`,
     `C_Map.GetWorldPosFromMapPos`, `GetPlayerFacing` / `rotateMinimap`
   * Which quests actually get an icon — `QuestOfferDataProviderMixin:GetAllQuestOffersForMap`
     (`Blizzard_SharedMapDataProviders/QuestOfferDataProvider.lua`): quest lines
     (`C_QuestLine.GetAvailableQuestLines`), **force-visible**
     (`C_QuestLine.GetForceVisibleQuests` + `GetQuestLineInfo`), then
     `C_TaskQuest.GetQuestsOnMap`, filtered by `ShouldAddQuestOffer` (`inProgress`,
     foreign `startMapID`, `isHidden` without `C_Minimap.IsTrackingHiddenQuests`).
     `C_QuestLog.GetQuestsOnMap` is **accepted** quests only — those draw a blob, not a
     bang, so read it for `C_QuestLog.ReadyForTurnIn` markers only.
   * `Enum.QuestClassification` — pin art only; filter is always `questID`

2. **wago.tools** for the quest→patch table, not for Lua API. Retail live `wow` DB2 CSVs
   (`QuestV2`, `QuestPOIBlob`). See **Data table** below. Do not treat Wowhead “Added in patch”
   as a second gospel; it is the same first-seen-in-files signal.

3. **Warcraft Wiki** for orientation only (`Template:LatestPatchInfo`, `TOC_format`). Frequently
   wrong. Never let it override Blizzard source.

Practical notes: `WebFetch` on the wiki tends to hit Cloudflare; use `WebSearch` or `curl` with
network. **Do not fetch wow-ui-source file-by-file over HTTP.** Python `urllib` SSL to wago failed
in an earlier session; the builder uses `curl`.

### Versions — re-verify at the start of every session

* Local UI clone currently at **12.1.0.69814** (commit `4e3cbb8`, 12 September 2026, branch `live`,
  `version.txt`). `.toc` is `## Interface: 120100`. Five-digit
  scheme: major, two digits minor, two digits patch. Wiki `LatestPatchInfo` can lag.
* Last quest table snapshot: **12.1.0.69814** (`data/quest_patches_meta.json`). Those two build
  numbers can differ; Interface follows the client the owner plays, the table follows newest wago
  live `wow` per `X.Y.Z`.
* Addon version is `## Version: 0.1.0`. **Not released** (no `release0.1.0` tag yet). GitHub
  [Winring/AsItWas](https://github.com/Winring/AsItWas). No CurseForge project ID.
  Author in the toc is `Winring` (same as MemoryKeeper).

## Where the work currently is

**15 September 2026.** GitHub [Winring/AsItWas](https://github.com/Winring/AsItWas) `main`. First in-game
load happened: `RefreshAllDataProviders` during first-run hide, and `seenSetup` must wait until
`ApplyFilter` succeeds. Titles and minimap clocks were missing on that pass; both are hooked now.
Addon icon is `AsItWas.png` next to the toc. **Do not overwrite that png.**

Install path the client expects: `Interface/AddOns/AsItWas/` (folder name must match `AsItWas.toc`).
Copy the whole folder (lua + `textures/`) and `/reload`.

### What is implemented

* Mechanical QuestID → patch table from wago history (`tools/build_quest_patches.py`).
* Filter: one dropdown (Off, Legion and older, each expansion whole, each real `X.Y.Z`) plus
  **Include older quests**. Labels use wiki tokens: Legion, BfA, SL, DF, TWW, MN.
* First-run window once per character; close / Esc / “No filter” = Off. `seenSetup` is set only
  after a successful `ApplyFilter` (a crash on first show can re-open it).
* Options canvas under Options → AddOns → As It Was (`/asitwas` or `/aiw`). Same dropdown +
  checkbox; applies immediately (no Confirm).
* HUD caption under minimap zone text (`GameFontNormalSmall`). Off hides it. Click opens Options.
* Map/minimap pin badges: `textures/newer.png` (later), `textures/older.png` (earlier, when Include
  older is off), `INV_Misc_QuestionMark` (unknown). Minimap bangs are engine-drawn; overlay uses
  `GetViewRadius` every 0.05s and instance-space facing when rotate-minimap is on. The minimap
  pass collects the same offers Blizzard's own provider does, plus turn-ins.
* `/aiw debug` toggles a diagnostic channel (`AsItWasDB.debug`, off by default). `AIW.Debug`
  returns before any `string.format`, because the minimap pass runs from `OnUpdate`. Never leave
  bare `print` in that path.
* Titles (quest log on the map, quest details, tracker, gossip, greeting, progress): expansion chip
  + `X.Y.Z` + name. Out of range adds Blizzard's warning icon. World-map pin tooltips use the
  up/down arrows instead of the warning. Unknown IDs: `?` + `[?]`.
* Expansion chips: `textures/chips/{legion,bfa,sl,df,tww,mn}.png` (AI wordmarks, sliced by alpha,
  not `width/6`).
* Auto-accept: `QUEST_ACCEPTED` chat mark only.
* Mass abandon: quest log settings gear (`Menu.ModifyMenu` on `MENU_QUEST_MAP_FRAME_SETTINGS`) plus
  `/aiw abandon`. Confirm popup. Default **Don't abandon older quests**. Only the **current
  character** quest log (`C_QuestLog.AbandonQuest`). Unknown IDs are not mass-abandoned.

### SavedVariables (per character)

Toc: `SavedVariablesPerCharacter: AsItWasDB`.

| Key | Default | Meaning |
| --- | --- | --- |
| `filterId` | `"off"` | Option id: `"off"`, `"8"`, `"8.0.1"`, `"7.3.5"`, … |
| `seenSetup` | `false` | First-run already shown on this character |
| `includeOlder` | `true` | Unmarked if `patch <= filter.max`; if false, `min <= patch <= max` |
| `doNotAbandonOlder` | `true` | Mass abandon only `patch > max`; if false, abandon everything out of range |

Unknown quest IDs are marked `?` / `[?]`. Filter Off marks nothing. Do not treat unknown as in-range
on titles or pin badges; a known in-range quest on the same giver still wins.

## Product identity

**Display name:** `As It Was` (spaces). **Technical:** `AsItWas` (folder, toc, Lua global, slash
`/asitwas` `/aiw`). Chat prefix uses the display name.

For people going **back** through an expansion/patch, not current-raiders. Later-season quests on
old maps are the problem. It is not Chromie Time, not a quest guide, not catch-up (catch-up in WoW
means skip to now). Never block taking a quest — only mark. 3D bangs over NPC heads **cannot** be
removed; do not spend a session on that. Call those marks **vykřičníky**, not bangs, in Czech chat.

Rejected / do not re-open without the owner:

* WowTimeline, QuestEpoch, NotYet, Enforcer, Guide in the name
* Wowhead scrape as the table
* Publishing wago CSV structure (derived integer map is fine)
* Guessed QuestID ranges
* Hiding pins instead of a badge
* Mixing full expansion names into HUD/title tokens (use Legion / BfA / SL / DF / TWW / MN only)
* Overwriting `AsItWas.png`
* Auto-abandon
* Account-wide filter (would mark the Midnight main because an alt picked BfA)

## Data table

Rebuild after every new live retail patch. Mechanical. No AI, no Wowhead. Full maintainer notes:
`UPDATE.md`.

```bash
python3 tools/build_quest_patches.py
```

Needs `python3` and `curl`. Cache: `.cache/wago/` (gitignored). **Never commit or ship those CSVs.
Never republish wago's table layout.** Ship `data/QuestPatches.lua` and `data/PatchList.lua`.
CSV/JSON in `data/` are maintainer copies; the client does not load them.

* Source: live `wow` builds on wago.tools, newest build per `X.Y.Z`.
* Walk from BfA. There is **no 8.0.0** on retail; launch is **8.0.1**.
* Baseline **7.3.5** (oldest live dump) = Legion-and-older as one bucket. Pre-BfA minor patches
  (Northrend 3.0 vs 3.3, etc.) **cannot** be split from this source.
* Assignment: `patch = later(first QuestV2, first QuestPOIBlob)`.
  `id_only` / `poi` / `poi_after_id` / `at_or_before` in the CSV.
* Patch codes `MMmmpp` (`12.1.0` = `120100`). Compare numbers, not strings.
* Probes must stay green (script fails otherwise): 83137/83151 → 11.1.0; 84876/84905 → 11.2.0;
  92895 → 12.0.7; 92924/93387 → 12.1.0. `92924` is the grey case (ID in 12.0.x, POI in 12.1.0).
* Last successful build: ~66448 quests, 42 snapshots, newest `12.1.0.69814`.

Globals the addon reads: `AsItWasQuestPatch`, `AsItWasQuestPatchNewestBuild`, `AsItWasPatches`.

## File map

Loaded by the toc (order matters):

| File | Role |
| --- | --- |
| `data/QuestPatches.lua` | generated QuestID → code |
| `data/PatchList.lua` | generated snapshot list; UI builds dropdown rows at runtime |
| `AsItWas.lua` | filter math, DB, slash, first-run trigger, HUD, title prefix |
| `AsItWasMap.lua` | map/minimap era badges |
| `AsItWasTitles.lua` | log / tracker / gossip / greeting / map-tooltip titles |
| `AsItWasLog.lua` | mass abandon + `QUEST_ACCEPTED` print |
| `AsItWasOptions.lua` | first-run frame, Settings canvas, quest-log menu hook |
| `textures/newer.png`, `older.png` | pin arrows |
| `textures/chips/*.png` | expansion wordmarks |

Not loaded: `README.md` (CurseForge paste), `UPDATE.md` (table rebuild), `CHANGELOG.txt`,
`pkgmeta.yaml`, `SPEC.md`, this file, `tools/build_quest_patches.py`.

`pkgmeta.yaml` ignores `tools`, this file, `SPEC.md`, `UPDATE.md`, and the maintainer CSV/JSON.
Do not pack wago CSVs or the Python builder. Do not pack `*_preview.png`.

## Git, tags, CurseForge — same ritual as MemoryKeeper

GitHub: [Winring/AsItWas](https://github.com/Winring/AsItWas). Git identity **local to this repo**:
`Jiri Malina <jirka.malina@gmail.com>` in `.git/config`. Do not use the work address in global
`~/.gitconfig`. Never `git config` unless asked to set that local identity.

* Commits: one short English line, **no trailers**, no `Co-authored-by`. Owner is the only git
  author. Do not commit unless asked. Do not put uncommitted work on `main`.
* `main` on MemoryKeeper has **never** used merge commits; keep that here. Work on `fixes0.1.x`
  (or whatever version is current). Shipping is **fast-forward only**.
* CurseForge (once the webhook exists, same as MemoryKeeper): annotated tags named
  `release0.1.x` / `release1.x.x` (**not** `v0.1.0`). Empty tag message. **Pushing the tag is
  publishing.** Push `main` first, then the tag. Do not `git push --tags`.
* Owner Czech: *dej to do hlavního a tagni* means that recipe, not a GitHub PR, not `--no-ff`.

Concrete commands once `fixes0.1.1` (example) is ready **and the owner asked to ship** — swap
versions:

```bash
git checkout main
git pull --ff-only origin main
git merge --ff-only fixes0.1.1
git tag -a release0.1.1 -m ""
git push origin main
git push origin release0.1.1
git branch -d fixes0.1.1
git push origin --delete fixes0.1.1
```

If `--ff-only` refuses, **stop**. Before tagging: `## Version` matches, `CHANGELOG.txt` has the
player-visible entry, working tree clean.

**Not this recipe:** commit / push the fixes branch only (leaves CurseForge alone).

Do not re-open AI authorship / `Co-authored-by`. Same settlement as MemoryKeeper: never attribute
the work to an agent in git.

## Owner's conventions

* Verify Lua against `E:\Tvorba Her\Addony\wow-ui-source`, never from memory.
* Keep a change coherent with the surrounding file; do not refactor unrelated code.
* No recursive functions.
* Comments: constraint or reasoning the code cannot show, full sentences. No narration of the next
  line.
* Explain and agree before editing product behaviour. If it is designer-answerable, ask. If it is
  only visible in game, put it on the in-game list instead of guessing.
* **Ask before running tests** or anything with side effects. There is no Android suite here. Do
  not auto-run WoW. In-game verification is on the owner.
* Session-only state needs no discussion; **SavedVariables across logins must be asked first**
  (already agreed: per character).
* `README.md` and `CHANGELOG.txt` are player-facing only. Table-rebuild instructions stay in
  `UPDATE.md`.

## In-game list (owner)

First load already found: first-run `CloseAllWindows` + `seenSetup` on a crashing apply, missing
title hooks, no minimap clocks. Those are addressed in code. This pass is the chip/arrow/HUD build.

* Addon loads (`AsItWasTitles.lua` + `textures/`).
* First-run: Confirm applies; a Lua error during apply must **not** set `seenSetup`.
* HUD under zone name; Off hides; click opens Options.
* Options dropdown uses BfA / SL / DF / TWW / MN, not mixed full names.
* Whole BfA vs BfA 8.0.1 vs 8.1.0; Include older on/off.
* Blue up / grey down on map **and** minimap; zoom and rotate-minimap.
* Mixed giver: in-range wins.
* Quest log (map + details), tracker, gossip, greeting: chip + patch; warning when out of range.
* World-map pin tooltip: arrow or nothing, then chip + patch (not the warning).
* Unknown ID: `?` `[?]` in titles; question-mark on the pin.
* Taking a marked quest still works.
* 3D vykřičník over NPC head still there.
* Quest log gear: Don't abandon older + Abandon later; confirm; **only this character's log**.
* `/aiw` opens Options, `/aiw abandon` still works.

## Next (only if the owner asks)

1. Owner in-game pass on this commit; fix what actually breaks.
2. CurseForge project when they want to ship 0.1.0 (changelog already has `We are alive!`).
3. After the next retail patch: `python3 tools/build_quest_patches.py` and ship new Lua.
