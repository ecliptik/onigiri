# PLAN — Logging several items from one read (2026-08-23)

A menu, a nutrition guide, a screenshot of a comparison table: one read,
many things you actually ate. Today the read is thrown away after the
first pick everywhere except the share extension, so the second item
costs a second photograph, a second OCR pass, a second Vision escalation,
and — where the row printed no calories — a second run at the model.

> **STATUS — BUILT 2026-08-23.** Decisions taken with the user are
> marked **[decided]**. What changed on contact with the code is at the
> end under *"What shipped"* — read that before trusting any paragraph
> above it, which is preserved as the pre-build reasoning.

## What breaks today, precisely

The loop already exists. It exists in exactly one place, and it is the
one place that isn't the app.

| Door | Host | After the first pick |
| --- | --- | --- |
| Photographed menu board | `ScanSheet` → `.menuPhotoPicker` | `onLabel(picked); dismiss()` — sheet, camera, list, all gone |
| Multi-food screenshot | `ScanSheet`/`SharedImageSheet` → `.screenshotCandidates` | dialog cleared, `dismiss()`, cascade discarded |
| Shared image | `SharedImageSheet` | `.sheet(item: $pick, onDismiss: { dismiss() })` — the form's dismissal takes the host with it |
| Shared PDF / link, drained into the app | `MenuImportSheet` | **list survives** (form stacks over it) but nothing says what was logged |
| Shared PDF / link / image, in the extension | `OnigiriShare/ShareFlow` | **logs, appends to `logged`, returns to `.picking`** with a running note |

`ShareFlow` got this right on 2026-08-16 and left a comment saying why:
*"A nutrition guide is read once and ordered from several times —
logging one item and tearing the whole flow down meant re-sharing the
document to add the fries (the user)."* That is the same sentence the
user wrote again on 2026-08-23, about the in-app doors.

Two smaller faults fall out of the same gap:

- **`MenuPicker.note` is dead outside the extension.** `MenuPhotoSheet`
  declares `var note: String?` and never passes it to the `MenuPicker` it
  builds; `menuPhotoPicker` has no note parameter at all. The slot for
  "Logged Greek Chicken. Choose another" is already cut and already
  wired in one caller.
- **A `confirmationDialog` has nowhere to put a running note**, so the
  multi-food screenshot path cannot be fixed without changing its
  control. The extension already made that call: *"Few enough for the
  dialog in the app; here the same picker serves, and one control is
  better than two."*

## Decisions

- **[decided] Repeat-pick, not multi-select.** Tap a row, confirm it,
  land back on the same list with a note naming what was logged; Done
  closes. Matches `ShareFlow` exactly, so there is one interaction model
  in the product rather than two.
- **[decided] Quick confirm in the app, not the full form.** Picking a
  row from a list opens the portion/meal confirm with the receipt of
  everything about to be written — `ShareLogSheet`'s shape — and Log
  returns to the list. The full `FoodFormView` is what a SINGLE-item read
  still gets, and what the Add Food form still gets; see the purpose
  split below.
- **[decided] Nothing persists between sessions.** The list lives as long
  as the sheet, as `PLAN-menu-import` requires. The waste this plan
  removes is re-reading the same photo twice in one sitting, not
  re-finding yesterday's menu.
- **[decided] All four doors.** Menu photo, multi-food screenshot, shared
  image, shared document/link.
- **Library saving stays opt-in in the app.** `ShareLogSheet` saves the
  dish to the library unconditionally because an extension has no other
  way to keep it. The app's rule is the opposite and the user wrote it:
  *"saving to the library is the option, not the price of admission"*
  (`QuickLogSheet`, `purpose: .logging`). So the in-app confirm carries a
  **Save to Food Library** toggle, default OFF, and the extension keeps
  its unconditional save. A dish logged without saving is still
  re-loggable from the Log sheet's history rows, which is the app's
  existing answer for this.
- **No "Edit details…" escape from the confirm.** Considered and
  dropped — the receipt already shows every value that will be written,
  and a door into `FoodFormView` from inside the loop reintroduces the
  sheet-swap the loop exists to avoid. A wrong figure is a reason to
  Cancel and use the form door, not a reason to nest one.

## The shape

One flow view, hosted by everything, so the loop is written once.

### `MenuPickerFlow` (new, `Onigiri/Views/MenuPickerFlow.swift`)

Compiled into BOTH targets, the way `Onigiri/Views/MenuPicker.swift`
already is (`project.yml` lists it under `OnigiriShare.sources`). Owns
the whole pick→confirm→log→pick loop and nothing else:

```swift
struct MenuPickerFlow: View {
    let rows: [MenuRow]
    let suggestedSource: String?
    /// Writes the log. The app passes LogActions.logFood (toast + undo +
    /// didMutate); the extension passes its own HealthKitService path,
    /// which must keep its requestAuthorization() pre-flight.
    let log: (ParsedLabel, FoodCategory, Double) async -> Bool
    let onFinish: (_ logged: Bool) -> Void
}
```

State: `logged: [String]`, `chosen: ParsedLabel?`, `category`, `quantity`
— lifted verbatim out of `ShareFlow`, including the two rules already
learned there:

- **The meal slot does NOT reset between items; the quantity does.**
  Several items off one menu are one meal, and re-picking "Dinner" four
  times is the busywork this exists to remove.
- **Estimation happens at PICK time, per item, never up front.** A menu
  lists thirty dishes and one is being eaten; `FoodIntelligence.describeFood`
  runs for that one. This is already true in both `MenuPhotoSheet.choose`
  and `ShareFlow.choose` — keep it, and keep the `aiGenerated` mark
  riding out with the numbers.

### `LogConfirmSheet` (moved, `Onigiri/Views/LogConfirmSheet.swift`)

`ShareLogSheet` lifted out of `ShareFlow.swift` unchanged except for the
new toggle, and added to `OnigiriShare.sources` beside `MenuPicker.swift`.
It must keep the whole "Also logged" receipt and the dropped/suspect
findings footer: that section exists because a shared page logged
**810,400 mg** of sodium behind a button that showed only calories
(`PLAN-nutrition-plausibility.md`). Bringing the quick confirm into the
app without the receipt would re-open that hole on three more doors —
the receipt is the *reason* a quick confirm is acceptable here at all.

The extension passes `saveToLibrary: .always`; the app passes
`.optional(default: false)` so the toggle renders.

### Purpose split — which hosts loop

A door that exists to FILL A FORM must not start logging.

| Host | Purpose | Behavior |
| --- | --- | --- |
| `QuickLogSheet` → `ScanSheet` | `.logging` | loop |
| `SharedImageSheet` | `.logging` | loop |
| `MenuImportSheet` | `.logging` | loop |
| `ShareFlow` | `.logging` | loop (as today) |
| `FoodFormView` (blank Add Food) → `ScanSheet` | `.filling` | first pick fills the form and dismisses — today's behavior, unchanged |

`ScanSheet` gains `var purpose: ScanPurpose = .filling` and passes it to
the flow. `FoodFormView` already carries the same distinction under its
own `Purpose`; use the same word, not a second vocabulary.

`QuickLogSheet` must also hand its **`logDate`** to `ScanSheet` — the Log
sheet backfills into the browsed day, and a log written straight from the
picker would otherwise land on today. This is new plumbing: today
`ScanSheet` never logs, so it never needed the date.

### The multi-food screenshot changes control

`.screenshotCandidates` (the `confirmationDialog` in
`EntryDoorsSection.swift`) is retired in favor of the same picker, with
candidates mapped to `MenuRow`s exactly as `ShareFlow.readImage` already
does. Reasons, in order: a dialog cannot hold a running note; a dialog
cannot be returned to; and two controls for one job is what the extension
already rejected.

**This contradicts a comment and a CLAUDE.md line that must be updated
together** — the dialog was chosen in `PLAN-screenshot-nutrition` Part C
partly because *"swapping a sheet from inside a sheet is the dismissal
race that bit twice on 2026-07-22."* That reasoning is intact and is
respected here: the picker sheet **stays up** and the confirm opens as a
NESTED sheet over it. Nothing swaps a binding mid-dismissal. `PortionSheet`
already documents this exact distinction — *"a nested sheet is fine, it's
SWAPPING one slot's binding mid-dismissal that races"* — and the deferred
`Task { }` hand-offs that `SharedImageSheet` added on 2026-08-17 come out
with the swap they were protecting.

## Landmines this walks into

- **The camera keeps running behind the picker.** `ScanSheet`'s
  `ScannerRepresentable.updateUIViewController` calls `startScanning()`
  on every update unless `delivered`. Today the sheet dismisses on the
  first pick, so nobody noticed; a loop leaves the live scanner burning
  behind the list for as long as the user is choosing. Add a `paused`
  input gated on "a picker or confirm is up", and keep
  `dismantleUIViewController`'s unconditional `stopScanning()`.
- **`showsFrozenFrame` doesn't know about menus.** It is
  `capturedStill != nil && (isReading || delivered || !candidates.isEmpty)`
  — `menuItems` is absent, so a photographed MENU already shows live
  camera behind its picker. Extend it, and re-check it once `candidates`
  becomes rows: the condition must be "some list is up", not a list of
  every state variable that can mean that.
- **`.sheet(item:)` identity collapses menu rows.** `MenuImportSheet`
  already carries the fix and the reason: every menu row folds to a
  barcode-less `ScannedProduct`, so product identity would make all 113
  rows one item and the sheet would refuse to re-present. Its `Pick` is
  keyed on an incrementing counter. The flow's `chosen` must do the same
  — two rows can share a name.
- **`markUsed`/recency must fire on CONFIRM, never on pick.** Recency
  means logged, never looked at (2026-08-14). A menu row has no library
  row behind it, so there is nothing to stamp until the optional library
  save happens — which is the confirm handler.
- **The extension's `requestAuthorization()` pre-flight is not
  optional and is not shared.** It is a different process; without it a
  log lands carrying calories and nothing else, silently
  (`CorrelationWritePolicy`). It stays in the extension's `log` closure,
  not in `MenuPickerFlow`.
- **The extension does not touch the meal graph.** `saveToLibrary` there
  only ever fetches and inserts `Food`, which is why it is immune to the
  dangling-reference process kill and why it runs no repair pre-flight
  (declined 2026-08-18). Moving that function into shared code must not
  quietly give it a `Meal` fetch.
- **`LibraryDuplicate.nameMatches` is the only name rule.** The optional
  in-app save uses it, not an exact-match predicate — the extension's own
  twin-minting bug (audit 2026-08-17).
- **A `MenuPicker` under `.searchable` gets a transient
  onDisappear/onAppear pair when the keyboard dismisses.** Nothing in the
  flow may cancel work or clear `logged` from `onDisappear`.

## Work, in order

1. **Kit:** `MenuPickProgress.note(logged:)` — the pure string builder
   behind *"Logged X. Choose another, or tap Done."* / *"Logged N items,
   last X…"*, lifted out of `ShareFlow.loggedNote` so the app and the
   extension cannot drift. Unit-tested for 0/1/N.
2. **Move** `ShareLogSheet` → `Onigiri/Views/LogConfirmSheet.swift`, add
   the save toggle, add to `OnigiriShare.sources`, `xcodegen generate`.
   Extension unchanged in behavior; run it once before going further.
3. **New** `MenuPickerFlow`, also in `OnigiriShare.sources`. Rewrite
   `ShareFlow` to host it — the extension is the reference behavior, so
   porting it first proves the extraction lost nothing.
4. **`MenuImportSheet`** hosts the flow instead of `FoodFormView`; the
   single-food fallback (`SharedPageReader.singleFood`) goes straight to
   the confirm, as `ShareFlow` does.
5. **`SharedImageSheet`** hosts the flow for `.menu` and `.candidates`;
   drop the `onDismiss: { dismiss() }` self-teardown for those cases.
   `.label`/`.food` keep the form and keep dismissing.
6. **`ScanSheet`**: `purpose`, `logDate`, camera pause, frozen-frame
   condition, `.candidates` → rows. `QuickLogSheet` passes
   `.logging` + its `logDate`; `FoodFormView` passes `.filling`.
7. **Retire** `screenshotCandidates` and `menuPhotoPicker` once no caller
   remains; delete `MenuPhotoSheet`'s dead `note`.
8. **Docs:** `PLAN-screenshot-nutrition` Part C gets the amendment (the
   dialog is gone and why), `PLAN-menu-import` gets a line pointing here,
   and CLAUDE.md's *Food entry* section loses the "which item?
   confirmationDialog" claim in the three places it makes it.

## Optional, and easy to drop

**A logged row carries a mark in the list.** The note names the last item
and a count; after four picks it cannot answer *"did I already add the
fries?"*. A `checkmark.circle.fill` on rows whose name is in `logged`
answers it, and `MenuItemRow` has the trailing slot free. Beyond parity
with the extension — say so in the commit if it ships, and drop it
without argument if it reads as clutter.

## How this gets verified

Green tests prove nothing here; the failure being fixed is a sheet
disappearing.

- **Unit (kit):** `MenuPickProgress` for 0/1/N, pinned so both hosts read
  the same sentence.
- **UI test:** drive the sample-photo door (`--label-scan-sample`
  already exists), log two different rows off one read, and assert **both
  entries exist in the day's log** — an assertion that can only pass if
  the list survived the first pick. `waitForExistence` on the picker
  proves nothing (2026-08-08); assert on the logged rows.
- **On device, all four doors** (the user hit all four): photograph a
  menu board, share a screenshot with several foods, share an image,
  share a restaurant PDF. Check the receipt renders on an AI-estimated
  row — that is the path with no printed numbers and the one where a
  wrong figure is cheapest to log.
- **Watch the camera.** After the picker has been open a minute behind a
  menu photo, the phone should not be warm. That is the pause working.

## What shipped

Everything above, with five departures. Each is a decision, not a
shortcut.

1. **The confirm REPLACES the list in the same navigation stack; it is
   not a sheet over it.** The plan said nested sheet, on the grounds
   that nesting is safe where swapping is not. Both are safe — but the
   share extension already worked by replacing content, and reusing its
   shape meant the app and the extension run the same code rather than
   two arrangements of it. It also removes the sheet from the question
   entirely: with no presentation there is nothing for the 2026-07-22
   race to act on.
   With it came something the plan did not have: while a list stands
   behind the confirm, the leading button is **Back**, not Cancel.
   Cancel-as-only-exit would have meant picking the wrong row cost you
   the read — the very complaint, one level down.
2. **A SINGLE food still opens the full form in the app.** The plan had
   `MenuImportSheet`'s stated-food fallback going to the quick confirm,
   matching the extension. It doesn't: single-item reads were never in
   scope, one dish costs one trip through the form either way, and a
   page read as PROSE is where a wrong figure is most likely and editing
   matters most (`PLAN-nutrition-plausibility.md`). The extension keeps
   the confirm there because it has no form to offer.
3. **`ScanSheet` presents the list from ONE value** — `MenuListing`
   (rows + source) through `.sheet(item:)`, replacing the rows-and-a-Bool
   the plan implied. Not tidiness: with a Bool, the picker asked "Where
   is this menu from?" about a menu that had named itself, because the
   sheet's content closure read `menuSource` before the assignment beside
   the flag landed — and `MenuPicker.task` never runs again to take the
   answer back. The Log sheet got the ordering it wanted and the food
   form did not, on identical code. Found by the UI test's second leg;
   it is now a CLAUDE.md landmine.
4. **Two pieces went into shared code the plan hadn't named**:
   `MenuRow.list(from:)` in the kit (candidates → rows, so both hosts
   convert identically) and `MenuLibrarySave` (the dedup-and-insert the
   extension had privately). `LogConfirmSheet` also gained an inline
   failure slot — a toast raised by a host underneath a sheet is
   invisible at the moment it matters.
5. **The logged-row checkmark shipped.** It was the "easy to drop"
   item; two picks in and the note alone cannot answer "did the fries go
   in".

### Verified

- `MenuPickProgressTests` — 4 tests, and the whole kit suite: 654 tests,
  0 failures.
- `testMenuPickerLogsSeveralItems` (opt-in, `MENU_LOOP=1`, needs
  `--menu-scan-sample`): logs two rows off one list, asserts the note
  reads **"Logged 2 items"** — which only a list that survived the first
  pick can render — then expands the day's meal sections and finds both
  entries in Health. Leg 2 drives the same list from a blank Add Food
  form and asserts the form fills and **no confirm step appears**, which
  is what tells the two purposes apart.
- The default UI suite: 31 tests, 24 skipped (opt-in), 0 failures.
- Screenshots at both stops: the list intact after two logs, with the
  note and both rows checked.

### Not verified here

The four doors on DEVICE, which is where a share sheet and a camera
exist. The simulator run covers the loop, the purpose split and the
logging; it cannot cover Safari → Share → Onigiri, a photographed board,
or the extension's own process.
