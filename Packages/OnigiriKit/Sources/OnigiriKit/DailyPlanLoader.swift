import Foundation

/// Combines today's HealthKit summary with a (possibly synced) goal into the
/// numbers the watch app and complications render. Plan assembly
/// (`makeState`) is pure and lives outside the HealthKit guard so the
/// macOS test host can reach it; only the fetch layer needs the store.
@MainActor
public enum DailyPlanLoader {
    /// Codable since 2026-08-03 so the watch complications can persist a
    /// last-good copy: their providers had no equivalent of the phone's
    /// `widget.lastGoodSnapshot`, so a reload against a SEALED watch
    /// store (off wrist, locked) fell through `try? ... ?? .zero` below
    /// and rendered a confident zero day. Stale-but-true beats
    /// confidently wrong — the same rule the phone already followed.
    public struct State: Sendable, Codable {
        public let summary: DailyEnergySummary
        public let deficitTargetKcal: Double?
        /// 0...1 fill of the onigiri gauge (banked deficit / daily target).
        public let gaugeProgress: Double
        /// Intake budget for the day (the day's own burn − required deficit).
        public let dailyBudgetKcal: Double?
        /// The burn the budget was cut from (`DayBudget.dayBurn`) — the
        /// figure every verdict-shaped number on this state must read,
        /// so the gauge, the goal line and the headline can't answer the
        /// same question differently. nil when there's no plan.
        public let dayBurnKcal: Double?
        /// The Active/Resting credited split (`DayBudget.creditedActive`
        /// and its inline resting counterpart) — what Today's own
        /// meter rows show, and what the extra-large widget layout
        /// reuses rather than re-deriving. nil alongside `dayBurnKcal`
        /// when there's no plan or nothing measured yet.
        public let creditedRestingKcal: Double?
        public let creditedActiveKcal: Double?
        /// The burn correction as applied to today (after its cap and
        /// floor), so Active + Resting + this == `dayBurnKcal` exactly.
        /// Its own ROW wherever the split prints: folded into resting it
        /// would breach resting's floor, into active it goes negative on
        /// a quiet day (`plans/PLAN-burn-correction.md`). nil or 0
        /// without one — a pre-correction cached state decodes as nil.
        public let creditedCorrectionKcal: Double?

        public init(
            summary: DailyEnergySummary,
            deficitTargetKcal: Double?,
            gaugeProgress: Double,
            dailyBudgetKcal: Double? = nil,
            dayBurnKcal: Double? = nil,
            creditedRestingKcal: Double? = nil,
            creditedActiveKcal: Double? = nil,
            creditedCorrectionKcal: Double? = nil
        ) {
            self.summary = summary
            self.deficitTargetKcal = deficitTargetKcal
            self.gaugeProgress = gaugeProgress
            self.dailyBudgetKcal = dailyBudgetKcal
            self.dayBurnKcal = dayBurnKcal
            self.creditedRestingKcal = creditedRestingKcal
            self.creditedActiveKcal = creditedActiveKcal
            self.creditedCorrectionKcal = creditedCorrectionKcal
        }

        /// kcal still available to eat today, when a plan exists.
        public var remainingKcal: Double? {
            dailyBudgetKcal.map { $0 - summary.intakeKcal }
        }

        /// The day's deficit on the budget's own burn, positive for a
        /// deficit. Falls back to the raw measured balance only where
        /// there is no plan to disagree with.
        public var deficitKcal: Double {
            DayBudget.deficit(
                intakeKcal: summary.intakeKcal,
                dayBurnKcal: dayBurnKcal ?? summary.totalBurnKcal
            )
        }

        public static let empty = State(summary: .zero, deficitTargetKcal: nil, gaugeProgress: 0)
    }

    /// Assemble the rendered state from already-fetched Health numbers.
    /// Maintenance: eat what you burn — deficitTarget stays nil (the
    /// any-deficit badge rule, no "% of goal" captions) and the gauge
    /// shows budget left. A weight goal banks deficit toward the target;
    /// without a current weight anywhere there is no plan.
    ///
    /// Both modes ride the SAME burn figure the phone does
    /// (`DayBudget.dayBurn`): resting credited up front — measured,
    /// floored by the body-metric estimate — plus the active energy
    /// actually earned. The trailing-average forecast is gone. It lived
    /// here longer than on the phone, which is precisely why this had to
    /// move before shipping: the widgets and the watch would have gone on
    /// quoting an average-based budget while Today quoted the earned one.
    public static func makeState(
        goal: SyncedGoal?,
        summary: DailyEnergySummary,
        /// Full-day resting from body metrics (`BasalEstimate.restingKcal`),
        /// the floor under the day's resting credit. nil when Health can't
        /// describe the body well enough — measured resting then stands
        /// alone, which is a documented shortfall, not an error.
        estimatedRestingKcal: Double?,
        healthWeightLb: Double?,
        /// The day-ratcheted day burn (TodayBurnFloor) when the caller has
        /// one — the budget derives from it while the summary keeps the
        /// honest display numbers. nil = derive straight from the summary,
        /// the pure pre-ratchet behavior the tests pin.
        todayBurnFloorKcal: Double? = nil,
        /// The accepted burn correction (`SharedStore.burnCorrectionKcal`
        /// at the caller). Applied AFTER the ratchet: the floor guards
        /// Health's measurement, the correction is a separate term, and
        /// ratcheting a corrected figure would pin a mid-day acceptance
        /// under the uncorrected high mark until midnight. Defaulted to 0
        /// here only because this is pure assembly with a dozen tests —
        /// `load`, the path every surface takes, requires it.
        burnCorrectionKcal: Double = 0,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> State {
        guard let goal else {
            return State(summary: summary, deficitTargetKcal: nil, gaugeProgress: 0)
        }
        let measuredBurn = todayBurnFloorKcal ?? DayBudget.uncorrectedDayBurn(
            activeKcal: summary.activeBurnKcal,
            restingKcal: summary.restingBurnKcal,
            estimatedRestingKcal: estimatedRestingKcal
        )
        let dayBurn = BurnCorrection.apply(
            toBurnKcal: measuredBurn,
            estimatedRestingKcal: estimatedRestingKcal,
            correctionKcal: burnCorrectionKcal
        )
        let creditedCorrection = dayBurn - measuredBurn
        // Nothing measured and no estimate to floor it with: a budget of
        // "0 minus the target" would invent a huge overage, so the
        // budget-shaped UI stands down (TodayView's guard). The deficit
        // target still stamps history — the goal was in force either way.
        let hasBurn = dayBurn > 0
        // The same split Today's own meter rows show (DayBudget.swift) —
        // resting credited up front and floored by the estimate, active
        // never less than what was actually measured. Computed once here
        // for both branches below rather than re-derived by every reader.
        let creditedResting = max(summary.restingBurnKcal, estimatedRestingKcal ?? 0)
        // Split off the MEASURED burn: the correction is the third row,
        // not a share of either channel.
        let creditedActive = DayBudget.creditedActive(
            dayBurnKcal: measuredBurn, creditedRestingKcal: creditedResting,
            measuredActiveKcal: summary.activeBurnKcal
        )
        if goal.isMaintenance {
            let plan = CalorieBudget.completedDayPlan(
                dayBurnKcal: dayBurn, requiredDailyDeficit: 0
            )
            let progress = plan.dailyBudget > 0
                ? max(0, min(1, 1 - summary.intakeKcal / plan.dailyBudget))
                : 0
            return State(
                summary: summary,
                deficitTargetKcal: nil,
                gaugeProgress: progress,
                dailyBudgetKcal: hasBurn ? plan.dailyBudget : nil,
                dayBurnKcal: hasBurn ? dayBurn : nil,
                creditedRestingKcal: hasBurn ? creditedResting : nil,
                creditedActiveKcal: hasBurn ? creditedActive : nil,
                creditedCorrectionKcal: hasBurn ? creditedCorrection : nil
            )
        }
        guard let deficit = CalorieBudget.requiredDailyDeficit(
            currentWeightLb: healthWeightLb ?? goal.fallbackCurrentWeightLb,
            targetWeightLb: goal.targetWeightLb,
            targetDate: goal.targetDate,
            calendar: calendar,
            now: now
        ) else {
            return State(summary: summary, deficitTargetKcal: nil, gaugeProgress: 0)
        }
        let plan = CalorieBudget.completedDayPlan(
            dayBurnKcal: dayBurn, requiredDailyDeficit: deficit
        )
        // Banked on the SAME burn the budget was cut from, so the gauge
        // can't sit part-full while the number beside it says the day is
        // already inside its budget.
        let banked = DayBudget.deficit(intakeKcal: summary.intakeKcal, dayBurnKcal: dayBurn)
        let progress = plan.requiredDailyDeficit > 0
            ? max(0, min(1, banked / plan.requiredDailyDeficit))
            : 1
        return State(
            summary: summary,
            deficitTargetKcal: plan.requiredDailyDeficit,
            gaugeProgress: progress,
            dailyBudgetKcal: hasBurn ? plan.dailyBudget : nil,
            dayBurnKcal: hasBurn ? dayBurn : nil,
            creditedRestingKcal: hasBurn ? creditedResting : nil,
            creditedActiveKcal: hasBurn ? creditedActive : nil,
            creditedCorrectionKcal: hasBurn ? creditedCorrection : nil
        )
    }

    /// One plan input resolved between the phone's synced copy and the
    /// local Health read. The synced value wins while its day stamp is
    /// today or yesterday: the phone's store holds full history, while
    /// watchOS purges old samples — a weigh-in older than the watch's
    /// window is invisible there, and the two devices' plans drift apart.
    nonisolated static func planInput(
        synced: (value: Double, day: String)?,
        local: Double?,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Double? {
        guard let synced, WatchSync.isRecentDay(synced.day, calendar: calendar, now: now)
        else { return local }
        return synced.value
    }
}

#if canImport(HealthKit)
/// The reads the loader performs — injectable so tests can stub the
/// store (the audit's HealthKitService-injection gap, scoped to the
/// loader's surface).
@MainActor
public protocol HealthPlanReading: Sendable {
    func todaySummary() async throws -> DailyEnergySummary
    func latestBodyMassLb() async throws -> Double?
    /// The weight the DEFICIT TARGET is derived from — the user's
    /// `WeightBasis` applied to recent history, which is not always the
    /// last weigh-in (PLAN-target-weight-basis).
    ///
    /// Every surface that computes a deficit must call THIS and not
    /// `latestBodyMassLb()`, or Today and the widget quote different
    /// numbers for the same day.
    func targetBasisWeightLb() async -> Double?
    /// Height/age/sex — with weight, the inputs the resting estimate
    /// needs. The trailing burn average it replaced is no longer a plan
    /// input on any surface.
    func bodyProfile() async -> (heightCm: Double?, ageYears: Int?, sex: BasalEstimate.Sex)
    /// Day stamp on the last weight this store successfully answered
    /// with — the evidence a nil weight is judged against
    /// (`HealthReadTrust`). Read AFTER the weight, since the basis read
    /// writes through to it.
    func lastGoodWeightDay() -> String?
}

public extension HealthPlanReading {
    /// Raw latest — the honest degradation, and what a test double gets
    /// without implementing anything.
    func targetBasisWeightLb() async -> Double? {
        (try? await latestBodyMassLb()) ?? nil
    }

    /// The write-through `targetBasisWeightLb` maintains. It is a cache
    /// lookup, not a query — the seal check must not put a second sample
    /// query on the complication/widget refresh path.
    func lastGoodWeightDay() -> String? {
        HealthKitService.cachedPlanWeightLb()?.day
    }
}

// `HealthKitService: HealthPlanReading` conformance lives in
// HealthKitService.swift, not here — Swift requires a Sendable-inheriting
// conformance (`HealthPlanReading: Sendable`) to be declared in the SAME
// FILE as the class it applies to, and warned here until moved
// (2026-09-17, an Xcode warning sweep: "Conformance to 'Sendable' must
// occur in the same source file as class 'HealthKitService'").

public extension DailyPlanLoader {
    /// `burnCorrectionKcal` has no default on purpose: every surface —
    /// app, widgets, watch, intents — must say which correction it judged
    /// by, and they all say `SharedStore.burnCorrectionKcal`, which the
    /// watch receives through the settings sync.
    static func load(
        goal: SyncedGoal?,
        burnCorrectionKcal: Double,
        health: any HealthPlanReading = HealthKitService()
    ) async -> State {
        let (state, planWeightLb) = await computeState(
            goal: goal, burnCorrectionKcal: burnCorrectionKcal, health: health)
        // Every plan load stamps today's rule, so history keeps being
        // judged by the goal in force that day even after the goal (or
        // the weight behind it) changes — but ONLY when the read behind
        // it can be trusted. A SEALED store answers a weight goal with a
        // nil target, which `recordToday` writes as 0 = "any deficit
        // earns the badge", permanently re-grading the day. See
        // `HealthReadTrust.mayStampPlan`; a rendered sealed read is
        // corrected by the next refresh, a stamped one never is.
        guard HealthReadTrust.mayStampPlan(
            deficitTargetKcal: state.deficitTargetKcal,
            hasWeightGoal: goal.map { !$0.isMaintenance } ?? false,
            weightLb: planWeightLb,
            cachedDay: health.lastGoodWeightDay()
        ) else { return state }
        DeficitTargetHistory.recordToday(
            targetKcal: state.deficitTargetKcal,
            isMaintenance: goal?.isMaintenance ?? false
        )
        return state
    }

    #if DEBUG
    /// Every input the budget is built from, in one line.
    ///
    /// Exists because a budget can move hundreds of kcal without anything
    /// visible changing (2026-08-07: the morning's "kcal left" rose by
    /// hundreds an hour later, at a desk). The suspicion is the WEIGHT read: it feeds
    /// both the resting estimate and — via
    /// `healthWeightLb ?? goal.fallbackCurrentWeightLb` — the required
    /// deficit, so a sealed store on a locked phone silently swaps in the
    /// goal's stored weight. With a near target date a few pounds is
    /// hundreds of kcal/day, and `TodayBurnFloor` keeps `dayBurn` pinned
    /// at its high-water mark so the budget shrinks instead of standing
    /// down, which makes the swap invisible. Print it rather than infer it.
    ///
    /// The weight it prints is the RESOLVED one — what the plan actually
    /// rode, through the same `resolvedWeight` `computeState` uses. On the
    /// watch that is not the local read: the phone's synced basis wins
    /// while its day stamp is recent, so printing the local one made this
    /// line disagree with the budget beside it on the one device where
    /// the two can differ (2026-09-20, chasing a phone/watch budget
    /// gap). Both are printed, plus the synced pair, because WHICH of
    /// them the plan took is the question.
    static func diagnose(
        goal: SyncedGoal?,
        burnCorrectionKcal: Double,
        health: any HealthPlanReading = HealthKitService(),
        now: Date = .now
    ) async -> String {
        let summary = (try? await health.todaySummary()) ?? .zero
        let localWeight = await health.targetBasisWeightLb()
        let syncedWeight = WatchSync.syncedPlanWeight()
        let healthWeight = resolvedWeight(localWeight)
        let profile = await health.bodyProfile()
        let estimate: Double? = {
            guard let heightCm = profile.heightCm, let age = profile.ageYears,
                  let weightLb = healthWeight else { return nil }
            return BasalEstimate.restingKcal(
                weightLb: weightLb, heightCm: heightCm, ageYears: age, sex: profile.sex)
        }()
        let rawBurn = DayBudget.uncorrectedDayBurn(
            activeKcal: summary.activeBurnKcal,
            restingKcal: summary.restingBurnKcal,
            estimatedRestingKcal: estimate
        )
        // READ-only: `ratcheted` would RECORD this, so merely printing
        // the budget's inputs moved the budget — and at a midnight
        // launch it could write the very mark every other call site is
        // now guarded against. This is what `ratcheted` would return
        // without the write.
        let floored = max(rawBurn, TodayBurnFloor.todayMark(now: now))
        let deficit = goal.flatMap {
            CalorieBudget.requiredDailyDeficit(
                currentWeightLb: healthWeight ?? $0.fallbackCurrentWeightLb,
                targetWeightLb: $0.targetWeightLb,
                targetDate: $0.targetDate,
                now: now
            )
        }
        func show(_ value: Double?) -> String { value.map { String(Int($0)) } ?? "nil" }
        // The two figures the SCREEN shows, so a phone line and a watch
        // line can be diffed without re-doing the arithmetic by hand —
        // and so a gap can be attributed to a term rather than guessed
        // at. `left` is negative when over, where the headline flips to
        // "kcal over" and drops the sign.
        // The correction after the floor, exactly as `makeState` does —
        // and printed, so a phone line and a watch line that disagree on
        // it name the settings sync as the suspect at a glance.
        let corrected = BurnCorrection.apply(
            toBurnKcal: floored, estimatedRestingKcal: estimate,
            correctionKcal: burnCorrectionKcal)
        let budget = corrected - max(0, deficit ?? 0)
        return "budget active=\(Int(summary.activeBurnKcal))"
            + " restingMeasured=\(Int(summary.restingBurnKcal))"
            + " restingEstimate=\(show(estimate))"
            + " weightHealth=\(show(healthWeight))"
            + " weightLocal=\(show(localWeight))"
            + " weightSynced=\(syncedWeight.map { "\(Int($0.lb))@\($0.day)" } ?? "nil")"
            + " weightFallback=\(show(goal?.fallbackCurrentWeightLb))"
            + " height=\(show(profile.heightCm)) age=\(profile.ageYears.map(String.init) ?? "nil")"
            + " rawBurn=\(Int(rawBurn)) floored=\(Int(floored))"
            + " correction=\(Int(burnCorrectionKcal)) corrected=\(Int(corrected))"
            + " deficit=\(show(deficit))"
            + " intake=\(Int(summary.intakeKcal))"
            + " budget=\(Int(budget)) left=\(Int(budget - summary.intakeKcal))"
    }
    #endif

    /// The state, plus the weight the plan was built from — the caller
    /// needs that weight to judge whether the read was trustworthy
    /// enough to persist (`HealthReadTrust.mayStampPlan`), and re-reading
    /// it would put a second sample query on the complication/widget
    /// refresh path for a value already in hand. It is the RESOLVED
    /// weight, because that is the one the deficit target rides: on the
    /// watch a fresh synced weight makes the target trustworthy even
    /// while the local store is sealed.
    private static func computeState(
        goal: SyncedGoal?,
        burnCorrectionKcal: Double,
        health: any HealthPlanReading
    ) async -> (state: State, planWeightLb: Double?) {
        guard let goal else {
            let summary = (try? await health.todaySummary()) ?? .zero
            return (makeState(
                goal: nil, summary: summary,
                estimatedRestingKcal: nil, healthWeightLb: nil
            ), nil)
        }
        // The reads are independent — run them concurrently; this path
        // is complication/widget refresh latency. Weight is read even in
        // maintenance now: it isn't a plan input there, but the resting
        // estimate that floors the day's burn is built from it.
        // Captured BEFORE the reads start. `todaySummary()` fixes its own
        // day window when it runs, so this is a conservative lower bound
        // on which day the figures below describe — and conservative is
        // what the guard wants: it skips the ratchet WRITE whenever the
        // read might have crossed midnight, which costs one skipped mark
        // a day and prevents the 2026-09-20 lock-in.
        // See `TodayBurnFloor.ratcheted(readAt:)`.
        let readStart = Date()
        async let summaryRead = health.todaySummary()
        // The BASIS, not the raw latest: the deficit target rides this,
        // and so does the resting estimate below, so one screen never
        // mixes two different "current weights".
        async let weightRead = health.targetBasisWeightLb()
        async let profileRead = health.bodyProfile()
        let summary = (try? await summaryRead) ?? .zero
        let weightLb = resolvedWeight(await weightRead)
        let profile = await profileRead
        let estimatedResting: Double? = {
            guard let heightCm = profile.heightCm, let age = profile.ageYears,
                  let weightLb else { return nil }
            return BasalEstimate.restingKcal(
                weightLb: weightLb, heightCm: heightCm,
                ageYears: age, sex: profile.sex)
        }()
        #if DEBUG
        // Durable trail of the budget's inputs, for the same reason the
        // burn journal exists: a budget rose hundreds of kcal in the hour after
        // waking (2026-08-07), and by the time anyone could
        // look the inputs were self-consistent and the morning's were
        // gone. os_log does not survive on a busy device; this does.
        WidgetBurnGate.notePlan(
            active: summary.activeBurnKcal,
            restingMeasured: summary.restingBurnKcal,
            restingEstimate: estimatedResting,
            weight: weightLb
        )
        #endif
        // Ratchet the DAY burn, not the raw total: under measured-only
        // active energy the guard against Health revising burn downward
        // mid-day matters more, not less.
        // The UNCORRECTED burn is what ratchets; `makeState` applies the
        // correction on top (see its parameter note).
        let dayBurn = DayBudget.uncorrectedDayBurn(
            activeKcal: summary.activeBurnKcal,
            restingKcal: summary.restingBurnKcal,
            estimatedRestingKcal: estimatedResting
        )
        return (makeState(
            goal: goal,
            summary: summary,
            estimatedRestingKcal: estimatedResting,
            healthWeightLb: weightLb,
            todayBurnFloorKcal: TodayBurnFloor.ratcheted(dayBurn, readAt: readStart),
            burnCorrectionKcal: burnCorrectionKcal
        ), weightLb)
    }

    /// On the watch, prefer the phone's synced weight while fresh (see
    /// `planInput`); everywhere else the local store IS the phone's.
    ///
    /// Both sides of that choice are a BASIS weight — the local read is
    /// `targetBasisWeightLb`, and the phone now sends the same thing
    /// rather than its raw latest weigh-in. They have to be the same kind
    /// of number, because this preference silently decides which one the
    /// wrist quotes.
    private static func resolvedWeight(_ local: Double?) -> Double? {
        #if os(watchOS)
        return planInput(
            synced: WatchSync.syncedPlanWeight().map { ($0.lb, $0.day) }, local: local
        )
        #else
        return local
        #endif
    }
}
#endif
