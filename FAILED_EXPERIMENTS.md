# As It Was — failed experiments and taint history

This is a maintainer log of changes that were tried and then rejected, reverted,
or left disabled after testing. Read this before proposing another taint, tooltip,
map-pin, or secret-value workaround.

The purpose is not to preserve every implementation detail. The purpose is to
prevent repeating an old experiment without new evidence. A previously rejected
approach may only be reconsidered when the WoW client/API or the observed error
path has materially changed.

## Rules for using this file

1. Verify the current remote branch and commit before reading local error logs.
2. Build or update `WOW12_API_AUDIT.md` by cross-referencing every affected
   Blizzard API, frame, mixin, argument, return value, and call path against
   current Blizzard source and generated API metadata. This comes before any
   code change or runtime experiment.
3. Check Blizzard's current UI source and generated API documentation; never
   rely on model memory.
4. Change one taint boundary at a time and record the exact in-game reproduction.
5. Do not call a workaround a fix until the original feature still works and the
   relevant error is absent after a fresh `/reload` or client restart.
6. Never infer causality from an error merely mentioning `AsItWas`; compare the
   complete stack and test with the smallest possible change.

## Current known hazards

### Global `GameTooltip:SetText` hook

**Commits:** `895c532`, `5d92f9f`
**Status:** rejected; do not restore without a new design.

The hook runs for every `GameTooltip`, not only quest map tooltips. In WoW 12.0+
the argument may be a secret string. Comparing it with `RETRIEVING_DATA`,
comparing it with a decorated result, or passing it through ordinary string
operations can fail on a tainted path. A no-op global post-hook can also put
addon execution into unrelated Blizzard tooltip/widget paths.

The error captured on remote branch `ae28b99` at
`AsItWasTitles.lua:392` is the direct example:

```text
attempt to compare local 'title' (a secret string value, while execution tainted by 'AsItWas')
```

Do not treat `title == RETRIEVING_DATA` as a sufficient fix. Secret values must
be rejected before any comparison or string processing, and the global hook's
scope must be justified independently.

### Replacing or wrapping Blizzard title decorators

**Commits:** `d1b81e0`, earlier title-hook experiments
**Status:** rejected.

Replacing or wrapping `QuestUtils_DecorateQuestText` was unsafe in WoW 12. The
current title integrations adapt the individual rendered UI instead. Do not
restore a global replacement merely because it is shorter or covers more UI.

### Hooking map-pin acquisition or visual setup

**Commits:** `1f52ad0`, `4f7ce26`
**Status:** rejected for the map acquisition path.

Post-hooks around pin acquisition and visual-update methods still execute in or
near Blizzard's protected map refresh pipeline. Deferring the callback with
`C_Timer.After(0)` did not make the acquisition path a safe place to mutate the
pin.

The later design in `203242d` removed those acquisition hooks and polls pins
that already exist. Do not reintroduce `OnAcquired`, `OnLoad`, `SetQuestID`, or
visual-update hooks as a first response to missing badges.

### Temporarily disabling the world-map overlay

**Commit:** `1aacb5f`
**Status:** diagnostic isolation only, not a product fix.

This removed the world-map overlay to isolate map taint, then
`48b8a13` restored it. It proves only that disabling a feature can be a useful
binary test; it does not prove that the overlay implementation is the root
cause or that the feature should remain disabled.

### Disabling map hover tooltip hooks

**Commits:** `1b93715`, `406cd17`, later restored in the current line
**Status:** diagnostic isolation only.

Disabling hover hooks was an experiment, not an established fix. Do not repeat
it as a final solution without recording whether the exact current
`SetPassThroughButtons()` error disappears and whether map tooltip labels still
work.

The replacement must not restore those global hooks. The current implementation
uses `AsItWasMapTooltip.lua`: it polls existing pins and renders an addon-owned
tooltip instead of rewriting Blizzard's `GameTooltip`.

### `securecallfunction` as a universal taint fix

**Commits:** `d1b81e0`, `e3d6f85`
**Status:** not a proof of safety.

`securecallfunction` can create a secure boundary for a specific Blizzard call,
but it does not automatically make arbitrary addon logic and mutations of
Blizzard map objects safe. It must be evaluated against the exact call graph.

### Monkey-patching `GameTooltip_AddWidgetSet`

**Commit:** `a58f94d` (later evolved/reworked)
**Status:** do not use as a default workaround.

Replacing a Blizzard global with an addon wrapper changes a central tooltip
path. Current Blizzard UI already uses secure delegates/boundaries for tooltip
widget processing. Any such change needs current-source evidence and an
isolated reproduction; the existence of a widget-layout error alone is not
enough.

## Current unresolved investigation

Remote branch `origin/fix-wow12-preserve-title-functionality` currently points
to `ae28b99` and reports:

* the secret-string comparison in `AsItWasTitles.lua:392`;
* `ADDON_ACTION_BLOCKED` for `Button:SetPassThroughButtons()` while Blizzard
  acquires map pins;
* secret-number/widget-layout errors in Blizzard tooltip code.

These are not yet proven to share one cause. Investigate them separately:

1. isolate the global tooltip hook and retest character/stat and AreaPOI
   tooltips;
2. independently isolate world-map pin overlays and map hover hooks;
3. compare the exact Blizzard source and API metadata for the client build being
   tested;
4. record a fresh error log for each single-variable test here.

## Evidence standard for closing an entry

An entry may be marked fixed only when the replacement has:

* a named test scenario;
* a fresh client/reload result;
* the relevant error count before and after;
* confirmation that the intended addon feature still works;
* a commit reference explaining the final design.
