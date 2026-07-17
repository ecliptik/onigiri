import Foundation
import Testing
@testable import OnigiriKit

struct HeadlineModeTests {
    // Intake 1,100; burn 1,500 → balance −400 (a deficit). Budget 1,682.
    private let summary = DailyEnergySummary(
        intakeKcal: 1100, activeBurnKcal: 380, restingBurnKcal: 1120,
        sodiumMg: 0, waterOz: 0
    )
    private let budget = 1682.0

    @Test func remainingReadsBudgetMinusIntake() {
        let r = CalorieBudget.headlineReadout(mode: .remaining, summary: summary, dailyBudgetKcal: budget)
        #expect(r.value == 582)            // 1682 − 1100
        #expect(r.caption == "kcal left")
        #expect(r.signed == false)
    }

    @Test func remainingFlipsToOverWhenBudgetExceeded() {
        let over = DailyEnergySummary(intakeKcal: 2000, activeBurnKcal: 0, restingBurnKcal: 0, sodiumMg: 0, waterOz: 0)
        let r = CalorieBudget.headlineReadout(mode: .remaining, summary: over, dailyBudgetKcal: budget)
        #expect(r.value == 318)            // |1682 − 2000|
        #expect(r.caption == "kcal over")
    }

    @Test func balanceIsSignedIntakeMinusBurn() {
        let r = CalorieBudget.headlineReadout(mode: .balance, summary: summary, dailyBudgetKcal: budget)
        #expect(r.value == -400)           // 1100 − 1500
        #expect(r.caption == "kcal balance")
        #expect(r.signed)
        #expect(r.statusLabel == "deficit")
    }

    @Test func eatenIsIntake() {
        let r = CalorieBudget.headlineReadout(mode: .eaten, summary: summary, dailyBudgetKcal: budget)
        #expect(r.value == 1100)
        #expect(r.caption == "kcal eaten")
        #expect(r.signed == false)
        #expect(r.statusLabel == nil)
    }

    @Test func budgetIsTheDailyBudget() {
        let r = CalorieBudget.headlineReadout(mode: .budget, summary: summary, dailyBudgetKcal: budget)
        #expect(r.value == 1682)
        #expect(r.caption == "kcal budget")
    }

    @Test func withoutBudgetRemainingAndBudgetFallBackToBalance() {
        for mode in [HeadlineMode.remaining, .budget] {
            let r = CalorieBudget.headlineReadout(mode: mode, summary: summary, dailyBudgetKcal: nil)
            #expect(r.caption == "kcal balance")
            #expect(r.value == -400)
        }
    }

    @Test func availableModesDependOnBudget() {
        #expect(HeadlineMode.available(hasBudget: true) == [.remaining, .balance, .eaten, .budget])
        #expect(HeadlineMode.available(hasBudget: false) == [.balance, .eaten])
    }

    @Test func cycleWalksAllFourWithABudget() {
        #expect(HeadlineMode.remaining.next(hasBudget: true) == .balance)
        #expect(HeadlineMode.balance.next(hasBudget: true) == .eaten)
        #expect(HeadlineMode.eaten.next(hasBudget: true) == .budget)
        #expect(HeadlineMode.budget.next(hasBudget: true) == .remaining)
    }

    @Test func cycleSkipsBudgetlessModesWhenNoGoal() {
        // Only balance ↔ eaten are reachable; a stored remaining/budget
        // steps into the available ring rather than sticking.
        #expect(HeadlineMode.balance.next(hasBudget: false) == .eaten)
        #expect(HeadlineMode.eaten.next(hasBudget: false) == .balance)
        #expect(HeadlineMode.remaining.next(hasBudget: false) == .balance)
        #expect(HeadlineMode.budget.next(hasBudget: false) == .balance)
    }

    @Test func resolvedFallsBackWhenUnavailable() {
        #expect(HeadlineMode.budget.resolved(hasBudget: false) == .balance)
        #expect(HeadlineMode.remaining.resolved(hasBudget: false) == .balance)
        #expect(HeadlineMode.eaten.resolved(hasBudget: false) == .eaten)
        #expect(HeadlineMode.budget.resolved(hasBudget: true) == .budget)
    }
}
