# As It Was

> Come back to Azeroth. Pick up where you left off.

World of Warcraft moves on while you are away. When you return, quests from newer patches can fill your map and quest log, making it hard to tell where your own journey stopped.

**As It Was** lets you choose the expansion or patch where you want to continue. Select the patch you last played—or the one you want to experience—and identify the quests that came later. Focus on the content that belongs to your current chapter, then move the filter forward whenever you are ready.

Later content is marked, never blocked. You can still accept any quest, but the markers help you decide what belongs to your current playthrough and what can wait.

## Keep your journey on track

* Choose a complete expansion or an individual patch `X.Y.Z`
* Mark later quests on the world map and minimap
* Optionally mark older quests too
* See expansion and patch labels in quest titles, the quest log, objective tracker, NPC dialogues, and map tooltips
* See the active filter under the minimap zone name
* Abandon later quests from the quest log settings menu, if you choose
* Change your selected patch at any time
* Keep the familiar Blizzard UI — no routes to follow and no content is blocked

## How it works

Choose an era during the first setup, such as a complete expansion or a specific patch. Quests from your selected period remain unmarked. Later quests receive a blue marker so you can recognize content that belongs to a later chapter. If **Include older quests** is disabled, older quests receive a grey marker as well.

When you finish your chosen chapter, change the filter to the next patch and continue through Azeroth’s history one step at a time—experiencing it **As It Was**.

The setup is saved separately for each character. Closing the first-run window or choosing **No filter** leaves the addon inactive. The addon never removes quests automatically, and the original 3D exclamation marks above NPCs are left unchanged.

> **Coverage:** Patch data includes every patch code currently emitted by ATT, plus
> explicitly marked BfA+ fallback entries where ATT has no effective value.

## Commands

* `/asitwas` or `/aiw` — open the settings panel
* `/asitwas abandon` — abandon quests newer than the selected patch

## Development

Technical specifications, data-generation instructions, and maintenance notes are documented separately:

* [`SPEC.md`](SPEC.md) — product behavior and technical specification
* [`UPDATE.md`](UPDATE.md) — rebuilding the quest-to-patch data
* [`HANDOFF.md`](HANDOFF.md) — project state and development notes
