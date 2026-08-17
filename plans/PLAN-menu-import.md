# PLAN — Importing a whole restaurant menu (2026-08-16)

The eating-out workflow one step up from `PLAN-screenshot-nutrition.md`. That
plan solved *one* published item: screenshot it, read it, fill the form. This is
what happens when the restaurant publishes **the whole menu at once** — a
nutrition page listing every item, or a multi-page PDF guide — and you want one
row out of it.

Today that means screenshotting a slice of the table, or pasting the document
into Claude/ChatGPT and asking it to write a nutrition label you then retype.
The values are published, machine-readable, and complete; the app just can't
take them in that form.

> **STATUS — BUILT 2026-08-16, unreleased.** Decisions taken with the user
> are marked **[decided]**. What changed on contact with the real
> documents is at the end under *"What shipped"* — read that before
> trusting any paragraph here, which is preserved as the pre-build
> reasoning.

## What breaks today, precisely

Pasting a big menu screenshot "just seems to choose the first one". That is not
the model guessing badly — it is four mechanisms in a row, and only the last one
is visible:

1. **The transcript is flattened before the model sees it.**
   `readNutritionScreenshot` does `transcript.map(\.text).joined(separator: "\n")`
   (`FoodIntelligence.swift:282`). Every x/y coordinate Vision produced is
   thrown away. **This is the column-header problem exactly** — the headers
   ("Calories", "Sodium (mg)", "Protein") end up dozens of lines above the
   numbers with nothing left to say which number sits under which header. The
   model has to re-derive the table's geometry from a flat list, and on a wide
   table it can't.
2. **A 6,000-character gate returns empty, silently.**
   `guard !text.isEmpty, text.count < 6_000 else { return [] }`
   (`FoodIntelligence.swift:285`). It was written to stop a page of prose
   blowing the on-device context window, and it is correct for that. A menu is
   the other thing over 6,000 characters. One page of the CAVA PDF is
   ~8,000; the whole document is 25,140.
3. **At most six foods can come back.** `@Guide(..., .count(0...6))` on
   `ScreenshotReading.foods` (`FoodIntelligence.swift:1092`). Sized for "a menu
   section in one screenshot", which is what the feature was for.
4. **So the cascade falls through to the deterministic parse** — and
   `LabelParser` is FDA-panel geometry that can only ever describe ONE food. It
   latches onto some row's numbers, `parsed.kcal != nil` passes at
   `FoodImageReader.swift:122`, and the form opens on that row with no name.
   **That is the "first one".**

Note that (2) and (3) are *silent*: an over-long transcript and a page with no
nutrition on it produce the identical empty array, so nothing downstream can
tell "too big" from "nothing there" and say so.

And underneath all four: a screenshot is a **screen-sized window onto a
document**. You cannot fit 113 items on a phone screen, so no amount of parser
work makes the screenshot the right container for this input.

## What the two examples actually are

Measured, not assumed — both sources the user gave, fetched and inspected
2026-08-16.

**The PDF** (`assets.ctfassets.net/…/KT5_26_AN_STND_RECAN11148_DIGITAL.pdf`) —
6 pages, 25,140 characters, **113 data rows**, three nutrition pages followed by
three allergen pages.

    Recipe                          Cal.   Cal.      Total    Sat.    Trans. fat  Chol.  Sodium  Carb.  Fiber  Sugar  Protein
                                           from Fat  Fat (g)  Fat (g) (g)         (mg)   (mg)    (g)    (g)    (g)    (g)
    CURATED BOWLS
    Spicy Lamb + Avocado Bowl       800    460       52       14      0           105    1670    49     17     11     43
    Steak + Harissa Bowl            620    310       35       10      0           105    1830    39     7      7      37

Four facts that decide the design:

- **It has a real text layer with real coordinates.** No OCR required at all.
  `pdftotext -layout` reconstructs the columns perfectly, which proves the
  x-positions are in the file; PDFKit exposes the same thing on-device.
- **Reading-order extraction shatters it.** Without `-layout` the header comes
  out as `Cal.` / `Cal.` / `from Fat` / `Total` / `Fat (g)` / … — one fragment
  per line, detached from every number. That is what the model is being handed
  today, and it is unparseable by anything.
- **The header repeats on every nutrition page, at different x-positions.**
  Columns must be re-detected per page, not once per document.
- **The allergen pages carry a different header** (`Wheat`, `Milk`, `Soy`,
  `Vegan`…) with no calorie column, so they exclude themselves — the parser
  needs no page whitelist.

**The Chick-fil-A page** is the other shape. Its nutrition is inline in the page
text, but *self-labelled* rather than positional:

    Spicy Chicken Biscuit 153g Serving Size 153g 450 Calories 450 22 grams of fat 22
    Chick-fil-A® Nuggets 113g Serving Size 113g 250 Calories 250 11 grams of fat 11

No header row to align against — each item is a self-contained run of
label/value pairs, and the values repeat (`450 Calories 450`) because the markup
carries both a visible number and an accessible one.

So there are **two document shapes**, and both arrive through the same door:

| Shape | Where it comes from | How you read it |
|---|---|---|
| **Positional table** | Print-designed PDFs (the nutrition guide) | Reconstruct columns from x-geometry, match header cells |
| **Labelled runs** | HTML pages, and Safari's Reader-PDF of them | Segment per item; each value names itself |

## The thesis

**Parse the document; never send a menu to the model.**

Everything above argues one way. The values are printed, exact, and already
laid out in a machine-readable grid — asking a language model to read 113 rows
is slower, less accurate, capped at six answers, and impossible on-device
anyway. It is also the one thing the app's existing rules say not to do: printed
values win over model values, everywhere (`FoodImageReader.merged`, `refine()`,
CLAUDE.md's *Food entry* section).

The volume objection — *"look at all items and ask which one, but this could be
a lot of things"* — dissolves once the document is parsed. You never render 113
buttons. You render **a search field over 113 parsed rows**, which is the
grammar this app already uses for online results. Search is what makes a big
menu better than a small screenshot rather than worse.

That also means **the whole feature works with AI off**, which is where the app
starts.

## Part A — the door

**[decided]** Share sheet only. Safari or Files → Share → Onigiri. No in-app
Files picker, no text paste, no URL handling.

This covers both examples, because Safari's Share sheet can hand over a web
page **as a PDF**: Share → *Options* → PDF (or Reader PDF, which strips the
navigation furniture). So the Chick-fil-A page and the CAVA guide arrive as
the same kind of object, and no URL is ever fetched — which keeps
`PLAN-screenshot-nutrition`'s veto on URL fetching and per-site HTML parsing
intact. The document, not the link, stays the interface.

Two mechanisms produce that door. **Try the cheap one first:**

**A1 — declare document types on the main app.** `CFBundleDocumentTypes` for
`com.adobe.pdf` (plus `LSSupportsOpeningDocumentsInPlace`), and handle the
incoming file in `scene(_:openURLContexts:)`. No new target, no app group
hand-off, no memory ceiling, and the app is in the foreground with the full
cascade available. The `onigiri://` URL scheme and the app group already exist
(`project.yml:94`, `LibraryModels.swift:244`) but neither is needed on this
route.

**A2 — a share extension**, only if A1 doesn't put Onigiri in the share sheet
where the user expects it. This must be verified on device, not assumed: how
document handlers surface in the iOS 26 share sheet versus the app row is not
something the simulator settles.

If A2 is needed, two landmines come with it, both already half-documented in
this repo:

- **A share extension cannot reliably open its host app.**
  `extensionContext.open(_:)` is unreliable for share extensions, and the
  responder-chain walk to reach `UIApplication` is the trick that gets apps
  rejected. Design for **not** opening the app: the extension stashes the file
  in the app group and the app sweeps that inbox on next foreground, offering
  "A menu is waiting to import." One extra tap, no fragile call.
- **Keep it a thin hand-off** — stash and exit. Parsing inside the extension
  is the memory ceiling `PLAN-screenshot-nutrition` Part D already warned about,
  and this cascade downsamples specifically because a full-size decode is
  "jetsam territory".

Either way the file must be copied into the app's own container and **deleted
after the import sheet closes** — one-shot means one-shot, and an abandoned
inbox is the other thing Part D warned about.

## Part B — `MenuTableParser` (kit, pure, fixture-tested)

Lives in `Packages/OnigiriKit`, alongside `LabelParser` and following its
division of labour exactly:

- **App side** (`MenuDocument.swift`, sibling of `LabelScan`): PDFKit opens the
  document and emits positioned text.
- **Kit side** (`MenuTableParser.swift`, sibling of `LabelParser`): pure
  function, no Apple frameworks, unit-tested against fixtures.

**Reuse `LabelObservation` as the input type.** It is already exactly right —
text plus a bounding box, `Codable` and `Sendable`, documented as
"Vision-normalized (origin lower-left, unit square)" (`LabelParser.swift:3`).
PDFKit's coordinates share that origin, so the adapter divides by the page
bounds and the two producers agree. The payoff is large: OCR transcripts and PDF
pages become the same input, the existing fixture-dump discipline carries over
unchanged, and a future "photograph the printed menu on the wall" route needs no
new parser.

    public enum MenuTableParser {
        public static func parse(_ page: [LabelObservation]) -> [MenuRow]
    }

    public struct MenuRow {          // → ParsedLabel, so every existing
        public let name: String      //   downstream path is reused as-is
        public let section: String?
        public let values: NutrientValues
        public let kcal: Double?
        public let sodiumMg: Double?
    }

### The algorithm

1. **Band the page into rows** by y — the same clustering `LabelParser` already
   does over OCR observations.
2. **Find the header band**: the topmost band whose text matches ≥3 known
   nutrient headings. No match on a page ⇒ not a nutrition table ⇒ return
   nothing. (This is what silently and correctly skips the allergen pages.)
3. **Assemble header *cells* by x-range, across stacked lines** — see the traps
   below; this step is the whole parser.
4. **Map cells to nutrients** by whole-cell match against a synonym table
   (`Cal.`/`Calories`/`Energy`, `Sodium (mg)`/`Sodium`, `Carb. (g)`/
   `Total Carbohydrate`…). An unmapped cell is dropped, not guessed at.
5. **Each following band is one row**: text left of the first numeric column is
   the name; each number is assigned to the column whose x-range contains its
   centre.
6. **Repeat per page** — headers and x-positions both move.

### Four traps, each already visible in the fixture

- **`Cal.` appears twice and the bare one is the one you want.** The header is
  two stacked lines; `Cal.` sits on the lower line for the calories column and
  on the upper line as the first half of `Cal. from Fat`. Match the assembled
  cell, never a substring.
- **Three columns contain the word "Fat"** — `Total Fat (g)`, `Sat. Fat (g)`,
  `Trans. fat (g)`. Same rule, and the reason cells must be whole.
- **The header is not one line.** `Sodium` is on the upper line and `(mg)` on
  the lower; `Chol. (mg)` is on the lower line alone. Cells assemble by
  x-range across both lines, not by line.
- **A numberless band is ambiguous** — it is either a section heading
  (`CURATED BOWLS`, `BASES`) or the second line of a wrapped item name. Rule:
  all-caps ⇒ heading; otherwise append to the previous row's name. This one is
  a guess dressed as a rule and belongs in a fixture before it is trusted.

The labelled-runs shape (Chick-fil-A) is a second entry point on the same type —
segment on repeated value labels, no header alignment — and should be built
**second**, once the positional path is proven.

## Part C — the picker

**[decided]** One-shot. Parse, choose, log, discard: nothing persists but the
food you actually kept, which lands in the library and reaches Recent and
Favorites by the normal route. No `Menu` model, no staleness, no watch payload,
no backup surface.

The import sheet is a plain `List` of parsed rows under the **standard system
`.searchable`, bottom placement** — the same bar as everywhere else, no custom
bar, no auto-focus (CLAUDE.md *Food entry*). Sections from Part B's headings.
Each row reads dish and cost, matching the existing `candidateLabel` grammar
(`EntryDoorsSection.swift:220`): *Spicy Lamb + Avocado Bowl — 800 kcal*.

**[decided]** Tapping a row opens the **prefilled `FoodFormView`** — the same
thing a screenshot read does. `MenuRow` folds to `ParsedLabel` and enters
`onLabel`, so the entire downstream path is the one already shipped, reviewed
and tested.

Deliberately **not** reusing `.candidates` / `screenshotCandidates`: that is a
`confirmationDialog` sized for a handful of items and would be unusable at 113.
This is a new presentation over the same outcome type. A menu import should
produce a fifth `FoodImageOutcome`-style case (`.menu([MenuRow])`) rather than
overloading `.candidates`, so the dialog keeps meaning "a few, pick one".

Two rules inherited rather than re-derived: no provenance mark (parsed printed
values are not estimates — the `refine()` ruling), and defer any
sheet-to-sheet swap one turn (the 2026-07-22 dismissal race).

## Part D — naming

**[decided]** Prefix imported items with their source: *CAVA — Greek
Chicken*. A bare "Greek Chicken" is ambiguous the moment a second restaurant has
one.

**The source often cannot be detected, and this was checked.** The CAVA PDF
contains no brand name anywhere in its text — the title is the InDesign filename
`KT5_26_AN_STND_RECAN11148.indd`, the footer is the same job code, and the logo
is artwork, not text. A detector built on this feature's first real document
would have returned nothing.

**[decided]** So: use what the document offers, and **ask when it offers
nothing**. Detection is the optimisation; the prompt is the contract.

- Try the PDF title, then the first page's heading. Accept only something that
  reads like a name — reject job codes, `.indd` filenames, and the generic
  "Nutrition and Allergen Guide".
- Nothing usable ⇒ **ask, in a dialog, before the list appears**, with the field
  empty. One question, once per import, and a one-shot import means it is never
  asked twice for the same document.
- Detected ⇒ prefill it and let the field be edited or cleared. Cleared means no
  prefix.

The prefix is applied when a row is picked, so it arrives in the form's name
field and is still editable there.

## Where AI still helps — small, optional, never load-bearing

Everything above runs with AI off. Two narrow jobs remain worth the model, both
scoped to **one row at a time** so the 6,000-character gate is never in play:

- **Rescue an unparsed row.** A row the geometry couldn't align is one short
  line of text — exactly what `readNutritionScreenshot` is already good at.
- **Name the source** when the field is blank and the document has a header
  worth reading.

Neither blocks the import. `readNutritionScreenshot` should keep its
6,000-character gate for its own callers, but the gate needs to stop being
silent: distinguish "too long" from "nothing found" so the caller can say which.

## Testing

- **Fixtures are the whole game, and they are free here** — a PDF's text layer
  is deterministic, with none of the lighting or perspective variance photo
  fixtures carry. Extend `scripts/dump-label-ocr.swift` (or add a sibling) to
  dump `[LabelObservation]` from a PDF page, and never hand-transcribe, per
  CLAUDE.md.
- Commit both example documents' first nutrition page as fixtures. The CAVA
  page pins: 113 rows across the document, `Cal.` mapping to calories and not to
  calories-from-fat, the three Fat columns landing separately, `CURATED BOWLS`
  read as a section and not an item, and the allergen page yielding **nothing**.
- One invariant worth pinning like `theSmoothedLineEndsOnTheBudgetBasis` did:
  **every parsed row's numbers come from its own band.** The four-salads-all-490
  bug (`PLAN-screenshot-nutrition` "What shipped") was exactly this failure in
  the AI path, and a geometry parser can make it too if a band is mis-clustered.
- Device check required for Part A: whether Onigiri appears in Safari's share
  sheet from A1 alone, and whether Options → PDF captures the Chick-fil-A
  page's nutrition (its values are in the page text, but a print stylesheet can
  drop them).

## Not doing

- ~~**Fetching a URL.**~~ **REVERSED in round three — see *What shipped*.** The
  reasoning below still holds for what it actually forbade: per-site HTML
  parsing that rots per restaurant. What ships instead renders the shared page
  to PDF and reads it with the same table parser, so there is no HTML parsing
  and nothing site-specific. The original text: *arbitrary fetching plus
  per-site HTML that rots per restaurant, against an off-by-default network
  posture. Sharing the page as a PDF gets the same data with none of that.*
- **Persisting menus.** [decided] — the library is already the repeat-visit
  path.
- **Sending the whole document to a model.** The thesis of this plan.
- **Multi-select logging** (sandwich + fries + drink in one pass). Considered
  and set aside: it bypasses the form's review step, and it can be added later
  over the same parsed rows without changing anything here.
- **Text paste and an in-app Files picker.** Both cheap, neither chosen. The
  paste door stays image-only.

## Sequencing

1. **Part B first, against committed fixtures** — no UI, no target changes, the
   parser and its tests standing alone. It is the part that can be wrong in ways
   only fixtures catch, and everything else is worthless without it.
2. **Part A1** (document types) plus a minimal import sheet — one real document,
   end to end. Verify the share-sheet appearance on device here, before building
   anything on the assumption.
3. **Part C** properly: search, sections, the source field.
4. **A2** only if step 2 proves A1 doesn't surface the app.
5. Labelled-runs shape (Chick-fil-A via Reader-PDF), once positional is solid.
6. Part E, last, and only if real use shows rows going unparsed.

## Open

- Does Safari's Options → PDF preserve the Chick-fil-A page's nutrition text?
  Its values are in the page source, but a site's print stylesheet can hide the
  very table you want. If it doesn't, that page needs the Reader-PDF variant or
  falls back to today's per-item screenshot flow — which is a legitimate answer,
  not a failure.
- Does the wrapped-name-versus-section-heading rule survive a second document?
  It is the one rule here with no evidence behind it yet.
- Serving size. The CAVA guide prints none — the row is the item as sold.
  Chick-fil-A prints grams. `ParsedLabel.servingDescription` should stay nil
  rather than invent "1 serving", but the form's behaviour with a nil serving on
  a menu row wants checking before it surprises someone.

## What shipped

Verified end to end on the simulator against the real guide: 113 items,
sections intact, "CAVA — Spicy Lamb + Avocado Bowl" at 800 kcal with 8
macros filled and the serving correctly blank.

**A1 was tried first and FAILED the device check; A2 was required after all.**
`CFBundleDocumentTypes` for `com.adobe.pdf` at rank Alternate — correct in the
source plist and in the signed binary — never appeared in Safari's share sheet,
for either a web page or a PDF. The lesson is worth more than the hour: document
types feed the Files app's "Open With"; the share sheet's app row and its
"Open in …" entries are populated by **extensions**. No amount of plist work
substitutes.

So `OnigiriShare` ships: a share extension whose activation rule is a predicate
on `com.adobe.pdf` (not `SupportsFileWithMaxCount`, which would offer Onigiri
for every document on the phone). It writes the PDF to `MenuInbox` in the app
group and exits — it does NOT try to open the app, because
`extensionContext.open` is unsupported here and the responder-chain walk is the
rejection trick. `ContentView` drains the inbox on launch and on every
foreground, which makes the foreground the delivery path rather than a fallback.
Verified on the simulator by planting a PDF in the group container: launch,
drain, sheet, 113 items, inbox empty.

The `CFBundleDocumentTypes` declaration is kept regardless — it costs nothing
and covers opening a PDF from Files. `.onOpenURL` handles that route; the
`isOurs` flag on `MenuImportRequest` is what keeps the app from deleting a file
it opened in place.

**The extractor was rebuilt mid-flight, and it is the one thing here that could
not have been reasoned out.** The plan assumed PDFKit's per-glyph geometry.
On the real document `characterBounds(at:)` reports the "i" in "Spicy" as
68 pt wide and hands back zero-height boxes for 185 of 2,133 glyphs — so the
first extractor silently ate a letter in every eighth word ("identify all" came
out "identiyall"). Two wrong diagnoses preceded the right one: an assumed
`page.string`/index-space mismatch (they DO align), then a `selection(for:)`
detour that reproduced the same damage. `selectionsByLine()` was the answer and
is better than what was planned — it returns one run per table CELL, already
positioned, so the "assemble header cells by x-range" step reads straight off
it.

**Two traps the plan predicted were real; one it missed.** `Cal.` twice and
three "fat" columns both landed exactly as described. The miss: adjacent cells
with a narrow gap come back as ONE selection — `"0 105"`, `"7 7"` — so a run
can hold two columns and has to be split by which column centres it spans.
Without that, trans fat and cholesterol merge.

**The section-heading bug was in the plan's own algorithm.** Iterating from the
first DATA row skips the first heading, which sits between the header and the
data — every item in the opening section came out unlabelled. The body starts
below the HEADER, not at the data.

**Source detection was cut back after it failed its own test.** A filename
fallback made `suggestedSource` return "menu-cava" — passing the test for
the wrong reason and prefixing items with whatever the download was called. The
title is the only source now, and nil is the ordinary answer.

### Round three: the share sheet, for real

The PDF-only activation predicate was wrong for a second reason, found only by
trying it: **Safari hands the share sheet a `public.url` for a remote PDF**, so
the predicate never matched the CAVA guide either, and a web page needed
Share → Options → PDF, a control the user could not find. The rule is now the
dictionary form (web URL + image + file). The clutter that argued against it is
the user's to prune in Edit Actions — their call, and it removes the only
objection.

**A shared link is now resolved by the app**, which reopens the URL veto on
purpose and lands somewhere the veto did not cover: `MenuLinkLoader` downloads
the link when it is a PDF and otherwise renders the page with
`WKWebView.createPDF()`. There is **no HTML parsing** — no selectors, nothing
per-site, nothing to rot. The browser lays the page out and the same
`MenuTableParser` reads the text layer.

That last point is the real discovery of this round: **there is no second
document shape.** The plan predicted "labelled runs" needing their own parser.
A rendered page is a positional table like any print PDF, so step 5 of the
sequencing is deleted rather than done. What a page *does* carry is furniture,
and four bugs came out of it — each now a fixture:

1. A **serving column** left unrecognized sat left of the numbers and was swept
   into the name: "Spicy Chicken Biscuit 153g".
2. A **category sidebar** at the far left shared bands with table rows: "Kid's
   Meals (nutrition per entrée only) Egg White Grill".
3. The item **name sits on a baseline below its numbers**, so it arrived as a
   numberless band and was glued to the row above — "…Bowl 233g Dipping Sauces
   Dressings". `joinSubPitch` merges bands closer than 0.35 × the data pitch.
4. **Geometry alone mis-assigned values.** Header extents and data extents
   differ on that page, so a run holding two numbers put both on one column and
   fibre came out nil. Count-match positional assignment is now primary and
   geometry is the ragged-row fallback.

Plus: a **continuation page** reprints no header, so `parse(pages:)` carries
columns forward. Without it the drinks at the end of the menu vanished silently.

**Sharing a photo** was added the same round (the user): it runs
`FoodImageReader` with `.imported` — the paste door's cascade, unforked, so a
shared screenshot reads the way a pasted one does.

**Cost, and it is a real one:** `import WebKit` from Swift needs
`libswiftWebKit.dylib`, which first ships in **iOS 18.6**. No SDK carries an
embeddable copy, so on 18.0–18.5 the app does not launch at all. The iOS
deployment target is now 18.6.

### Round four: the key that was silently dropped

The extension still did not appear, and the cause was neither the rule nor the
signing: **`NSExtensionActivationRule` was nested one level too shallow.** It
belongs under `NSExtensionAttributes`; placed directly under `NSExtension` it is
ignored outright, so the extension matched nothing and appeared nowhere. There
is no build error, no runtime log, and no diagnostic of any kind — and both the
`project.yml` and the shipped plist *look* fine unless you know the required
shape. Verify the built `.appex` plist, not the YAML.

Two rounds were spent on the activation rule's CONTENT while the rule was never
being read at all. Worth remembering as a class of bug: when a declarative
mechanism produces no effect whatsoever, check that the declaration is in a
place the system reads before refining what it says.

**Still open:** the wrapped-name-vs-heading rule has two documents behind it now
but is still the weakest rule here. The rendered-page fixtures are a snapshot of
a live site and will drift. And the share sheet itself is verified by
construction plus simulator injection of every route — the real
Share → Onigiri tap is the outstanding device check.


## Round 6 — a sweep of real restaurant menus (2026-08-16)

Eight real documents were fetched and run through the shipping path
(`MenuDocumentReader` → `MenuTableParser`) rather than reasoned about.
Every defect below was found by MEASURING, and each one had produced
plausible-looking output beforehand.

| Document | Shape | Result |
|---|---|---|
| CAVA | positional table, header per page | 113 rows (reference) |
| Chick-fil-A | rendered web page | control fixture |
| Shake Shack | name+allergens+calories in ONE run | 292 rows |
| McDonald's | 22 columns incl. %DV and micronutrients | 463 rows |
| Chipotle | plain table | 66 rows |
| Wendy's | 4 columns only (no sodium) | 72 rows |
| Cheesecake Factory (KSA) | per-letter text, merged header cells | rejected — see below |
| Starbucks / Buc-ee's / Handel's | not documents at all | rejected |

### What the sweep changed

- **"CALCIUM" contains "cal".** McDonald's micronutrient columns matched
  the calorie keyword, sat to the RIGHT of the real one, and overwrote
  it: every row read 25 kcal instead of 740. Wrong data, silently, on
  the largest chain in the country. `ignoredHeaderWords` now recognises
  micronutrient and %DV columns in order to skip them, and
  `deduplicated(_:)` keeps a repeated field's LEFTMOST column.
- **A section heading is a matter of type SIZE, not capitals.** Shake
  Shack sets sections in Title Case, so an all-caps test filed them as
  wrapped names and glued them onto the row above. No document in the
  sweep produced a single section. A heading measures ≥1.25× the median
  data-row height; the marketing prose beside it measures 0.81×.
- **Merged HEADER runs.** The Cheesecake booklet extracts
  "Cholesterol Carbohydrates Total Sugars Added" as one run across four
  columns. `splitMergedHeaderRun` splits a run that names two or more
  different nutrients, apportioning x by character offset.
- **A failed parse must return NOTHING.** That booklet sets product
  names as individual letters, which clustered into
  "T R I P O L A C I G G N R E E L O O C R" beside a 0 kcal — 171 rows
  of confident nonsense. Three gates now stand between a broken mapping
  and the picker: a name must contain a WORD (`looksLikeProse`), a page
  must declare at least three value columns, and the rows must fill at
  least `minimumFieldFillRate` of what the header promised. The booklet
  drops from 171 rows to 9; Wendy's fills 4 of 4 and is untouched.
- **An image-only PDF is now OCR'd**, not refused. `readOCR` renders any
  page carrying fewer than `scannedPageRunLimit` runs and reads it with
  Vision, which returns the same normalized observations PDFKit does —
  so a scanned guide takes the ordinary path with no second parser. A
  rasterised Wendy's guide goes from 0 rows to 47. Capped at
  `ocrPageLimit` pages: OCR costs ~1 s a page and a share sheet that
  thinks for half a minute reads as a hang.

### What a shared LINK can be

Not a PDF, often. Beyond the Widen viewer (Round 5), three of the
"nutrition PDFs" that search engines offered were **CAPTCHA
interstitials** served from `website-files.com` CDNs — a real risk for
any link a user shares. They read as documents with no table, which is
what the sheet says.

### Known gaps, deliberately left

- **A menu that exists only as a web calculator** (Taco Bell, Buc-ee's)
  has no document to import. Nothing to parse; the photo and screenshot
  doors cover it.
- **Per-letter text layers** (Cheesecake Factory KSA) parse partially.
  The rows that survive are real; the ones dropped are dropped quietly.
  Fixing it properly means reassembling glyph runs into words, which is
  the `characterBounds` road that Round 1 already found unusable.
- **Micronutrients are not stored**, so vitamin/iron columns are read
  only to be ignored.


## A correction: the reference document is CAVA's, not Kwik Trip's

The PDF this parser was built against was called "Kwik Trip" throughout
the code, the fixtures and this plan from the first commit until
2026-08-16. It is CAVA's. The document sells `Crazy Feta`, `Harissa`,
`Tzatziki`, `Falafel` and `Braised Lamb` under a "CURATED BOWLS"
heading; a Midwest filling-station chain sells none of that.

The mistake is instructive, because the feature documents its own cause.
The link supplied was a Contentful asset ending
`KT5_26_AN_STND_RECAN11148`, and the PDF names its restaurant NOWHERE —
title, footer and logo are all that job code or artwork, which is
precisely why `source(in:)` returns nil and the sheet asks. Somebody
read `KT5` as "Kwik Trip", and because detection was already expected to
fail, nothing ever contradicted it. An inference that no test can
disprove is worth less than the file it was written into.

Fixtures and references are renamed to `menu-cava-*`. `CHANGELOG.md` is
left alone: it is regenerated from tag messages and records what the
release notes actually said at the time.
