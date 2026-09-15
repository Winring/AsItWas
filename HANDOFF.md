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

   ```bash
   CLONE=/tmp/wowui
   if [ -d "$CLONE/.git" ]; then
     git -C "$CLONE" fetch --depth 1 origin live
     git -C "$CLONE" checkout --detach origin/live
   else
     git clone --depth 1 --branch live https://github.com/Gethe/wow-ui-source "$CLONE"
   fi
   ```

   Prefer `/tmp/wowui`. If an older session used `/tmp/wowui-live`, reuse that instead of a second
   clone. **Never re-clone if `/tmp/wowui` already has `.git` — fetch/reset only.** The owner has
   already said not to clone wow-ui again when it is there.

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
   * Gossip — `GossipSharedAvailableQuestButtonMixin` / `GossipSharedActiveQuestButtonMixin`
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

* Last UI clone used for API greps: **12.1.0.69587**. `.toc` is `## Interface: 120100`. Five-digit
  scheme: major, two digits minor, two digits patch. Wiki `LatestPatchInfo` can lag.
* Last quest table snapshot: **12.1.0.69814** (`data/quest_patches_meta.json`). Those two build
  numbers can differ; Interface follows the client the owner plays, the table follows newest wago
  live `wow` per `X.Y.Z`.
* Addon version is `## Version: 0.1.0`. **Not released** (no `release0.1.0` tag yet). GitHub
  [Winring/AsItWas](https://github.com/Winring/AsItWas). No CurseForge project ID.
  Author in the toc is `Winring` (same as MemoryKeeper).

## Where the work currently is

**15 September 2026.** UI and data exist on disk. **Nobody has loaded this in game.** The first
in-game pass belongs to the owner. Addon icon is `AsItWas.png` next to the toc.

Install path the client expects: `Interface/AddOns/AsItWas/` (folder name must match `AsItWas.toc`).

### What is implemented (untested in game)

* Mechanical QuestID → patch table from wago history (`tools/build_quest_patches.py`).
* Filter: one dropdown (Off, Legion and older, each expansion whole, each real `X.Y.Z`) plus
  **Include older quests**.
* First-run window once per character; close / Esc / “No filter” = Off and do not nag again.
* Options canvas under Options → AddOns → As It Was (`/asitwas` or `/aiw`). Same dropdown +
  checkbox; applies immediately (no Confirm).
* Clock badge (`INV_Misc_PocketWatch_01`, 16px TOPRIGHT) on map/minimap quest pins.
* Gossip / greeting `[X.Y.Z]` prefix; rows stay clickable.
* Auto-accept: `QUEST_ACCEPTED` chat mark only.
* Mass abandon: quest log settings gear (`Menu.ModifyMenu` on `MENU_QUEST_MAP_FRAME_SETTINGS`) plus
  `/aiw abandon`. Confirm popup. Default **Don't abandon older quests**. Only the **current
  character** quest log (`C_QuestLog.AbandonQuest`).

### SavedVariables (per character)

Toc: `SavedVariablesPerCharacter: AsItWasDB`.

| Key | Default | Meaning |
| --- | --- | --- |
| `filterId` | `"off"` | Option id: `"off"`, `"8"`, `"8.0.1"`, `"7.3.5"`, … |
| `seenSetup` | `false` | First-run already shown on this character |
| `includeOlder` | `true` | Unmarked if `patch <= filter.max`; if false, `min <= patch <= max` |
| `doNotAbandonOlder` | `true` | Mass abandon only `patch > max`; if false, abandon everything out of range |

Unknown quest IDs stay unmarked. Filter Off marks nothing.

## Product identity

**Display name:** `As It Was` (spaces). **Technical:** `AsItWas` (folder, toc, Lua global, slash
`/asitwas` `/aiw`). Chat prefix uses the display name.

For people going **back** through an expansion/patch, not current-raiders. Later-season quests on
old maps are the problem. It is not Chromie Time, not a quest guide, not catch-up (catch-up in WoW
means skip to now). Never block taking a quest — only mark. 3D bangs over NPC heads **cannot** be
removed; do not spend a session on that.

Rejected / do not re-open without the owner:

* WowTimeline, QuestEpoch, NotYet, Enforcer, Guide in the name
* Wowhead scrape as the table
* Publishing wago CSV structure (derived integer map is fine)
* Guessed QuestID ranges
* Hiding pins instead of a badge
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
| `AsItWas.lua` | filter math, DB, slash, first-run trigger |
| `AsItWasMap.lua` | pin badge |
| `AsItWasGossip.lua` | gossip / greeting prefix |
| `AsItWasLog.lua` | mass abandon + `QUEST_ACCEPTED` print |
| `AsItWasOptions.lua` | first-run frame, Settings canvas, quest-log menu hook |

Not loaded: `README.md` (CurseForge paste), `UPDATE.md` (table rebuild), `CHANGELOG.txt`,
`pkgmeta.yaml`, `SPEC.md`, this file, `tools/build_quest_patches.py`.

`pkgmeta.yaml` is `manual-changelog: CHANGELOG.txt` only (same as MemoryKeeper). When a curse pack
exists, ignore `.cache/` and `tools/`. Do not pack wago CSVs.

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

* Verify Lua against `/tmp/wowui`, never from memory.
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

## In-game list (owner, first load)

Nothing below has been confirmed in 12.1.

* Addon loads (toc lists every Lua file).
* First-run once per character; Confirm applies; No filter / X / Esc = Off and never again on that
  character.
* Options dropdown + Include older; live apply; Off turns marks off.
* Whole BfA vs BfA 8.0.1 vs 8.1.0; Include older on/off.
* Clock on classic `!`, campaign, important, world quest, hub, bonus, minimap POIButton.
* Mixed giver: in-range quest wins, no clock over a wanted bang.
* Gossip + greeting prefix; still clickable; watch for taint.
* Taking a marked quest still works.
* 3D bang over NPC head still there.
* Quest log gear: Don't abandon older + Abandon later; confirm; **only this character's log**.
* `/aiw` opens Options, `/aiw abandon` still works.

## Next (only if the owner asks)

1. Owner in-game pass; fix what actually breaks.
2. Git repo + CurseForge project when they want to ship 0.1.0 (`We are alive!` is already in
   CHANGELOG).
3. After the next retail patch: `python3 tools/build_quest_patches.py` and ship new Lua.
