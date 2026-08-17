import XCTest
import OnigiriKit
@testable import Onigiri

/// Golden-set regression evals for the four FoodIntelligence affordances
/// (describe-it, meal names, label refinement, identify-food). The on-device model
/// changes underneath the app on every OS update with no code change on
/// our side — this suite is what notices.
///
/// Discipline (hand-rolled: the Evaluations framework is iOS 27+, this
/// project builds with Xcode 26):
/// - Every sample calls the REAL shipped entry points, not a copy of
///   their prompts.
/// - "Produced" is a guardrail at 100%: the entry points return nil on
///   any model failure, and for these benign inputs a refusal is a
///   regression, never a skipped sample. Range checks are tolerant
///   plausibility bounds, not point answers — the model samples
///   nondeterministically (the shipped code uses default options, and
///   we evaluate what ships).
/// - Thresholds are named up front in `Gate` — set BEFORE tuning,
///   adjust only deliberately, in a commit that says why.
/// - Model unavailable ⇒ SKIP, never a green pass: an absent model is
///   not a quality result.
///
/// Run (evals are slow — a couple of minutes of on-device inference —
/// so they're opt-in; without the flag every test skips):
///   TEST_RUNNER_ONIGIRI_AI_EVALS=1 xcodebuild test -project Onigiri.xcodeproj \
///     -scheme Onigiri -destination '<simulator>' -only-testing:OnigiriTests
/// The simulator runs the host Mac's model: Apple Intelligence must be
/// enabled on this Mac or the suite skips.
final class FoodIntelligenceEvals: XCTestCase {

    /// Pass-rate floors, decided before the first tuning pass.
    /// `produced` and format invariants the prompt explicitly demands
    /// are guardrails (1.0); estimate plausibility gets headroom for
    /// sampling variance.
    private enum Gate {
        static let produced = 1.0
        static let kcalInRange = 0.8
        /// Re-aimed 0.75 → 0.8 on 2026-08-17, on the trigger the old
        /// comment named: the golden set grew (13 → 20 samples, seven of
        /// them sodium calibration). Measured that day, greedy, iOS 26.5
        /// sim: **16/19 = 0.842**. The three misses are the two
        /// long-standing model-knowledge errors (Big Mac 2,400 mg where
        /// ~1,010 is published, cola 300 mg where ~40 is) plus one in the
        /// other direction — American cheese at 100 mg, which is UNDER.
        /// So "the model over-estimates sodium" is not the whole story,
        /// and the five deliberately low-sodium additions (blueberries,
        /// black coffee, almonds, potato, milk) all landed.
        ///
        /// Headroom is one sample: a fourth miss reads 0.789 and fails.
        /// That is the point of a floor, but it means an OS model update
        /// needs a re-baseline rather than a shrug.
        static let sodiumInRange = 0.8
        static let nameFormat = 0.8
        static let mealNameFormat = 1.0
        static let labelFill = 0.8
        static let identifyComponents = 0.8
        /// Describe-a-meal's component evidence, at identify-food's floor
        /// (0.8). The 2026-07-29 baseline is 5/6: "miso soup with rice and
        /// grilled salmon" came back as two parts — it dropped the rice —
        /// while every other sample named and portioned every part it was
        /// given. A merge or omission is the failure that matters for this
        /// feature (each part is meant to become its own editable food),
        /// so this floor means "never worse than today".
        static let mealComponents = 0.8
        /// Sign read (2026-08-02), both set BEFORE the first run.
        /// The NAME is a guardrail at 1.0: the sign states it in words,
        /// so unlike every estimate in this file there is a right answer
        /// printed in the input — and `plausibleSignFoods` already
        /// rejects a name that appears nowhere in the text, so a miss
        /// here means the read is coming back empty or naming the brand.
        static let signName = 1.0
        /// Item count gets estimate-style headroom: telling "one item
        /// with an ingredient list" from "a menu listing two" is a
        /// judgment, and the ingredient run is the known trap.
        static let signItemCount = 0.75
    }

    @MainActor
    private func requireEvalRun() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["ONIGIRI_AI_EVALS"] == "1",
            "AI evals are opt-in: pass TEST_RUNNER_ONIGIRI_AI_EVALS=1 (minutes of model inference)"
        )
        // AI ships OFF by default (2026-07-20); the suite runs in the
        // app's process, so flip the master switch for the eval run —
        // an opted-in eval must never silently skip on the default.
        SharedStore.defaults.set(true, forKey: AIProviderSettings.enabledKey)
        // Pin the engine under test: every Gate/knownRefusals threshold
        // in this file is calibrated against the ON-DEVICE model, and
        // the provider picker persists in the real App Group defaults —
        // a sim last used for BYO-AI QA would otherwise silently eval
        // the wrong engine (and spend real API budget doing it).
        SharedStore.defaults.set(AIProvider.onDevice.rawValue, forKey: AIProviderSettings.providerKey)
        XCTAssertEqual(
            AIProviderSettings.selected, .onDevice,
            "eval run must exercise the on-device model — provider pin failed"
        )
        try XCTSkipUnless(
            FoodIntelligence.isAvailable,
            "Foundation Models unavailable (Apple Intelligence off or unsupported here) — skipping; an absent model must never report a quality result"
        )
    }

    // MARK: Describe-it ("half cup cooked white rice and a fried egg")

    private struct DescribeSample {
        let description: String
        let kcal: ClosedRange<Double>
        let sodiumMg: ClosedRange<Double>
    }

    /// Plausibility bounds are deliberately wide — commonsense sanity,
    /// not nutrition-table precision. The sodium-heavy items (soy sauce,
    /// pickle, miso) are the load-bearing samples: this is a sodium
    /// tracker, and "soy sauce is salty" is the floor of usefulness.
    private static let describeGolden: [DescribeSample] = [
        .init(description: "two large scrambled eggs", kcal: 120...400, sodiumMg: 60...1000),
        .init(description: "a cup of cooked white rice", kcal: 130...350, sodiumMg: 0...600),
        .init(description: "a medium banana", kcal: 60...160, sodiumMg: 0...30),
        .init(description: "a Big Mac", kcal: 400...800, sodiumMg: 600...1600),
        .init(description: "a tablespoon of soy sauce", kcal: 0...60, sodiumMg: 400...1400),
        .init(description: "a large dill pickle", kcal: 0...60, sodiumMg: 300...2000),
        .init(description: "6 oz grilled chicken breast", kcal: 150...450, sodiumMg: 0...600),
        .init(description: "a 12 oz can of regular cola", kcal: 90...200, sodiumMg: 0...120),
        .init(description: "half cup cooked white rice and a fried egg", kcal: 150...450, sodiumMg: 30...800),
        .init(description: "a bowl of miso soup", kcal: 20...180, sodiumMg: 300...1800),
        // Spoken grammar (the Siri describe-to-log path): first-person,
        // conversational — phrasing users SAY differs from what they type.
        .init(description: "I had two slices of pepperoni pizza", kcal: 350...900, sodiumMg: 400...2000),
        .init(description: "I ate a bowl of oatmeal with honey", kcal: 120...500, sodiumMg: 0...400),
        .init(description: "I drank a large iced latte with whole milk", kcal: 80...400, sodiumMg: 30...350),
        // SODIUM CALIBRATION (2026-08-17, Layer 4 of
        // PLAN-nutrition-plausibility). The measured failure on this set
        // was never "it doesn't know salty" — soy sauce and miso have
        // always landed — it was consistent OVER-estimation on things
        // that carry almost none (cola 300 mg, Big Mac 2,500). So the
        // additions are weighted toward foods whose right answer is a
        // SMALL number, which is the half the set could not see.
        .init(description: "a cup of fresh blueberries", kcal: 50...130, sodiumMg: 0...25),
        .init(description: "a plain baked potato", kcal: 120...350, sodiumMg: 0...100),
        .init(description: "a cup of black coffee", kcal: 0...15, sodiumMg: 0...25),
        .init(description: "1 oz unsalted almonds", kcal: 130...220, sodiumMg: 0...30),
        .init(description: "an 8 oz glass of whole milk", kcal: 110...220, sodiumMg: 70...220),
        // …and the genuinely salty end, so tightening the gate later
        // cannot be done by simply predicting "low".
        .init(description: "a cup of instant ramen noodles", kcal: 250...550, sodiumMg: 700...2400),
        .init(description: "a slice of American cheese", kcal: 40...130, sodiumMg: 150...500),
    ]

    /// BASELINE, 2026-08-17 (greedy, iOS 26.5 sim, 20 samples): produced
    /// 20/20 with one known refusal, kcal 16/19, sodium 16/19, names
    /// 19/19. kcal misses are all UNDER — white rice 110, two pizza
    /// slices 250, instant ramen 150 — which is a different failure from
    /// sodium's and has no gate change behind it yet.
    ///
    /// `estimateMacros` (Layer 4) dropped exactly ONE sample's macros:
    /// "half cup cooked white rice and a fried egg", the only COMPOSED
    /// description in the set. 18/19 survived, which is the number that
    /// matters — a filter that took most of them would be a prompt
    /// problem wearing a filter's clothes.
    ///
    /// Known-failures register: inputs the OS guardrails refuse today
    /// through no fault of the prompt. "6 oz grilled chicken breast"
    /// trips the input safety classifier on "breast" (iOS 26.5,
    /// baselined 2026-07-16; the round-1 data-framing fix recovered
    /// "a Big Mac" but not this). Refusals ON this list don't fail the
    /// produced gate; refusals OFF it do. Re-check on every OS update —
    /// if it stops refusing, remove it so the register can't rot.
    private static let knownRefusals: Set<String> = [
        "6 oz grilled chicken breast",
    ]

    @MainActor
    func testDescribeFoodGoldenSet() async throws {
        try requireEvalRun()
        var produced = 0, answered = 0, kcalOK = 0, sodiumOK = 0, nameOK = 0
        // How often the model's macros SURVIVE `estimateMacros` — i.e.
        // account for the calorie figure the same answer stated. Logged,
        // not gated: the calibrate-then-gate rule, and this is the run
        // that produces the baseline to gate against.
        var macrosKept = 0
        var report: [String] = []

        for sample in Self.describeGolden {
            guard let food = await FoodIntelligence.describeFood(sample.description) else {
                if Self.knownRefusals.contains(sample.description) {
                    produced += 1  // pinned OS false positive, not a regression
                    report.append("KNOWN-REFUSAL  \(sample.description)")
                } else {
                    report.append("REFUSED  \(sample.description)")
                }
                continue
            }
            produced += 1
            answered += 1
            let kcalHit = sample.kcal.contains(food.kcal)
            let sodiumHit = sample.sodiumMg.contains(food.sodiumMg)
            // The @Guide asks for at most five words; allow drift to
            // eight before calling it a format regression.
            let nameHit = !food.name.isEmpty
                && food.name.split(separator: " ").count <= 8
            if kcalHit { kcalOK += 1 }
            if sodiumHit { sodiumOK += 1 }
            if nameHit { nameOK += 1 }
            report.append(
                "\(kcalHit && sodiumHit && nameHit ? "ok  " : "MISS") "
                + "\(sample.description) → \"\(food.name)\", "
                + "\(food.kcal) kcal (want \(sample.kcal)), "
                + "\(food.sodiumMg) mg Na (want \(sample.sodiumMg)), "
                + "serving \"\(food.serving)\"")
            // MACRO BASELINE (PLAN-unified-search): logged, not yet
            // gated — Gates get set from this data in their own commit
            // (the calibrate-then-gate rule). Blank = model omitted.
            let macros = food.nutrients
            if !macros.isEmpty { macrosKept += 1 }
            report.append(
                "     macros: fat \(macros.fatG.map { "\($0)g" } ?? "—"), "
                + "carbs \(macros.carbsG.map { "\($0)g" } ?? "—"), "
                + "protein \(macros.proteinG.map { "\($0)g" } ?? "—"), "
                + "fiber \(macros.fiberG.map { "\($0)g" } ?? "—"), "
                + "sugar \(macros.sugarG.map { "\($0)g" } ?? "—")"
                + (macros.isEmpty ? "  ← dropped or omitted" : ""))
        }
        report.append("""
            macros survived: \(macrosKept)/\(answered) \
            (estimateMacros keeps them only when 4·carbs + 9·fat + 4·protein \
            accounts for the stated kcal)
            """)

        attachAndPrint(report, name: "describeFood-eval")
        // Produced is the guardrail: a nil here is a refusal/failure on a
        // benign kitchen-table description, silently swallowed in-app
        // (knownRefusals excepted — those are pinned OS false positives).
        // Range metrics divide by ANSWERED so a known refusal can't
        // drag them; the guard keeps an all-refused run from passing
        // the range gates over an empty denominator.
        let n = Double(Self.describeGolden.count)
        XCTAssertGreaterThanOrEqual(Double(produced) / n, Gate.produced, "produced (refusals are failures)")
        guard answered > 0 else {
            XCTFail("no sample produced values — nothing was measured")
            return
        }
        let a = Double(answered)
        XCTAssertGreaterThanOrEqual(Double(kcalOK) / a, Gate.kcalInRange, "kcal plausibility")
        XCTAssertGreaterThanOrEqual(Double(sodiumOK) / a, Gate.sodiumInRange, "sodium plausibility")
        XCTAssertGreaterThanOrEqual(Double(nameOK) / a, Gate.nameFormat, "name format")
    }

    // MARK: Describe-a-meal ("chicken burrito bowl with rice, beans, guac")

    private struct DescribeMealSample {
        let description: String
        /// The whole meal's total, summed IN CODE from the components.
        let kcal: ClosedRange<Double>
        let sodiumMg: ClosedRange<Double>
        /// How many distinct foods the description NAMES. Merging two of
        /// them into one component is the failure that matters here: the
        /// point of components is that each becomes a separately editable,
        /// re-usable library food.
        let minComponents: Int
    }

    /// Multi-food descriptions, the shapes a meal actually gets described
    /// in — plus one in spoken grammar (the Siri lesson: what users SAY
    /// differs from what they type).
    private static let describeMealGolden: [DescribeMealSample] = [
        .init(description: "chicken burrito bowl with rice, beans, and guacamole",
              kcal: 400...1600, sodiumMg: 200...3000, minComponents: 4),
        .init(description: "two eggs, toast with butter, and a banana",
              kcal: 250...900, sodiumMg: 80...1500, minComponents: 3),
        .init(description: "a Big Mac, medium fries, and a Coke",
              kcal: 700...2000, sodiumMg: 600...2800, minComponents: 3),
        .init(description: "miso soup with rice and grilled salmon",
              kcal: 300...1100, sodiumMg: 300...2800, minComponents: 3),
        .init(description: "spaghetti with meat sauce and a side salad",
              kcal: 350...1300, sodiumMg: 250...2800, minComponents: 2),
        // Upper bound 3000, not the 2500 first written here: a deli
        // turkey sandwich alone runs ~1500 mg and salted chips add
        // several hundred, so 2500 was an arbitrary cut that called a
        // PLAUSIBLE 2505 a miss. These are plausibility bounds; a bound
        // tighter than reality measures the bound, not the model.
        .init(description: "I had a turkey sandwich with chips and an apple",
              kcal: 350...1200, sodiumMg: 300...3000, minComponents: 3),
    ]

    /// Calibrated against the 2026-07-29 on-device baseline (iOS 26.5
    /// sim, greedy): produced 6/6, kcal 6/6, sodium 5/6, parts 5/6,
    /// distinct 6/6, name 6/6.
    ///
    /// The two known misses, both model knowledge rather than prompt bugs:
    /// - "a Big Mac, medium fries, and a Coke" → 4100 mg sodium (real is
    ///   ~1300). The SAME salt overestimate already pinned for describe-it
    ///   (cola, Big Mac), which is why sodium rides the existing 0.75 gate.
    /// - "miso soup with rice and grilled salmon" → 2 parts; the rice
    ///   vanished. See Gate.mealComponents.
    ///
    /// One soft finding NOT gated: the model sometimes echoes the whole
    /// description as the meal name ("Spaghetti with meat sauce and a side
    /// salad" — 8 words against a five-word @Guide). It lands in an
    /// editable field the user reviews, so it's a wart, not a defect;
    /// worth prompt work only if it recurs after an OS model update.
    @MainActor
    func testDescribeMealGoldenSet() async throws {
        try requireEvalRun()
        var produced = 0, kcalOK = 0, sodiumOK = 0, partsOK = 0, distinctOK = 0, nameOK = 0
        var report: [String] = []

        for sample in Self.describeMealGolden {
            guard let meal = await FoodIntelligence.describeMeal(sample.description) else {
                report.append("REFUSED  \(sample.description)")
                continue
            }
            produced += 1
            let kcalHit = sample.kcal.contains(meal.kcal)
            let sodiumHit = sample.sodiumMg.contains(meal.sodiumMg)
            // Every component named AND portioned, within the 1...6 the
            // @Guide asks for, and at least as many as the description
            // names (the identify-food component-evidence precedent).
            let partsHit = (sample.minComponents...6).contains(meal.components.count)
                && meal.components.allSatisfy { !$0.name.isEmpty && !$0.portion.isEmpty }
            // The shared gate collapses repeats; if a duplicate still
            // shows here, the gate stopped holding.
            let distinctHit = Set(meal.components.map { ComponentMatch.normalized($0.name) }).count
                == meal.components.count
            let nameHit = !meal.name.isEmpty
                && meal.name.split(separator: " ").count <= 8
                && !meal.name.contains("\"")
            if kcalHit { kcalOK += 1 }
            if sodiumHit { sodiumOK += 1 }
            if partsHit { partsOK += 1 }
            if distinctHit { distinctOK += 1 }
            if nameHit { nameOK += 1 }
            report.append(
                "\(kcalHit && sodiumHit && partsHit && distinctHit && nameHit ? "ok  " : "MISS") "
                + "\(sample.description) → \"\(meal.name)\" "
                + "(\(meal.components.count) parts, want ≥\(sample.minComponents)): "
                + "\(meal.kcal) kcal (want \(sample.kcal)), "
                + "\(meal.sodiumMg) mg Na (want \(sample.sodiumMg))")
            for component in meal.components {
                let macros = component.nutrients
                report.append(
                    "     • \(component.name) (\(component.portion)): "
                    + "\(component.kcal) kcal, \(component.sodiumMg) mg Na, "
                    + "fat \(macros.fatG.map { "\($0)g" } ?? "—"), "
                    + "carbs \(macros.carbsG.map { "\($0)g" } ?? "—"), "
                    + "protein \(macros.proteinG.map { "\($0)g" } ?? "—"), "
                    + "fiber \(macros.fiberG.map { "\($0)g" } ?? "—"), "
                    + "sugar \(macros.sugarG.map { "\($0)g" } ?? "—")")
            }
        }

        attachAndPrint(report, name: "describeMeal-eval")
        let n = Double(Self.describeMealGolden.count)
        // Same guardrail as describe-it: a nil on a benign kitchen-table
        // description is a refusal the app swallows silently.
        XCTAssertGreaterThanOrEqual(Double(produced) / n, Gate.produced, "produced (refusals are failures)")
        guard produced > 0 else {
            XCTFail("no sample produced values — nothing was measured")
            return
        }
        let a = Double(produced)
        XCTAssertGreaterThanOrEqual(Double(kcalOK) / a, Gate.kcalInRange, "meal kcal plausibility")
        XCTAssertGreaterThanOrEqual(Double(sodiumOK) / a, Gate.sodiumInRange, "meal sodium plausibility")
        XCTAssertGreaterThanOrEqual(Double(partsOK) / a, Gate.mealComponents, "component evidence")
        XCTAssertGreaterThanOrEqual(Double(nameOK) / a, Gate.nameFormat, "meal name format")
        // Guardrail, not a rate: duplicate components are collapsed IN
        // CODE by plausibleMealComponents, so one surviving here means the
        // gate stopped working — and two library foods with the same name
        // is exactly what the matching pass exists to prevent.
        XCTAssertEqual(distinctOK, produced, "components must be distinct after the shared gate")
    }

    // MARK: Meal-name suggestion

    private static let mealNameGolden: [[String]] = [
        ["chicken breast", "white rice", "steamed broccoli"],
        ["spaghetti", "marinara sauce", "parmesan"],
        ["greek yogurt", "granola", "blueberries"],
        ["black coffee"],
        ["tofu", "soba noodles", "edamame", "seaweed salad"],
    ]

    @MainActor
    func testSuggestMealNameGoldenSet() async throws {
        try requireEvalRun()
        var produced = 0, formatOK = 0
        var report: [String] = []

        for foods in Self.mealNameGolden {
            guard let name = await FoodIntelligence.suggestMealName(for: foods) else {
                report.append("REFUSED  \(foods.joined(separator: ", "))")
                continue
            }
            produced += 1
            // The prompt demands: short, no quotes, no emoji. Those are
            // code-checkable, so they're guardrails, not judge work.
            let quoteFree = !name.contains("\"") && !name.contains("\u{201C}") && !name.contains("\u{201D}")
            let emojiFree = !name.unicodeScalars.contains {
                $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value >= 0x1F000)
            }
            // "At most four words" asked; six before it's a regression.
            let short = name.split(separator: " ").count <= 6
            let hit = quoteFree && emojiFree && short
            if hit { formatOK += 1 }
            report.append("\(hit ? "ok  " : "MISS") \(foods.joined(separator: ", ")) → \"\(name)\"")
        }

        attachAndPrint(report, name: "suggestMealName-eval")
        let n = Double(Self.mealNameGolden.count)
        XCTAssertGreaterThanOrEqual(Double(produced) / n, Gate.produced, "produced (refusals are failures)")
        XCTAssertGreaterThanOrEqual(Double(formatOK) / n, Gate.mealNameFormat, "name format (prompt's own contract)")
    }

    // MARK: Label refinement

    /// Synthetic transcripts stand in for OCR output (real fixtures come
    /// from scripts/dump-label-ocr.swift; these test the model's reading,
    /// not Vision's). Boxes are placeholder geometry — refine() only
    /// joins the text.
    private static func transcript(_ lines: [String]) -> [LabelObservation] {
        lines.enumerated().map { i, line in
            LabelObservation(text: line, x: 0.1, y: 0.9 - Double(i) * 0.05, w: 0.8, h: 0.04)
        }
    }

    @MainActor
    func testRefineFillsBlanksExactlyAsPrinted() async throws {
        try requireEvalRun()
        // A classic US panel; the deterministic parse got kcal and
        // nothing else. The model must fill the blanks with the printed
        // numbers and must NOT touch the kcal it didn't fill (structural
        // — fill() only writes nils — but this exercises the whole path).
        var parsed = ParsedLabel()
        parsed.kcal = 230
        let lines = Self.transcript([
            "Nutrition Facts", "Serving Size 2/3 cup (55g)", "Calories 230",
            "Total Fat 8g", "Sodium 160mg", "Total Carbohydrate 37g",
            "Dietary Fiber 4g", "Total Sugars 12g", "Protein 3g",
        ])

        let merged = await FoodIntelligence.refine(parsed, transcript: lines)

        var filled = 0
        let expectations: [(String, Double?, Double)] = [
            ("sodiumMg", merged.sodiumMg, 160),
            ("fatG", merged.nutrients.fatG, 8),
            ("carbsG", merged.nutrients.carbsG, 37),
            ("proteinG", merged.nutrients.proteinG, 3),
            ("fiberG", merged.nutrients.fiberG, 4),
            ("sugarG", merged.nutrients.sugarG, 12),
        ]
        var report: [String] = []
        for (field, got, want) in expectations {
            let hit = got.map { abs($0 - want) < 0.5 } ?? false
            if hit { filled += 1 }
            report.append("\(hit ? "ok  " : "MISS") \(field): \(got.map(String.init(describing:)) ?? "nil") (want \(want))")
        }
        attachAndPrint(report, name: "refine-fill-eval")

        // Deterministic values always win — a changed kcal is a merge bug,
        // not a model quality miss. Hard assert.
        XCTAssertEqual(merged.kcal, 230, "refine must never overwrite a deterministic value")
        XCTAssertGreaterThanOrEqual(
            Double(filled) / Double(expectations.count), Gate.labelFill,
            "printed values read back")
    }

    @MainActor
    func testRefineNeverInventsMissingFields() async throws {
        try requireEvalRun()
        // A minimal label that shows only calories and fat. "Never
        // estimate or invent" is the prompt's core safety property: a
        // sodium value hallucinated onto a form in a SODIUM TRACKER is
        // the worst failure this feature has.
        let lines = Self.transcript(["Nutrition Facts", "Calories 100", "Total Fat 0g"])

        let merged = await FoodIntelligence.refine(ParsedLabel(), transcript: lines)

        attachAndPrint(
            ["kcal \(String(describing: merged.kcal)), fat \(String(describing: merged.nutrients.fatG)), "
             + "sodium \(String(describing: merged.sodiumMg)), protein \(String(describing: merged.nutrients.proteinG)), "
             + "carbs \(String(describing: merged.nutrients.carbsG))"],
            name: "refine-invent-eval")

        // Reads what's printed…
        XCTAssertEqual(merged.kcal.map { abs($0 - 100) < 0.5 }, true, "printed kcal should be read")
        // …and nothing else. Guardrails: absent fields stay nil.
        XCTAssertNil(merged.sodiumMg, "sodium not on the label — must stay blank, never invented")
        XCTAssertNil(merged.nutrients.proteinG, "protein not on the label — must stay blank")
        XCTAssertNil(merged.nutrients.carbsG, "carbs not on the label — must stay blank")
    }

    @MainActor
    func testRefineConvertsPer100gBasisAndIgnoresSalt() async throws {
        try requireEvalRun()
        // A European per-100g panel already scaled by the deterministic
        // parser (55 g serving ⇒ factor 0.55). Filled blanks must land
        // on the serving basis, and "Salt" alone must NOT become sodium
        // (the prompt: null when the label shows only salt).
        var parsed = ParsedLabel()
        parsed.per100gScaleFactor = 0.55
        parsed.servingGrams = 55
        let lines = Self.transcript([
            "Nutrition Information", "Per 100 g",
            "Energy 418 kcal", "Fat 14.5 g", "Salt 1.2 g",
        ])

        let merged = await FoodIntelligence.refine(parsed, transcript: lines)

        attachAndPrint(
            ["kcal \(String(describing: merged.kcal)) (want ~230), "
             + "fat \(String(describing: merged.nutrients.fatG)) (want ~8), "
             + "sodium \(String(describing: merged.sodiumMg)) (want nil)"],
            name: "refine-per100g-eval")

        if let kcal = merged.kcal {
            XCTAssertEqual(kcal, 418 * 0.55, accuracy: 12, "per-100g kcal must scale to the serving")
        } else {
            XCTFail("kcal printed on the label should be read")
        }
        if let fat = merged.nutrients.fatG {
            XCTAssertEqual(fat, 14.5 * 0.55, accuracy: 1, "per-100g fat must scale to the serving")
        }
        XCTAssertNil(merged.sodiumMg, "salt-only label must not fill sodium")
    }

    // MARK: Identify Food (classifier labels → components → one food)

    private struct IdentifySample {
        let labels: [String]
        let kcal: ClosedRange<Double>
        let sodiumMg: ClosedRange<Double>
    }

    /// The subject is the text-relay half (identifyFood(from:)) — the
    /// Vision half is deterministic and kit-tested. Labels mimic what
    /// ClassifyImageRequest actually emits: lowercase, generic, with
    /// context noise like "plate" and "bowl" the model must see past.
    private static let identifyGolden: [IdentifySample] = [
        .init(labels: ["salad", "vegetable", "plate", "lettuce"], kcal: 50...600, sodiumMg: 0...900),
        .init(labels: ["pizza", "food"], kcal: 200...1200, sodiumMg: 300...2500),
        .init(labels: ["soup", "bowl", "noodles"], kcal: 100...800, sodiumMg: 300...3000),
        .init(labels: ["sushi", "rice", "fish"], kcal: 150...900, sodiumMg: 100...2000),
        .init(labels: ["hamburger", "french fries", "plate"], kcal: 500...1600, sodiumMg: 400...2500),
    ]

    /// Not-food shortlists must come back nil — a food invented from a
    /// photo of a laptop is the feature's most embarrassing failure.
    private static let identifyNotFood: [[String]] = [
        ["laptop", "keyboard", "desk"],
        ["dog", "grass", "outdoor"],
        ["document", "text", "paper"],
    ]

    @MainActor
    func testIdentifyFoodGoldenSet() async throws {
        try requireEvalRun()
        var produced = 0, kcalOK = 0, sodiumOK = 0, componentsOK = 0
        var report: [String] = []

        for sample in Self.identifyGolden {
            let guesses = sample.labels.enumerated().map {
                FoodGuess(label: $1, confidence: 1.0 - Double($0) * 0.1)
            }
            guard let food = await FoodIntelligence.identifyFood(from: guesses) else {
                report.append("REFUSED  \(sample.labels.joined(separator: ", "))")
                continue
            }
            produced += 1
            let kcalHit = sample.kcal.contains(food.kcal)
            let sodiumHit = sample.sodiumMg.contains(food.sodiumMg)
            // 1-6 typical components, every one named and portioned —
            // the components ARE the user-facing evidence.
            let componentsHit = (1...6).contains(food.components.count)
                && food.components.allSatisfy { !$0.name.isEmpty && !$0.portion.isEmpty }
            if kcalHit { kcalOK += 1 }
            if sodiumHit { sodiumOK += 1 }
            if componentsHit { componentsOK += 1 }
            report.append(
                "\(kcalHit && sodiumHit && componentsHit ? "ok  " : "MISS") "
                + "[\(sample.labels.joined(separator: ", "))] → \"\(food.name)\": "
                + food.components.map { "\($0.name) (\($0.portion), \($0.kcal) kcal, \($0.sodiumMg) mg)" }
                    .joined(separator: " + ")
                + " = \(food.kcal) kcal (want \(sample.kcal)), \(food.sodiumMg) mg Na (want \(sample.sodiumMg))")
        }

        attachAndPrint(report, name: "identifyFood-eval")
        let n = Double(Self.identifyGolden.count)
        XCTAssertGreaterThanOrEqual(Double(produced) / n, Gate.produced, "produced (refusals are failures)")
        guard produced > 0 else {
            XCTFail("no sample produced values — nothing was measured")
            return
        }
        let a = Double(produced)
        XCTAssertGreaterThanOrEqual(Double(kcalOK) / a, Gate.kcalInRange, "kcal plausibility")
        XCTAssertGreaterThanOrEqual(Double(sodiumOK) / a, Gate.sodiumInRange, "sodium plausibility")
        XCTAssertGreaterThanOrEqual(Double(componentsOK) / a, Gate.identifyComponents, "component evidence")
    }

    @MainActor
    func testIdentifyFoodRejectsNotFood() async throws {
        try requireEvalRun()
        var report: [String] = []
        var invented = 0

        for labels in Self.identifyNotFood {
            let guesses = labels.enumerated().map {
                FoodGuess(label: $1, confidence: 1.0 - Double($0) * 0.1)
            }
            if let food = await FoodIntelligence.identifyFood(from: guesses) {
                invented += 1
                report.append("INVENTED [\(labels.joined(separator: ", "))] → \"\(food.name)\", \(food.kcal) kcal")
            } else {
                report.append("ok   [\(labels.joined(separator: ", "))] → nil")
            }
        }

        attachAndPrint(report, name: "identifyFood-notfood-eval")
        // Guardrail at 100%: inventing food from a not-food photo is the
        // failure mode this feature must never ship.
        XCTAssertEqual(invented, 0, "not-food label sets must return nil")
    }

    // MARK: Sign / menu / package-front read (photographed text → estimate)

    private struct SignSample {
        let what: String
        let lines: [String]
        /// A word the name must contain, lowercased — grounding, not a
        /// point answer. The sign SAYS what it is; getting that wrong is
        /// a different failure from estimating it badly.
        let nameContains: [String]
        let kcal: ClosedRange<Double>
        /// How many separately-named items the text advertises. The
        /// load-bearing check: an ingredient run under a name must not
        /// come back as five foods.
        let count: Int
    }

    /// The first two are the REAL transcripts that reported this
    /// (2026-08-02), through the app's own OCR — including its mistakes
    /// ("Mitk", "250z"), because the model has to read what Vision
    /// actually emits, not a cleaned-up version of it.
    private static let signGolden: [SignSample] = [
        .init(
            what: "bakery card, green onion bread",
            lines: [
                "$2.25", "青蔥麵包", "GREEN ONION",
                "Flour/Sugar/Salt/Egg/Mitk/",
                "Butter/Yeast/Soybean Oil/Green Onion",
                "Net WT 250z",
                "Allergen Warning! Contains:Wheat. Dairy, Soybean Oil",
            ],
            nameContains: ["onion"], kcal: 100...600, count: 1),
        .init(
            what: "bakery case, ham & cheese bagel",
            lines: [
                "SUNMERRY", "家聖瑪莉", "SUNMERRY", "◎聖瑪莉",
                "日式火熊起士色給具果", "$3.50", "小麥粉",
                "HAM & CHEESE", "FILLING BAGEL", "SUNMERRY",
            ],
            nameContains: ["bagel", "ham", "cheese"], kcal: 150...800, count: 1),
        .init(
            what: "package front",
            lines: ["KIND", "DARK CHOCOLATE", "NUTS & SEA SALT", "Net Wt 1.4 oz (40g)"],
            nameContains: ["chocolate", "nut", "kind"], kcal: 100...350, count: 1),
        .init(
            what: "menu board, two items",
            lines: [
                "TODAY'S SPECIALS",
                "Chicken Caesar Wrap ....... $9.50",
                "Tomato Basil Soup ....... $5.00",
            ],
            nameContains: ["wrap", "soup", "chicken", "tomato"], kcal: 100...900, count: 2),
    ]

    /// Text with no food in it must return NOTHING. The sign read is the
    /// step that runs on every failed label scan, so a model that
    /// invents a pastry out of a parking sign would fire constantly.
    private static let signNotFood: [[String]] = [
        ["NO PARKING", "TOW AWAY ZONE", "24 HOURS"],
        ["Gate B14", "Boarding 7:45 PM", "Seat 22A"],
    ]

    @MainActor
    func testReadFoodSignGoldenSet() async throws {
        try requireEvalRun()
        var produced = 0, kcalOK = 0, nameOK = 0, countOK = 0
        var report: [String] = []

        for sample in Self.signGolden {
            let foods = await FoodIntelligence.readFoodSign(
                transcript: Self.transcript(sample.lines))
            guard let first = foods.first else {
                report.append("REFUSED  \(sample.what)")
                continue
            }
            produced += 1
            let kcalHit = foods.allSatisfy { sample.kcal.contains($0.kcal) }
            let lowered = foods.map { $0.name.lowercased() }.joined(separator: " ")
            let nameHit = sample.nameContains.contains { lowered.contains($0) }
            let countHit = foods.count == sample.count
            if kcalHit { kcalOK += 1 }
            if nameHit { nameOK += 1 }
            if countHit { countOK += 1 }
            report.append(
                "\(kcalHit && nameHit && countHit ? "ok  " : "MISS") \(sample.what) → "
                + foods.map { "\"\($0.name)\" (\($0.serving)) \($0.kcal) kcal, \($0.sodiumMg) mg" }
                    .joined(separator: " | ")
                + "  [want \(sample.count) item(s), kcal \(sample.kcal), name ~ \(sample.nameContains)]"
                + (foods.count == 1 ? "" : "  first=\(first.name)"))
        }

        attachAndPrint(report, name: "readFoodSign-eval")
        let n = Double(Self.signGolden.count)
        XCTAssertGreaterThanOrEqual(Double(produced) / n, Gate.produced, "produced (refusals are failures)")
        guard produced > 0 else {
            XCTFail("no sample produced values — nothing was measured")
            return
        }
        let a = Double(produced)
        XCTAssertGreaterThanOrEqual(Double(nameOK) / a, Gate.signName, "name grounded in the sign's own words")
        XCTAssertGreaterThanOrEqual(Double(kcalOK) / a, Gate.kcalInRange, "kcal plausibility")
        XCTAssertGreaterThanOrEqual(Double(countOK) / a, Gate.signItemCount, "one item per named item")
    }

    @MainActor
    func testReadFoodSignRejectsTextWithNoFood() async throws {
        try requireEvalRun()
        var report: [String] = []
        var invented = 0

        for lines in Self.signNotFood {
            let foods = await FoodIntelligence.readFoodSign(transcript: Self.transcript(lines))
            if foods.isEmpty {
                report.append("ok   [\(lines.joined(separator: " / "))] → none")
            } else {
                invented += 1
                report.append("INVENTED [\(lines.joined(separator: " / "))] → "
                    + foods.map { "\"\($0.name)\" \($0.kcal) kcal" }.joined(separator: ", "))
            }
        }

        attachAndPrint(report, name: "readFoodSign-notfood-eval")
        XCTAssertEqual(invented, 0, "text naming no food must return no foods")
    }

    // The sign read sees only the text — geometry belongs to SignText
    // (kit, deterministically tested against the real boxes) — so these
    // reuse the refine section's placeholder-geometry `transcript`.

    // MARK: Plumbing

    /// The per-sample table is the point of an eval run — the pass rate
    /// says whether it regressed, the table says HOW. Attached to the
    /// xcresult and echoed to the console.
    @MainActor
    private func attachAndPrint(_ lines: [String], name: String) {
        let text = lines.joined(separator: "\n")
        print("=== \(name) ===\n\(text)")
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
