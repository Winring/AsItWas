# As It Was

> Play one expansion or patch as it was.

Retail World of Warcraft keeps later-season quests on old maps. As It Was marks those quests so you can walk Battle for Azeroth, Shadowlands, or a single patch without the world pulling you into content that did not exist yet.

This is for a playthrough, not for skipping to current. It is not Chromie Time. You can still take every quest.

## Features

* Pick a whole expansion or an exact patch `X.Y.Z`
* Optionally include older quests so only later patches are marked
* Map and minimap pins: blue up-arrow on later quests, grey down-arrow on older quests (when Include older is off)
* Quest titles in the log, tracker, and NPC talk: expansion chip + patch number
* Out-of-range titles also get a warning icon; world-map pin tooltips use the arrows instead
* Unknown quest IDs (not in the table yet) get `?` and `[?]`
* Current filter is shown under the minimap zone name
* Mass abandon from the quest log settings menu
* Settings live in the game's own options panel

## How it plays

* Each character is asked once on login; close that window and marking stays off
* Marking is off until you choose an era
* In-range quests on the same giver keep their normal icon
* 3D exclamation marks over NPC heads are left alone — the client owns those

## Commands

* `/asitwas` or `/aiw` — open the settings panel
* `/asitwas abandon` — abandon quests newer than the selected patch
