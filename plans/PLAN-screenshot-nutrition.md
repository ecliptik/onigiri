# PLAN — Nutrition from a screenshot (2026-07-24)

The eating-out workflow: the restaurant publishes nutrition on its own
site, so the values exist but only in Safari. Today that means
app-switching and retyping every field into the food form. The ask: get a
screenshot into Onigiri and have it fill the form.

> **STATUS — SHIPPED in v2.13.0 (2026-07-24).** Parts A, B, and C are
> built and verified on device. What changed from the plan below, and
> why, is recorded at the end under *"What shipped"* — read that before
> trusting any paragraph here, which is preserved as the pre-build
> reasoning.

**Two routes, both first-class — neither replaces the other:**

| Route | Steps | Photos residue | Build cost |
|---|---|---|---|
| **Paste** — screenshot → Done → *Copy and Delete* → Onigiri → Paste | 5 | **none** | low |
| **Choose photo** — screenshot saved → Onigiri → Choose Photo → pick | 4 + cleanup later | stays until deleted | already built, needs promoting |
| *(later)* Share extension — screenshot → Share → Onigiri | 3 | stays unless deleted | high |

Paste wins on hygiene: *Copy and Delete* is one choice in the screenshot
preview, so nothing ever reaches Photos and there is nothing to clean up.
Choosing a photo wins when the screenshot is already saved, came from
someone else, or was taken earlier. Both feed the same cascade.

## Current state (verified in code)

**The photo path already exists and already accepts screenshots** — it is
just buried. The `PhotosPicker` in `ScanSheet` (camera overlay
ScanSheet.swift:147, and the no-camera fallback :240) is NOT camera-gated;
picking a screenshot runs the same cascade as the shutter (`read(_:)`, :285):

```
UIImage → downsample 3000px → LabelScan.scan (Vision OCR)
        → LabelParser → ParsedLabel
        → FoodIntelligence.refine() (fills blanks, AI-gated, silent fallback)
        → onLabel(parsed) → prefilled FoodFormView
        └ empty parse? → falls through to identifyFood (photo-of-food path)
```

So this is not "build image import" — the cascade is done. The gaps:

**Gap 1 — no paste route at all.** No `UIPasteboard` / `PasteButton` use
anywhere in the app. Deployment target is iOS 18, so `PasteButton`
(iOS 16+) is available.

**Gap 2 — the photo route is buried.** It's a 52 pt circular button
*inside the camera overlay*, so reaching it means opening the scan sheet
and waiting out camera warm-up to tap a button that has nothing to do
with the camera.

**Gap 3 — no name.** `ParsedLabel` has no name field;
`scannedProduct(name:)` takes it from the caller (LabelParser.swift:49:
*"A label carries no barcode and no product name"*). True of a
photographed panel, **false of a restaurant screenshot**, which shows
"Quarter Pounder with Cheese" right there. It's the most tedious field
and the one a scan currently can't fill.

**Gap 4 — parser fit.** `LabelParser` is geometry over an FDA
nutrition-facts panel. Restaurant sites render HTML tables and menu
grids. Per CLAUDE.md, the iOS 26 documents/table branch fires on real
photos but "rendered label graphics don't" — a web screenshot lands on
the geometry parser, which wasn't built for it. Expect partial
extraction, not failure.

**Gap 5 — multi-item screenshots.** A nutrition page screenshot is often
a whole menu section; nothing picks which row the user meant.

## Part A — two doors in `EntryDoorsSection`

`EntryDoorsSection` is already the shared door row rendered identically
on Foods, the Log sheet, and the Add Food form — the right home, and it
already carries a provenance-caption slot. Both new doors live here and
both call the existing `read(image)` cascade.

**A1 — Paste door, directly under the search field.** Visible only when
the clipboard actually holds an image.

*Placement note.* The ask was "paste into the Foods, Meals, and More
field". Literal image-paste into that field is not available: `.searchable`
renders a system search bar SwiftUI does not hand you. The configuring
API is public (`UISearchBar.searchTextField` → `pasteConfiguration` +
`paste(itemProviders:)`), but **reaching** the bar from SwiftUI needs
view-hierarchy introspection with no public API — fragile across iOS
updates, and next door to the custom-search-bar approach already vetoed
(CLAUDE.md: "the STANDARD system `.searchable` … the user vetoed custom
bars"). What lands in the same place visually and behaviourally is a
**row leading the list**, which is this app's established grammar for
exactly this: `AIEstimateSection`'s "Estimate with …" row leads the
search results the same way. `EntryDoorsSection` renders immediately
beneath the search field whenever search is empty — which is precisely
the moment the user arrives holding a screenshot — so the paste row sits
under that field without fighting it.

Optional cheap extra: `.onPasteCommand(of: [.image])` for hardware-⌘V on
iPad. Verify behaviour on-device before promising it — its iOS support is
weaker than on macOS. An in-field paste via introspection stays an
explicit non-goal unless a spike proves it stable.

- **Use SwiftUI `PasteButton`, not `UIPasteboard.general.image`.** A
  programmatic pasteboard read raises the system "Onigiri would like to
  paste from Safari" alert *every time* — an interruption on a workflow
  meant to be repeated. With `PasteButton` the user's tap **is** the
  consent and no alert appears. That matters more than usual for an app
  whose whole posture is off-by-default privacy.
- **Gate visibility on `UIPasteboard.general.hasImages`** — a detection
  property that does **not** trigger the paste prompt, so checking costs
  nothing and reveals nothing.
- **Re-check on foreground.** The defining flow is *copy in Safari, then
  switch to Onigiri* — the clipboard changes while the app is
  backgrounded, and `changedNotification` is unreliable there. Check on
  appear AND on `scenePhase == .active`; CLAUDE.md's dead-Bool-flag
  landmine is the same class of bug.
- **Open design constraint:** `PasteButton`'s appearance is
  system-controlled and will not match `ScanRowLabel` exactly (tint and
  label style are adjustable; free-form row layout is not). Resolve at
  implementation: accept system styling, or fall back to a custom row
  plus the alert. Do not silently ship a row that looks like the others
  but behaves differently.

**A2 — Choose Photo door.** Promote the existing picker out of the camera
overlay into `EntryDoorsSection` as a peer of the scan door. Same
`PhotosPicker` binding, same `read(image)` call — a relocation, not a new
feature. Keep the in-camera button too (it's useful mid-scan when the
label won't photograph well).

**A3 — Paste into the food form's Name field.** Unlike the search bar,
**this field is the app's own `TextField`** (FoodFormView.swift:237), so
in-field image paste is reachable with public API and no introspection:
wrap it in a `UIViewRepresentable` over `UITextField`, set
`pasteConfiguration = UIPasteConfiguration(forAccepting: UIImage.self)`,
and override `paste(itemProviders:)`. With an image on the clipboard the
system Paste item appears in the field's own menu; tapping it hands over
the provider and runs **the same `read(image)` cascade as the scan door**
— so it fills the whole form (name, kcal, sodium, macros, serving), not
just the name.

Precedent: `EmojiTextField` (EmojiPrompt.swift:20) already wraps a
`UITextField` in this app for exactly this reason — UIKit behavior
SwiftUI doesn't expose. This is that pattern again, not a new departure.

Must survive the wrap, or it's a regression:
- Pasting **text** keeps behaving normally (paste a copied item name).
- The `.accessibilityLabel("Name")` workaround at FoodFormView.swift:238
  — the placeholder rides as the VoiceOver *value* and vanishes once text
  is typed, leaving the field nameless without it.
- Dynamic Type, `FocusState` participation, and the form's
  select-all-on-focus behaviour.

All three doors reuse the caption slot for provenance, and all inherit
the scan sheet's cancellation and sheet-race discipline (defer a
presentation swap one turn — the 2026-07-22 dismissal-race lesson).

## Part B — read the screenshot with the vision model

A screenshot is what the vision model is best at and the geometry parser
is worst at. New capability in `FoodIntelligence`, sibling to
`refine`/`identifyFood`, replacing neither:

- `readNutritionScreenshot(_ jpeg: Data) async -> [ScreenshotFood]?` —
  name, serving, kcal, sodium, five macros, plus a confidence marker.
- Prompt states the input is a screenshot of a *published* nutrition
  table, that values are **read, never estimated** (the `refine` prompt's
  never-invent clause, already pinned by the eval suite), and that
  unreadable fields stay null.
- Same containment discipline as the other remote paths: clamp ranges,
  reject implausible values, fall back silently.
- **Off-by-default holds.** With AI off or unavailable, today's OCR +
  `LabelParser` + blank-name behavior runs unchanged. Both doors degrade;
  neither dead-ends.

**Provenance decision (needs a ruling):** `refine()` fills blanks via AI
today and does **not** set `aiGenerated` — precedent says AI *reading*
printed values isn't an "AI estimate" and earns no ✨. I'd follow that
and mark ✨ only when the model estimates a field the screenshot didn't
show. Flagging rather than assuming — it's a rule about the app's
honesty marks.

## Part C — name and multi-item

- Name flows into `ScannedProduct.name` and prefills the form's name
  field (always blank from a scan today). Biggest single reduction in
  typing.
- More than one candidate → a picker before the form ("Which item?"),
  name + kcal per row. One candidate → straight to the form.
- The deterministic path stays name-blank: guessing a name from OCR
  geometry (largest text near the top) is a wrong-answer generator on any
  page with a site header.

## Part D — share extension (later, optional)

Screenshot → Share → Onigiri is the fewest taps, but it does **not** solve
the Photos-residue problem the paste route solves, and it costs the most:
a new app-extension target, an app-group image hand-off, a URL scheme,
and an inbox sweep for abandoned files. If built, it must be a **thin
hand-off** — stash the image, open the app, let the app parse. Share
extensions run under a much tighter memory ceiling, and this cascade
already downsamples because a full-size pick is "jetsam territory"
(ScanSheet.swift:290); running Vision plus a model upload inside an
extension invites the crash the app already engineers around.

Revisit only if Part A's tap count proves annoying in practice.

## Testing

- **Screenshot fixtures beat photo fixtures** — deterministic, no
  lighting or perspective variance. Capture via the existing
  `scripts/dump-label-ocr.swift` (CLAUDE.md: never hand-transcribe) from
  real restaurant pages; add to the `LabelParser` fixture suite so the
  deterministic path is pinned on this input class.
- AI path joins the `OnigiriTests` eval suite with its own golden set and
  gate: correct name, values-match-source, and a never-invent case
  (sodium absent from the screenshot → sodium stays nil).
- Paste door needs a device check: the simulator's clipboard doesn't
  reproduce the cross-app copy that triggers the consent behavior.

## Not doing (and why)

- **Sharing the page URL instead of the image.** No OCR at all —
  tempting — but it means fetching arbitrary URLs and parsing per-site
  HTML, which fights the off-by-default network posture and rots per
  restaurant. The screenshot is the stable interface.
- **Parsing inside a share extension.** Memory ceiling, duplicated
  cascade (Part D).
- **Replacing the photo picker with paste.** Both routes ship; they cover
  different situations.

## Sequencing

1. **Part A** — both doors, using today's parser and today's AI gating.
   No prompt work, no eval run, no new target. This is most of the win.
2. **Parts B + C** together (they share the response type), behind the
   eval suite.
3. **Part D** only if warranted after living with A.
4. CLAUDE.md gains the paste-consent rule (`PasteButton` over
   `UIPasteboard` reads, `hasImages` for visibility, foreground re-check).

**Available right now, no build:** the Photos button inside the Scan
sheet already accepts screenshots. Buried, and it won't fill the name,
but it beats retyping numbers while Part A is built.

## What shipped

Three corrections to the plan above, each earned:

**The paste-consent rule inverted.** The plan insisted on `PasteButton`
because a programmatic `UIPasteboard` read "raises the system alert
every time" — the reason it wanted the system control despite its
unstyleable chrome. On device that turned out to be false: iOS asked
**once**, then stopped. So the shipped control is a plain `DoorRowLabel`
row reading `UIPasteboard.general.itemProviders`. It matches the scan
door, it can say what it does ("Paste Nutrition Screenshot"), and the
consent alert is visible rather than implied by a tap — which was the
point. Privacy was never the variable: the app cannot read the
clipboard un-prompted either way, and visibility still comes from
`hasImages`, which reports only *that* an image exists.

Side effect worth knowing: a declined paste and an empty clipboard are
indistinguishable — iOS hands back nothing for both — so they share one
message.

**The "Choose Photo" door was built and removed the same day.** The
plan's Gap 2 ("the photo route is buried") was real, but promoting it
to its own entry row was the wrong fix — the scan sheet's photos button
already covers saved images, and a second row for it read as noise. The
photo route stays where it was; it just now runs the imported cascade
(name read included) instead of the camera one.

**Part C's merge had to become a discard.** The plan said "more than one
candidate → a picker", which shipped. What it did not anticipate: the
deterministic geometry parse can only ever describe ONE food, so on a
multi-item table it grabs some arbitrary row's numbers — and
blank-filling those into every candidate made four different salads all
read 490 kcal (seen live). Deterministic-wins is correct for a single
food and wrong for a list, so a multi-item read now discards the
deterministic parse entirely and the candidates stand alone.

**Provenance ruling** (the plan flagged it rather than assuming): the
screenshot read follows `refine()` — AI *reading* printed values earns
no ✨. The mark stays for estimates.

**Still open:** the eval golden set gating screenshot name and value
quality (Testing section above) is NOT built; the remote providers'
screenshot path is written but unverified, since keys are device-local
and the simulator has no Keychain access to them. Part A3 (paste into
the food form's Name field via `pasteConfiguration`) and Part D (share
extension) are unbuilt by choice.
