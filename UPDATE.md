# Updating the quest-to-patch table

The authoritative source is ATT's own C# parser. A refreshed BfA+ Wago backup is
kept for IDs that ATT does not expose at all:
`data/att_quest_database/wago_quest_patches.json`. The committed legacy Wago
file remains the offline safety net if no refreshed backup exists.
It never overrides an ATT record. Do not use the former Wago, Wiki, or hybrid
builders to replace ATT data.

## Build

On Windows, with Git, Python 3, curl, and MSBuild installed, use the combined
downloader:

```bat
tools\att_quest_database\download_and_run_windows.bat
```

It updates Wago's full historical snapshot set and ATT independently. The Wago
step uses the latest build for every available `X.Y.Z`, not just the newest
patch, so skipped releases are handled automatically. The ATT step clones or
fast-forwards `tools\att_quest_database\att-source` and runs ATT's C# parser.

The final merge is ATT-first: Wago only fills quest IDs for which ATT has no
effective `awp`. If Wago is unavailable, its previous backup is retained.

The ATT runner also supports both parser layouts currently used by ATT:
`.contrib\src\parser` and `.contrib\Source Code\Parser`.

The generated addon file is:

```text
data/QuestPatches.lua
```

The current validated snapshot is also kept in:

```text
data/att_quest_database/
```

That directory contains the Lua mapping, JSON/CSV audit copies, and ATT's
intermediate export including IDs without `awp`.

## Semantics

- ATT's processed object graph supplies direct and inherited `awp` values.
- Inheritance follows ATT's structural `g`, `aqd`, and `hqd` branches.
- A child's explicit `awp` overrides its inherited value.
- JSON and CSV retain every distinct value.
- Lua uses the latest value for addon compatibility.
- IDs without an effective ATT `awp` are omitted from the addon Lua output.
- BfA+ IDs absent from ATT may be added from the refreshed Wago backup, or from
  `legacy_wago_fallback.json` when Wago is unavailable; these are marked
  `wago_fallback` and remain lower priority than ATT.

## Auditing

Use the ATT-side gap report after a build if needed:

```bat
py -3 tools\att_quest_database\analyze_att_quest_gap.py C:\path\to\AllTheThings --json-out att_quest_gap.json
```

Manual Wowhead checks are supplementary audits only; Wowhead is not used to
generate or repair the ATT database.

## Current validated snapshot

The snapshot used for the current addon table contains 55,667 IDs with an
effective `awp`, including 235 IDs with multiple distinct `awp` values.
