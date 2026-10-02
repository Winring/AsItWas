# WoW 12.x API / UI cross-reference

This document is the required first step for changes touching WoW 12.x taint,
secret values, tooltips, map pins, protected frames, or Blizzard UI hooks. It
cross-references the current addon code with Blizzard's live UI source and
generated API documentation. It is not a runtime test report.

## Audit baseline

* Addon code audited: remote branch `fix-wow12-preserve-title-functionality`,
  commit `ae28b99`.
* Error evidence: `Reported lua errors.txt` at that commit.
* Blizzard source: `wow-ui-source` `live` files fetched from the official
  `Gethe/wow-ui-source` mirror during this audit.

## Findings

### A. Global tooltip title/text hooks

| Addon path | Blizzard path | API/value classification | Result |
|---|---|---|---|
| `AsItWasTitles.lua:391-407`, `GameTooltip:SetText` hook | `PaperDollFrame.lua:1793` → `GameTooltip:SetText` | `SetText` may receive a secret string; ordinary comparison and string processing are unsafe | **Invalid design.** The reported error is direct proof. |
| `AsItWasTitles.lua:371-387`, `GameTooltip_SetTitle` hook | `AreaPoiUtil.TryShowTooltip` and many other producers | Title is not guaranteed to be an ordinary accessible string | **Unsafe global scope.** Do not repair with only a `RETRIEVING_DATA` guard. |
| `AsItWas.lua:358-375`, `RetitleMapTooltip()` | reads `TextLeft1:GetText()` | FontString text can carry a secret aspect | **Same hazard.** Not an independent safe fallback. |
| `AsItWas.lua:328-355`, `AIW.MarkTitle()` | receives UI strings | Uses `gsub`, comparison, concatenation and formatting | Safe only for proven addon-owned ordinary text. |

The current `GameTooltip` source has separate APIs for titles, lines, widget
sets, tooltip data refresh, and secure handling. A generic setter hook sees
unrelated character, item, widget, and map tooltips.

### B. Map pin acquisition and protected mouse propagation

Current Blizzard source (`Blizzard_MapCanvas.lua` and
`MapCanvas_DataProviderBase.lua`) does this:

```text
AcquirePin
  pin:OnAcquired(...)
  pin:CheckMouseButtonPassthrough("RightButton")
    pin:SetPassThroughButtons()
    pin:SetPassThroughButtons("RightButton")
```

Generated API metadata classifies `SetPassThroughButtons` as:

```text
IsProtectedFunction = true
HasRestrictions = true
SecretArguments = "NotAllowed"
```

The addon does not call this function directly. The error says the protected
Blizzard call executes with `AsItWas` in the taint chain while acquiring a
flight-map pin. Suspect paths therefore include:

| Addon path | Operation | Static risk |
|---|---|---|
| `AsItWasTitles.lua:409-416` | hooks `QuestPinMixin.OnMouseEnter` | Addon code runs from a Blizzard pin mouse path. |
| `AsItWasMap.lua:445-462` | polls existing pins from `OnUpdate` | Does not acquire pins, but mutates Blizzard pins during map activity. |
| `AsItWasMap.lua:53-56` | `CreateTexture`, `SetSize`, `SetPoint` on pins | Mutates Blizzard-owned pin layout objects. |
| `AsItWasMap.lua:431-438` | `securecallfunction(RefreshCanvas, ...)` | Does not make the addon-controlled function body secure. |
| `AsItWasMap.lua:511`, `AsItWas.lua:416-420` | refresh from filter callbacks | Can mutate map pins from arbitrary UI/settings paths. |

The source proves the protected operation and its position, but does **not** by
itself prove which addon mutation taints it. That causality remains unresolved.

### C. AreaPOI/widget tooltip errors

Blizzard's `AreaPoiUtil.TryShowTooltip()` calls title/line functions,
`GameTooltip_AddWidgetSet`, `tooltip:Show`, and `tooltip:SetPadding`. Widget
layout then runs inside Blizzard's UI widget manager and can reach
`FontString:SetWidth`.

The old addon workaround in `a58f94d` monkey-patched `GameTooltip_AddWidgetSet`.
It is rejected and must not be restored without new source evidence. The
reported widget stacks contain no addon function before Blizzard's widget code.

**Classification:** possible interaction or taint amplification, not proven to
be caused by As It Was. Keep it separate from the direct tooltip comparison bug.

### D. FontString reads and writes

Current generated `SimpleFontString` metadata says:

```text
GetText: SecretReturnsForAspect = Text
SetText: SecretArgumentsAddAspect = Text
          SecretArguments = AllowedWhenTainted
```

This distinction is important: `SetText` being allowed to receive a secret
value in some tainted contexts does **not** mean an addon may read that value,
compare it, run `gsub` on it, or use it to construct a new string. The addon
currently reads FontString text in all of these title paths:

* Dialogue title and button decoration;
* quest-log and quest-detail title refresh;
* objective tracker headers;
* `RetitleMapTooltip()`;
* both global tooltip hooks.

The displayed quest-title paths may be safe when their source text is known to
be ordinary quest data, but they are not interchangeable with tooltip text.
Each path must be classified by its actual source before passing the value to
`AIW.MarkTitle()`.

The same metadata marks `GetStringWidth()` as conditionally secret. Therefore
the addon must also avoid assuming that layout measurements read from
Blizzard-owned FontStrings are always ordinary numbers when those strings may
have acquired secret aspects.

### E. Reference addon comparison

AngrierWorldQuests was checked at commit
`a28350ceff2fd64653852a0e65783c8309862980`. Its relevant hover path is for
addon-owned quest-list rows: it stores `button.awqTitle` and renders an
addon-owned `AWQTooltip`. It explicitly avoids reading a FontString with
`GetText()` for that tooltip. Its map-pin code is polling/post-processing and
does not retitle Blizzard's native `QuestPinMixin` tooltip.

WorldQuestsList was checked at commit
`6fe2892769a969d91b13c9aba5072d60deec9f28`. Its map code creates
`WQL_AreaPOIPinMixin` pins and uses its own `self.name` in
`GameTooltip_SetTitle`; it does not hook the native quest pin and then read
`GameTooltip.TextLeft1`. This is an older implementation and is not proof of
WoW 12.x safety, but it confirms that the two reference addons do not use the
same path as As It Was.

As It Was now follows the safer part of that design: it no longer hooks
`GameTooltip:SetText`, `GameTooltip_SetTitle`, or `QuestPinMixin:OnMouseEnter`.
`AsItWasMapTooltip.lua` observes existing pins from an addon-owned ticker and
renders an addon-owned tooltip. The prefix is a separate addon-owned line, so
the Blizzard title is never concatenated, compared, parsed, or read from the
native tooltip FontString.

The polling path uses `IsMouseMotionFocus()`, not `IsMouseOver()`. Current
`SimpleScriptRegion` metadata marks `IsMouseOver()` as
`SecretWhenAnchoringSecret`; `IsMouseMotionFocus()` is the ordinary boolean
focus query used by this design. Blizzard-owned visibility state is not used to
decide whether a pin is hovered.

The first custom-tooltip revision intentionally showed only the title and As It
Was prefix. That was not content-equivalent to Blizzard. Current Blizzard
`QuestPinMixin:OnMouseEnter()` adds the title, quest type, quest time, waypoint
text, and—when applicable—unfinished item drops or quest objectives. The custom
tooltip now calls the same Blizzard tooltip helpers and follows the same branch
order on an addon-owned `GameTooltip`. It still never reads the native tooltip
FontStrings or copies rendered lines out of them. If a data/helper call rejects
a secret value, the protected call leaves the native tooltip as the fallback
source rather than attempting to inspect or reconstruct that value.

Blizzard prepends `QUEST_DASH` to waypoint/objective strings in its native
implementation. As It Was intentionally does not concatenate that prefix with
returned quest text: the text is passed directly to the addon-owned tooltip.
This avoids converting a potentially secret string into a new string; the
tradeoff is that those special lines may not include Blizzard's dash glyph.

## Source-level conclusions

1. The `GameTooltip:SetText` hook is independently proven invalid. It must be
   redesigned or removed, not patched with another string comparison.
2. `GameTooltip_SetTitle` and `RetitleMapTooltip()` rely on the same unsafe
   assumption and must be audited as one tooltip-retitling design.
3. `SetPassThroughButtons()` is Blizzard's protected operation. The addon does
   not call it directly; the remaining question is whether addon map hooks or
   pin mutations taint acquisition.
4. `securecallfunction()` is not proof that an addon-controlled function body is
   secure.
5. Widget errors remain a separate, unproven category.
6. `FontString:GetText()` and `GetStringWidth()` are conditional/secret-aware
   APIs; every addon read must be classified by the source FontString, not by
   the apparent UI label.
7. A reference addon using a custom tooltip is evidence for architecture, not
   evidence that a native Blizzard tooltip may safely be rewritten.

## Required procedure for future changes

1. Fetch the current remote branch and record its commit.
2. Enumerate every Blizzard function, mixin, frame, and value crossing the
   addon boundary.
3. Look each item up in current Blizzard source and generated API metadata.
4. Mark protected functions, secret arguments/returns, secret aspects, secure
   execution ranges, and object mutations.
5. Compare the result with `FAILED_EXPERIMENTS.md` and commit history.
6. Only then propose the smallest code change. Runtime testing validates a
   change but cannot replace this audit or prove universal absence of a rare
   failure.
