# PLAN — Numbers nobody checked (2026-08-16)

A shared Salt & Straw product page logged a 300 kcal dessert carrying
**810,400 mg of sodium** — 810 grams of sodium, about 2 kg of table salt,
352× the daily limit — into HealthKit, silently.

> **STATUS — Layer 1 BUILT 2026-08-17, uncommitted. Layers 2–4 planned.**
> Decisions taken with the user are marked **[decided]**. The layers are
> ordered so each ships alone; Layer 1 is the reported bug, Layers 2–4
> are the class of bug behind it.

Three things about that number matter more than its size:

- **It is not an AI estimate.** The log row carries no ✨, correctly: it
  came out of the DETERMINISTIC reader. The one provenance mark the app
  has said "this was read, not guessed", and that was true.
- **It was never on screen before it was written.** The share
  extension's confirm sheet shows name, calories and serving. Sodium is
  not among them, and Log writes it anyway.
- **The same page family produces wrong numbers that look right.** The
  Sea Salt with Caramel Ribbons page reads 6,000 mg — also fabricated,
  also for a 340 kcal scoop, and under every ceiling in the app.

This plan is about the second and third points. The first is the bug;
the rest is why nothing stopped it, which is the part that will happen
again with a different arithmetic.

## The arithmetic, measured

    810,400 = 2026 × 0.4 × 1000
              ^^^^   ^^^^^^^^^^
              the    LabelParser's salt → sodium conversion
              copyright year        (`saltG * 0.4 * 1_000`)

The page's last line is `Salt & Straw © 2026 All Rights Reserved`.
`LabelParser`'s keyword table maps `salt` to the salt field; the row
yields `2026` as its amount; a bare number defaults to the field's
label-convention unit, which for salt is GRAMS; salt becomes sodium at
0.4 by mass, in milligrams. 2,026 grams of salt.

Reproduced end to end against the live page, through the exact shipping
path — `PageText.stripped` → `SharedPageReader` line geometry →
`LabelParser.parse`:

    kcal=300.0  sodiumMg=810400.0000000001  sugarG=15.0  serving="1 serving"

which matches the screenshots to the digit, sugar included. The sugar
came the other way round: the ingredients line names `Sugar` with no
amount, the parser's `pending` mechanism holds the field open for two
more rows, and the next number it sees becomes the value.

Sea Salt with Caramel Ribbons, same run:

    line 59: Made with Bitterman Salt      ← keyword, no amount → pending
    line 60: $15                           ← the PRICE becomes 15 g of salt
    → sodiumMg = 6000.0                    (15 × 0.4 × 1000), kcal 340

Two pages, two fabricated sodium values, two different mechanisms —
inline (a number later on the keyword's own line) and carry-forward (the
next line's number). Both are the same underlying mistake.

## Four failures, in order

**1. A nutrition-panel parser was pointed at prose.** `LabelParser` is
FDA-panel geometry: y-bands tie a nutrient name to its amount, x-position
picks the value column, the %DV column is excluded by position.
`SharedPageReader` fabricates that geometry — every line gets `x: 0.05`
and a synthetic y — so every safeguard the parser has is inert, every
line is its own row, and every number anywhere on the page is a candidate
for every keyword above it. This is not a criticism of `SharedPageReader`
existing: reading a product page's sentence is the right feature, and it
is how the galette's 300 kcal was found correctly. The parser just has no
mode for it.

**2. A bare number is accepted as an amount, and salt multiplies by
400.** On a panel that is correct — EU panels print the unit once in the
column header (`Sel/Zout/Salz` │ `(g)` │ `0,107`), so requiring a unit
would break every European label the app reads. In prose there is no
header, and the convention does not exist. Salt is the worst field to be
wrong about because it is the only one with a ×400 amplifier, and it is
the only nutrient keyword that is also a common English word, a brand
name, and an ingredient-list entry. `Salt` appears on almost every food
page ever published.

**3. Every plausibility gate in the app is on a MODEL path.**
`plausibleScreenshotFoods`, `plausibleSignFoods`, `parseIdentified`,
`describeFoodRemote`, `plausibleMenuDishes` all bound their numbers
(sodium ≤ 20,000 mg, kcal ≤ 5,000, macros clamped in `macroNutrients`).
The deterministic path has exactly one bound in it — `kcal < 10_000` —
and nothing on any other field. Worse, in `SharedPageReader` the
deterministic value WINS: the model's read only fills fields the parse
left nil. So the gated engine defers to the ungated one. Had the model
returned 810,400 it would have been rejected; the parser said it, so it
was kept.

**4. The number was never shown.** `ShareLogSheet` renders the name,
`kcal × quantity`, the serving, and an "Estimated — review before
logging" note when `aiGenerated`. It then writes sodium and five macros
to HealthKit. There is no screen in that flow where 810,400 is visible,
so "review before logging" cannot be done even by a careful user, and
the ✨ note would not have fired here anyway — this was a read.

## The fix, in four layers

Each layer is independently shippable and worth shipping alone. Layer 1
stops the manufacture, Layer 2 catches what the next parser change
invents, Layer 3 makes anything that still gets through visible before
it is logged, Layer 4 is about the estimates the user actually asked
about.

### Layer 1 — `LabelParser` gets a prose mode  ✅ BUILT 2026-08-17

`parse(_ observations:, prose: Bool = false)`. When `prose` is true:

- an amount must carry an explicit unit (`g`/`mg`/`mcg`) to claim a mass
  field — no header exists to supply one;
- the `pending` carry-forward is off — wrapped multilingual label names
  are a panel phenomenon, and in prose it just adopts the next number on
  the page;
- salt → sodium requires that explicit unit specifically.

Energy is untouched: `Calories per serving: 300` keeps working, because
kcal has its own column logic and the bare-number-after-the-keyword
convention is real for calories (it is also how `MenuBoardParser` already
reasons — it requires the unit WORD, `780 Cal`, because "a menu is
covered in bare numbers and only this one is nutrition"). Same idea,
applied one layer down.

`SharedPageReader` passes `prose: true`; nothing else changes.

Measured, on the working tree, then reverted (diff kept):

| page | before | after |
|---|---|---|
| Peaches and Cream Galette | 300 kcal, **810,400 mg**, 15 g sugar | 300 kcal, — , — |
| Sea Salt w/ Caramel Ribbons | 340 kcal, **6,000 mg** | 340 kcal, — |
| King Arthur recipe page | nothing | nothing |
| Chipotle nutrition calculator | nothing | nothing |

**All 543 OnigiriKit tests pass.** The one thing that does NOT work is
making the unit requirement unconditional: it breaks `euPer100gPanel`
and `euTableRows`, because that is exactly the case where the unit lives
in the column header. That failure is the proof the rule belongs to
prose and only prose — worth a comment in the code, since the obvious
"just require units everywhere" refactor is wrong and looks right.

Cost of the fix: the app loses nothing it was reading correctly. Cost of
NOT fixing: every shared page whose ingredient list contains `Salt,`
(i.e. nearly all of them) can mint a sodium figure out of a price, a
year, a percentage, or a street number.

**What shipped, exactly.** `LabelParser.parse(_:prose:)` with the three
rules above; the line→observation mapping moved out of
`SharedPageReader` into `PageText.observations(from:)` so the fixtures
parse the runs the app parses (the `LabelScan`/`dump-label-ocr` rule);
`SharedPageReader.singleFood(fromPageText:)` passes `prose: true`; five
tests in `PageReadTests` on committed page-text fixtures — three real
pages (both Salt & Straw, a recipe page that must stay empty) and two
prose panels that must still read, including salt WITH a stated mass.
547 kit tests green, app + watch + extension build clean.

**Known gap, deliberately left for Layer 2.** `singleFood(from pages:)`
— the RENDERED-document path, tried before the text path — still parses
in panel mode, because a shared PDF with no readable table may still be
a real panel whose units live in a header. A rendered web page reaching
that path with both a calorie figure and a `Salt` line could mint the
same kind of value from real geometry. It was not the route this
incident took (the galette's calories are inside a collapsed accordion,
so the render yields no kcal and the path returns nil), and it is not
verified either way. The plausibility gate is the honest fix for it;
narrowing prose mode by guessing at the document's shape is not.

### Layer 2 — one plausibility gate, on every path

A new pure kit type — `NutritionPlausibility` — with one entry point that
takes a `ParsedLabel` (or the fields directly) and returns per-field
verdicts. Two severities, because they earn different behavior:

**Impossible → drop the FIELD, keep the rest, log why.** The reading is
not thrown away: 300 kcal was right on the galette and the user still
wants it.

- kcal outside `0…5,000` per serving (the existing model bound, applied
  to the deterministic path for the first time)
- sodium outside `0…20,000` mg
- any gram field exceeding `servingGrams` when known — a 200 g serving
  cannot contain 300 g of carbohydrate
- sodium mass exceeding 40% of serving mass when known (pure NaCl is
  39.3% sodium — nothing edible can beat it)
- sodium above **250 mg/kcal** when serving mass is unknown. Calibrated
  ABOVE the worst real foods, deliberately: a bouillon cube is ~200
  mg/kcal, soy sauce ~90, a dill pickle ~60. The galette read is 2,701
  mg/kcal and is caught by a factor of ten.

**Suspicious → keep the value, flag it in the UI, never silently drop.**

- Atwater disagreement: `4(carbs − fiber) + 9 fat + 4 protein + 2 fiber`
  vs stated kcal, beyond `max(50 kcal, 30%)`. The tolerance is generous
  on purpose — alcohol is 7 kcal/g and is not a tracked field (there is a
  margarita in the same day's log), and sugar alcohols break it honestly.
- `sugar > carbs`, `saturated > fat`, `trans > fat`, `fiber > carbs`
- sodium above 3,000 mg in a single serving — legal (ramen, a whole
  pizza), rare enough to say so

Call sites, all of which currently roll their own bounds or none:
`SharedPageReader`, `FoodImageReader`, `MenuTableParser` rows,
`plausibleScreenshotFoods`, `plausibleSignFoods`, `parseIdentified`,
`describeFood`/`describeFoodRemote`, `describeMeal`, and the
OpenFoodFacts/FDC prefill — that last one matters more than it looks,
since OFF is contributor-entered and a per-100g figure in a per-serving
slot is a known class of bad row.

The existing ad-hoc ceilings get REPLACED by calls to it rather than left
beside it, for the reason `FoodIntelligenceRemote` already states about
its shared helpers: "guards and merges are the shared helpers, so the
engines can't drift."

### Layer 3 — never log a number the user has not seen

- `ShareLogSheet` shows every value it is about to write, not just kcal.
  It is a full HealthKit write behind one Log button; the sheet should
  read like the receipt for it.
- A field the gate called suspicious carries a warning marker in that
  sheet and in `FoodFormView`. Impossible ones arrive blank already.
- Neither blocks saving. The app's standing position is that the user
  can be right and the parser can be wrong; the flag says "look at
  this", not "you may not".

### Layer 4 — the estimates themselves

The estimate paths are, on the evidence, in better shape than the reader
— which is worth saying plainly, because the report that started this
was about estimation. Both ✨ rows in the same day's log (844 kcal /
1,875 mg for birria quesotacos, 140 kcal / 55 mg for a waffle cone) are
defensible numbers. The design already separates reading from
estimating, already refuses to estimate macros for menu dishes on
measured grounds, and already grounds sign reads in the photographed
text. Changes worth making, in order of value:

1. **Apply the Atwater check to estimates too, and drop macros that
   contradict the model's own calorie figure.** This is the `MenuDish`
   lesson generalized: macros implying ~290 kcal beside a stated 1,000
   were measured there, consistently, 65–71% adrift. That decision
   removed macros from one path; the check would enforce it everywhere
   and cost nothing at runtime.
2. **Sodium is the known-weakest estimate in the app, and it is already
   written down.** `Gate.sodiumInRange` sits at 0.75 where every sibling
   gate is 0.8+, with the note that the misses are "model-knowledge
   errors (cola 300 mg, Big Mac 2500 mg — consistent overestimates)".
   Options, in the open questions below: keep and mark it, widen the
   golden set and re-aim, or stop writing estimated sodium at all.
3. **Prefer published data over an estimate when the name matches.** An
   estimate is a floor, not a goal — when a described or identified food
   matches an OpenFoodFacts/FDC product closely, offering those numbers
   beats improving the guess. Accuracy comes from data.
4. **Grow the eval golden set** with the sodium cases specifically, and
   re-run per the CLAUDE.md rule (any prompt change, any OS model
   update). Thresholds move only in a commit that says why.

## What must NOT change

- **EU panels need bare numbers.** The unit lives in the column header.
  Verified by two failing tests when the rule was applied unconditionally.
- **Calories keep the bare-number convention.** `Calories per serving:
  300` is exactly the case the shared-page reader exists for.
- **Read ≠ estimate, and ✨ still means estimate.** This incident is an
  argument for a SECOND mark ("this looks wrong"), not for marking reads
  as guesses. A read is more trustworthy than an estimate; it just is
  not unconditionally trustworthy.
- **No per-site HTML parsing.** The `PLAN-screenshot-nutrition` veto
  holds. Everything above is site-agnostic — no selectors, nothing to rot.
- **Don't loosen the menu parser's gates to compensate.**
  `PLAN-menu-import` Round 6 already established the rule this whole
  incident re-teaches: *a parse that goes wrong must return NOTHING.*

## Tests

- **Prose fixtures.** Commit the STRIPPED TEXT of the two Salt & Straw
  pages (a few KB each, no HTML) plus a recipe page, a nutrition
  calculator page, and one page that really does state a full panel in
  prose. Assert exact `ParsedLabel`s, including the nils. The galette
  case asserts `sodiumMg == nil` — the regression test that would have
  caught this on the day it shipped.
- **`NutritionPlausibility` unit tests** on the boundary cases, with the
  real-food calibration points named in the test (bouillon, soy sauce,
  pickle) so the next person to raise a ceiling has to argue with them.
- The existing 543 must stay green; the EU salt tests are the tripwire.
- The AI eval suite re-runs only if Layer 4 touches a prompt.

## Cleanup on the device

The bad entry is in HealthKit now, and it is a sample the app wrote — the
day's sodium total is wrong until it is deleted, and if the food was
saved to the library the row carries 810,400 mg into every future log of
it. Both need checking: the log entry (Today → the row → delete) and
Foods → Peaches and Cream Galette.

## Decisions (2026-08-17, with the user)

1. **An impossible value drops the FIELD, not the reading** — the
   galette's 300 kcal was right and survives; the sodium blanks and the
   reason is logged. **[decided]**
2. **Estimated sodium keeps being written.** It is half of what the app
   tracks, so removing it guts the feature; the answer is a wider eval
   golden set and a gate re-aimed deliberately, in a commit that says
   why. **[decided]**
3. **`ShareLogSheet` shows every value it is about to write.** One Log
   button performs a full HealthKit write, so the sheet reads as the
   receipt for it. **[decided]**
4. **Layer 1 ships first, alone.** **[decided]** — done, above.

## Landmine, for CLAUDE.md when this ships

> **A nutrition keyword in PROSE is not a nutrition row.** `LabelParser`
> is panel geometry; `SharedPageReader` feeds it a web page with
> fabricated coordinates, so every safeguard in it is inert and every
> number on the page is a candidate. A copyright year became 810,400 mg
> of sodium (`2026 × 0.4 × 1000` — the salt→sodium conversion) and a
> `$15` price became 6,000 mg, both 2026-08-16, both logged silently
> because the share sheet's Log button shows only calories. Prose mode
> requires an explicit unit and disables the wrapped-name carry-forward.
> Do NOT make the unit requirement unconditional: EU panels print it in
> the column header once, and two tests will tell you so.
