# ATT quest database builder

This bundle runs ATT's own C# parser and exports its processed
`questID -> awp` values directly from the parser object graph. It does not
reimplement ATT timeline logic or parse the generated Lua.

## Windows setup

Install once:

1. Python 3 (`py -3` must work in Command Prompt).
2. Visual Studio 2022 Build Tools with **.NET desktop build tools**, or full
   Visual Studio. ATT's parser targets .NET Framework 4.8 and x64.
3. A full checkout of the ATT Git repository, not only the released addon ZIP.

Then from the As It Was project directory run:

```bat
tools\att_quest_database\run_windows.bat C:\path\to\AllTheThings
```

Or use `download_and_run_windows.bat` to update both sources automatically:

1. Wago's historical `X.Y.Z` snapshots are downloaded/cached and converted to
   `data/att_quest_database/wago_quest_patches.json`.
2. The latest ATT Git repository is cloned or fast-forwarded and its C# parser
   generates the ATT snapshot.
3. The final addon table merges both sources; ATT wins on every quest ID.

The Wago step walks every available patch, so it also handles several skipped
patches between two runs. If Wago is temporarily unavailable, the previous
Wago backup remains usable and the ATT build continues.

To measure how many processed ATT quest objects have no `awp`, run after the
database build:

```bat
py -3 analyze_att_quest_gap.py C:\path\to\AllTheThings --json-out att_quest_gap.json
```

The report distinguishes unique quest IDs with and without `awp`. It reads the
JSON emitted inside ATT after `Framework.Process()`, so missing values are an
ATT-data gap, not an omission by the As It Was export.

The script installs a small exporter into ATT's parser, builds `Parser.csproj`,
runs it with `auto`, and reads the direct JSON written to `ATT\db\Standard`.
It also writes:

- `data\QuestPatches.lua`
- `data\quest_patches_att.json`
- `data\quest_patches_att.csv`

The Wago-derived backup is written to `data\att_quest_database\wago_quest_patches.json`.

ATT's direct intermediate output is `db\Standard\QuestPatches.att.json` and
contains every processed quest ID, including IDs whose processed object graph
has no `awp`.

The Lua file uses the latest (`max`) ATT value for compatibility with the
addon. ATT itself resolves timelines and inheritance before the direct export.
The JSON/CSV files retain every distinct ATT value for a quest; CSV columns are `quest_id`,
`latest_awp`, and `all_awp`.

The ATT checkout receives the small exporter source and project wiring required
to compile it, plus the parser's generated `db` output. The As It Was database
is generated only after the parser exits successfully.

The parser is rebuilt because the direct exporter is compiled into it.
