# As It Was — handoff notes

Working notes for whoever picks this up next. This file sits in `MK/AsItWas/` next to the addon.
It is **not** listed in `AsItWas.toc`, so the client never loads it. GitHub is
[Winring/AsItWas](https://github.com/Winring/AsItWas). The owner may later move this file out of
the tree like MemoryKeeper's handoff.

Start a session by reading this file, then `SPEC.md` and `UPDATE.md`. Do not implement until the
owner has agreed. Conversation is Czech or English; code, README, CHANGELOG, UPDATE, SPEC, and this
file are English.

The Cursor workspace is often `MK/MemoryKeeper/MemoryKeeper`. **As It Was is not that repo.** Addon
code is this folder. Do not write As It Was files into MemoryKeeper. Writes from a MemoryKeeper
workspace into `AsItWas/` may need extra permissions (`all`).

## Read this before writing a single line: audit the API against live sources

Work based on a model's memory of the WoW API is garbage. The API changes every patch. **Look it
up. Every time. Even for things that feel obvious.** Before changing taint, secret-value, tooltip,
map-pin, tracker, or protected-frame code, cross-reference every affected Blizzard API, frame,
mixin, argument, return value, and call path with current Blizzard source and generated API
metadata. Do not begin with an in-game guess or a remembered workaround. `WOW12_API_AUDIT.md` and
`FAILED_EXPERIMENTS.md` predate the 0.4.0 taint work; the **WoW 12 taint rules** section below
supersedes them where they disagree.

Where to look, in order of authority:

1. **Blizzard's own UI source** — ground truth. Mirror: `https://github.com/Gethe/wow-ui-source`,
   branch `live`. Keep a **local clone** and grep that. Do **not** clone the whole tree every
   session.

   The clone lives at **`E:\Tvorba Her\Addony\wow-ui-source`** (owner's machine, PowerShell).

   ```powershell
   $CLONE = 'E:\Tvorba Her\Addony\wow-ui-source'
   git -C $CLONE fetch --depth 1 origin live
   git -C $CLONE checkout --detach origin/live
   ```

   **Never re-clone if that folder already has `.git` — fetch/reset only.** Only if the folder is
   gone: `git clone --depth 1 --branch live https://github.com/Gethe/wow-ui-source $CLONE`.

   Generated API docs: `Interface/AddOns/Blizzard_APIDocumentationGenerated/` (secret flags such as
   `SecretArguments` are listed there). Usage: `Interface/AddOns/Blizzard_*`. How Blizzard calls a
   function beats wiki and training data. Files that settled this addon's behaviour:

   * `Blizzard_Menu` — `WowStyle1DropdownTemplate`, `DropdownButtonMixin:SetupMenu`,
     `Menu.ModifyMenu` (runs callbacks through `securecallfunction`, safe for addons)
   * `Blizzard_Settings_Shared` — `Settings.RegisterCanvasLayoutCategory`,
     `Settings.OpenToCategory` (goes through `C_SettingsUtil.OpenSettingsPanel`, safe)
   * `Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua` — quest log gear menu tag
     `MENU_QUEST_MAP_FRAME_SETTINGS`; `QuestMapFrame_UpdateAll` → `QuestLogQuests_Update` runs on
     every map show and map change
   * Map pins — `Blizzard_MapCanvas` (`AcquirePin`, secure pin pools), `QuestOfferPinMixin`,
     `QuestHubPinMixin` (hub tooltips draw suppressed pins with `FrameCloneManager:Clone`, which
     copies every region of the pin, our badge included), `SuperTrackablePinMixin`
     (`SetPropagateMouseClicks`, protected in combat)
   * Map pin tooltips — `QuestPinMixin:OnMouseEnter` (`QuestDataProvider.lua`),
     `TaskPOI_OnEnter` + `GameTooltip_AddQuest` (`WorldMapFrame.lua`, `GameTooltip.lua`);
     `GameTooltip:GetOwner()` is the hovered pin
   * Gossip — `GossipFrameSharedMixin:UpdateScrollBox` / `Update` (`GossipFrameShared.lua`):
     quest buttons are ScrollBox children whose `Setup` sets the button ID to the quest ID
   * Objective tracker — `ObjectiveTrackerBlockMixin:SetHeader` measures the header into
     `block.height`; `QuestObjectiveTrackerMixin:UpdateSingle` ends with `LayoutBlock`;
     `ObjectiveTrackerModuleMixin:UpdateHeight` closes every layout pass; blocks are anchored below
     each other and modules below each other (`ObjectiveTrackerContainer`)
   * Dialogue UI — the live `DUIQuestFrame` copies `DUIDialogBaseMixin` methods from
     `Code/Dialogue/DialogueUI.xml`. Hook `DUIQuestFrame:UpdateQuestTitle()` and
     `DUIQuestFrame:HandleGossip()` after the addon is loaded. Source addon: `Peterodox/YUI-Dialogue`.
   * Minimap overlay — `C_Minimap.GetViewRadius`, `UnitPosition` (plain numbers, nil in
     instances), `C_Map.GetPlayerMapPosition` (allocates a vector per call), `GetPlayerFacing` /
     `rotateMinimap`
   * Which quests get an icon — `QuestOfferDataProviderMixin:GetAllQuestOffersForMap` and
     `ShouldAddQuestOffer`. `C_QuestLog.GetQuestsOnMap` is **accepted** quests only; read it for
     `C_QuestLog.ReadyForTurnIn` markers only.

2. **ATT's processed C# parser output** for the quest→patch table. See **Data table** below.
   Wowhead is only a manual audit reference, not a generation source.

3. **Warcraft Wiki** for orientation only (`Template:LatestPatchInfo`, `TOC_format`,
   `Secret_Values`, `CVar_taintLog`). Frequently wrong or late. Never let it override Blizzard source.

### Versions — re-verify at the start of every session

* Live client **12.1.5** (`version.txt` 12.1.5.70783 on 8 November 2026). `.toc` is
  `## Interface: 120105`. Five-digit scheme: major, two digits minor, two digits patch.
* Quest table: ATT revision `a9ceed3bf928764cb322fdc70f8e49976c4b01f5`, plus the Wago BfA+ backup
  (`data/att_quest_database/wago_quest_patches.json`). The newest patch row is 12.1.5
  (`12.1.5.70391`).
* Addon version **1.0.0**, released. Author in the toc is `Winring`.

## Where the work currently is

**8 November 2026.** `main` at `fb0506b Prepare 1.0.0 release`, released as 1.0.0. No known open
addon-breaking issues; the owner played for a long stretch without Lua errors before releasing.

Addon icon is `AsItWas.png` next to the toc. **Do not overwrite that png.**

Install path the client expects: `Interface/AddOns/AsItWas/` (folder name must match `AsItWas.toc`).
Copy the whole folder (lua + `textures/` + `data/`) and `/reload`.

### What is implemented

* Mechanical QuestID → patch table from ATT's C# parser, with a Wago backup only for BfA+ IDs ATT
  does not have (`UPDATE.md`).
* Filter: one dropdown (Off, newest expansion first, each whole-expansion row followed by its
  patches newest-to-oldest) plus **Include older quests**. Labels use short tokens: Classic, TBC,
  WotLK, Cata, MoP, WoD, Legion, BfA, SL, DF, TWW, MN.
* First-run window once per character; close / Esc / “No filter” = Off. `seenSetup` is set only
  after a successful `ApplyFilter`.
* Options canvas under Options → AddOns → As It Was (`/asitwas` or `/aiw`): filter dropdown,
  Include older quests, Show minimap quest badges. Applies immediately.
* HUD caption under the minimap zone text. Off hides it. Click opens Options. Its hover hint and
  the options checkbox hints are the addon-owned `AIW.ShowHint` frame, never `GameTooltip`.
* World map badges on `QuestPinTemplate` and `QuestOfferPinTemplate` pins (`newer.png`,
  `older.png`, question mark for unknown). Pins under a quest hub keep a correct badge, so the hub
  tooltip's cloned pins show it too. World quest, quest hub, and bonus objective pins are not
  badged (commented out in `PIN_TEMPLATES`).
* Minimap badges: engine bangs are drawn by the client; the overlay recomputes only when the player
  moved, the zoom or facing changed, or a quest/quest-line event arrived (coalesced to one rebuild
  per 0.05s tick). Accept, complete, turn-in, and abandon all rebuild it.
* World map pin tooltip (`AsItWasMapTooltip.lua`): an addon-owned `GameTooltip` widget built from
  `SharedTooltipTemplate`, drawn on top of Blizzard's pin tooltip with an opaque fill. It rebuilds
  Blizzard's lines for both pin types (title, Available Quest, follower lines, floor line, dungeon
  tag, time left, waypoint, objectives) with the era prefix. Shown in and out of combat; it stays
  hidden only when Blizzard's tooltip is not on a handled pin or our own code errors (`pcall`).
* Titles: quest log, quest details, quest log popup, objective tracker, gossip, greeting, and
  Dialogue UI show expansion chip + `X.Y.Z` + name through the single `AIW.MarkTitle()` formatter.
  Out of range adds Blizzard's warning icon; the map tooltip uses the arrows instead. Unknown IDs:
  `?` + `[?]`.
* Objective tracker: when a prefix wraps a title, the extra header height is added to the block
  and its module after `UpdateHeight`, so later quests and the next section move down.
* Gossip: no Blizzard function is replaced or hooked. A 0.1s ticker runs only while `GossipFrame`
  is shown and re-labels visible quest buttons from `C_GossipInfo` data.
* `QUEST_ACCEPTED` chat mark for out-of-range quests.
* Mass abandon: quest log settings gear (`Menu.ModifyMenu`) plus `/aiw abandon`. Confirm popup.
  Default **Don't abandon older quests**. Current character only. Unknown IDs are not abandoned.
* `/aiw debug`: per-character switch saved in `AsItWasDB.debug`; output goes to chat only. It
  reports, per hovered map quest pin, whether our tooltip was shown and why not.

### SavedVariables (per character)

Toc: `SavedVariablesPerCharacter: AsItWasDB`.

| Key | Default | Meaning |
| --- | --- | --- |
| `filterId` | `"off"` | Option id: `"off"`, `"8"`, `"8.0.1"`, `"7.3.5"`, … |
| `seenSetup` | `false` | First-run already shown on this character |
| `includeOlder` | `true` | Unmarked if `patch <= filter.max`; if false, `min <= patch <= max` |
| `showMinimapBadges` | `true` | Minimap badge overlay on/off |
| `doNotAbandonOlder` | `true` | Mass abandon only `patch > max`; if false, abandon everything out of range |
| `debug` | unset | `/aiw debug` switch; only the flag is saved, output is chat only |

Unknown quest IDs are marked `?` / `[?]`. Filter Off marks nothing. Do not treat unknown as in-range
on titles or pin badges; a known in-range quest on the same giver still wins.

## WoW 12 taint rules (learned the hard way, 0.3 → 1.0)

The 0.3.x `ADDON_ACTION_BLOCKED` (`SetPropagateMouseClicks`, `SetPassThroughButtons`) and secret
`textHeight` / `barWidth` / `LayoutFrame` errors were all addon taint that surfaced in combat. Taint
is written out of combat and stays until `/reload`; combat only makes it visible (protected calls
are blocked, secret values appear). Rules that came out of it:

* **Never call a Blizzard Lua helper that caches.** The root cause was `MapUtil.IsChildMapCached`
  called from the minimap pass: it wrote a tainted entry into Blizzard's private cache, the quest
  offer provider read it on the next map open, and every pin acquired in that refresh was tainted.
  `AsItWasMap.lua` walks parents with `C_Map.GetMapInfo` and its own cache instead.
* **Never hide, show, own, or hook `GameTooltip`.** `GameTooltip:Hide()` from addon code runs
  `GameTooltip_OnHide` (widget container cleanup) under addon taint, and the next AreaPOI widget
  tooltip fails on secret metrics. Only read-only getters are used on it (`IsShown`, `GetOwner`,
  `GetWidth`, `GetFrameLevel`). Do not use `GameTooltipTemplate` for addon tooltips either; its
  `OnHide` touches `BattlePetTooltip` and `TooltipComparisonManager`.
* **Never replace a Blizzard function or mixin method.** The old gossip `UpdateTitleForQuest`
  replacement put addon code into the secure ScrollBox setup.
* **No Lua arithmetic on geometry next to Blizzard frames.** Pins are pooled and can keep secret
  anchoring; anything anchored to them inherits it, including string metrics. Let the client lay
  out (a `GameTooltip` widget) and guard every measurement with `issecretvalue`.
* **Do not trust `pin:IsSuppressed()`** for drawn pins: Blizzard can leave the flag set on a pin
  that is still shown and hovered.
* **Blizzard Lua state is never written.** Frame sizes (`SetHeight`) and text on Blizzard regions
  are C-side and were fine; Lua fields (`block.height`, `contentsHeight`) are only read.
* **Diagnose with the client's taint log, not guesses.** `/console taintLog 4`, `/reload`, play
  10–15 minutes, `/console taintLog 0`, then search `Logs/taint.log` for writes whose stack contains
  `Interface/AddOns/AsItWas/`. The error does not need to reproduce; the tainting write is logged
  when it happens. The file grows to about 1 GB; delete it afterwards.

## Product identity

**Display name:** `As It Was` (spaces). **Technical:** `AsItWas` (folder, toc, Lua global, slash
`/asitwas` `/aiw`). Chat prefix uses the display name.

For people going **back** through an expansion/patch, not current-raiders. Later-season quests on
old maps are the problem. It is not Chromie Time, not a quest guide, not catch-up (catch-up in WoW
means skip to now). Never block taking a quest — only mark. 3D bangs over NPC heads **cannot** be
removed; do not spend a session on that. Call those marks **vykřičníky**, not bangs, in Czech chat.

The era prefix is the product. Do not propose shortening or dropping it to work around layout
problems; fix the layout instead.

Rejected / do not re-open without the owner:

* WowTimeline, QuestEpoch, NotYet, Enforcer, Guide in the name
* Wowhead scrape as the table
* Using Wago, Wiki, or Wowhead as the primary generation source (Wago is a BfA+ backup for IDs ATT
  lacks, never an override)
* Guessed QuestID ranges
* Hiding pins instead of a badge
* Mixing full expansion names into HUD/title tokens
* Shortening or hiding the prefix to fit Blizzard layouts
* Overwriting `AsItWas.png`
* Auto-abandon
* Account-wide filter (would mark the Midnight main because an alt picked BfA)

## Data table

Rebuild after every new live retail patch. ATT is the source of truth; Wago fills only BfA+ IDs ATT
has no `awp` for. Full maintainer notes: `UPDATE.md`.

```bat
tools\att_quest_database\download_and_run_windows.bat
```

It refreshes the Wago backup (`tools/build_quest_patches_wago.py`, cached under `.cache/wago`),
clones or fast-forwards ATT into `tools\att_quest_database\att-source`, and runs ATT's C# parser
(needs Git, Python 3, curl, MSBuild). The Wago backup is written only after its probe checks pass;
on failure the previous backup stays. `data/att_quest_database/` stores the validated snapshot and
audit files. Patch codes are numeric `MMmmpp` (`12.1.5` = `120105`). The builder also writes
`data/PatchList.lua` from the codes in the table, so the dropdown always matches the data. After a
rebuild, update `## Interface` in the toc.

`data/QuestPatches.lua` is the **only** quest database. A quest missing from it is unknown (`?`).
Do not add a second lookup table; the old Grail-based `QuestExpansions.lua` was removed in 1.0.1
because nothing rebuilt it and the badges read it instead of the patch table.

Globals the addon reads: `AsItWasQuestPatch`, `AsItWasPatches`.

## File map

Loaded by the toc (order matters):

| File | Role |
| --- | --- |
| `data/QuestPatches.lua` | generated QuestID → patch code |
| `data/PatchList.lua` | generated patch list; the UI builds dropdown rows at runtime |
| `AsItWas.lua` | filter math, DB, slash commands, first-run trigger, HUD, `AIW.ShowHint`, `AIW.MarkTitle` |
| `AsItWasMap.lua` | world map and minimap badges |
| `AsItWasTitles.lua` | title prefixes: quest log, details, popup, tracker (+ height fix), gossip ticker, greeting, Dialogue UI |
| `AsItWasMapTooltip.lua` | world map pin tooltip overlay, `/aiw debug` reports |
| `AsItWasLog.lua` | mass abandon + `QUEST_ACCEPTED` print |
| `AsItWasOptions.lua` | first-run frame, Settings canvas, quest-log menu hook |
| `textures/newer.png`, `older.png` | pin arrows |
| `textures/chips/*.png` | expansion wordmarks (Classic … MN) |

Not loaded: `README.md` (CurseForge paste), `UPDATE.md`, `CHANGELOG.txt`, `pkgmeta.yaml`,
`SPEC.md`, `WOW12_API_AUDIT.md`, `FAILED_EXPERIMENTS.md`, `Reported lua errors.txt`, this file,
`tools/`, `data/att_quest_database/`, and the CSV/JSON audit files. `pkgmeta.yaml` ignores all of
them. Do not pack the parser tools or `*_preview.png`.

## Git, tags, CurseForge — same ritual as MemoryKeeper

GitHub: [Winring/AsItWas](https://github.com/Winring/AsItWas). Git identity **local to this repo**:
`Jiri Malina <jirka.malina@gmail.com>` in `.git/config`. Do not use the work address in global
`~/.gitconfig`. Never `git config` unless asked to set that local identity.

* Commits: one short English line, **no trailers**, no `Co-authored-by`. Owner is the only git
  author. **Do not commit unless asked**, locally or to origin; leave changes uncommitted. Do not
  put uncommitted work on `main`.
* `main` on MemoryKeeper has **never** used merge commits; keep that here. Work on `fixes1.0.x`
  (or whatever version is current). Shipping is **fast-forward only**.
* CurseForge (same as MemoryKeeper): annotated tags named `release1.0.x` / `release1.x.x`
  (**not** `v1.0.0`). Empty tag message. **Pushing the tag is publishing.** Push `main` first,
  then the tag. Do not `git push --tags`.
* Owner Czech: *dej to do hlavního a tagni* means that recipe, not a GitHub PR, not `--no-ff`.

Concrete commands once `fixes1.0.1` (example) is ready **and the owner asked to ship** — swap
versions:

```bash
git checkout main
git pull --ff-only origin main
git merge --ff-only fixes1.0.1
git tag -a release1.0.1 -m ""
git push origin main
git push origin release1.0.1
git branch -d fixes1.0.1
git push origin --delete fixes1.0.1
```

If `--ff-only` refuses, **stop**. Before tagging: `## Version` matches, `CHANGELOG.txt` has the
player-visible entry, working tree clean.

**Not this recipe:** commit / push the fixes branch only (leaves CurseForge alone).

Do not re-open AI authorship / `Co-authored-by`. Same settlement as MemoryKeeper: never attribute
the work to an agent in git.

## Owner's conventions

* Verify Lua against the local `wow-ui-source` clone, never from memory.
* Keep a change coherent with the surrounding file; do not refactor unrelated code.
* No recursive functions.
* Comments: constraint or reasoning the code cannot show, full sentences. No narration of the next
  line.
* Explain and agree before editing product behaviour. If it is designer-answerable, ask. If it is
  only visible in game, put it on the in-game list instead of guessing.
* **Ask before running anything with side effects.** Do not auto-run WoW. In-game verification is
  on the owner.
* Session-only state needs no discussion; **SavedVariables across logins must be asked first**
  (agreed so far: per character, including the `debug` switch).
* `README.md` and `CHANGELOG.txt` are player-facing only. Table-rebuild instructions stay in
  `UPDATE.md`.
* Keep replies short; the owner asks for detail when wanted.

## In-game list (owner)

Regression pass after any change to map, tooltip, tracker, or gossip code:

* No Lua errors after a long session including combat, map open/close in combat, and hovering
  activity POIs (Theater Troupe, Void Incursion).
* World map: every quest and available-quest pin shows our single tooltip with prefix, also next to
  quest hubs and at every zoom; no Blizzard text showing through.
* Hub tooltip: listed quests show the correct badge.
* Minimap: badges follow movement, zoom, rotate-minimap; a turned-in quest loses its badge at once.
* Tracker: long prefixed titles wrap without overlapping the next quest or section.
* Gossip and Dialogue UI: quest buttons prefixed; clicking still works.
* Quest log (map + details), greeting: chip + patch; warning when out of range.
* Unknown ID: `?` `[?]` in titles; question mark on the pin.
* Memory: with the map closed and standing still, addon memory stays flat.
* `/aiw`, `/aiw abandon`, `/aiw debug`.

## Next (only if the owner asks)

1. After each retail patch: rebuild the data table (`UPDATE.md`), bump `## Interface`, add the
   patch row.
2. Known limit: Blizzard decides how many tracker blocks fit using its own heights, so with many
   wrapped titles the tracker can end slightly below its usual bottom edge.
3. World quest, quest hub, and bonus objective pins are still not badged; re-enable one template at
   a time if wanted, with a taint log session after each.
