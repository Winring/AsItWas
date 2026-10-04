# Updating the quest-to-patch table

The authoritative source is ATT's own C# parser. A narrow BfA+ fallback is kept
for IDs that ATT does not expose at all: `data/att_quest_database/legacy_wago_fallback.json`.
It never overrides an ATT record. Do not use the former Wago, Wiki, or hybrid
builders to replace ATT data.

## Build

On Windows, with a full ATT checkout and MSBuild installed:

```bat
tools\att_quest_database\run_windows.bat C:\path\to\AllTheThings
```

The runner installs the small exporter into ATT's parser, builds it, runs ATT's
normal processing, and writes the processed `questID -> awp` result. The parser
is the source of truth; Python only packages its output.

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
- BfA+ IDs absent from ATT may be added from `legacy_wago_fallback.json`; these
  are marked `legacy_wago_fallback` and remain lower priority than ATT.

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
