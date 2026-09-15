import Foundation
import SwiftData
import CoreData
import os

private nonisolated let maintenanceLog =
    Logger(subsystem: "com.ecliptik.Onigiri", category: "maintenance")

/// One-time store repairs run at app launch.
public enum LibraryMaintenance {
    /// Heal dangling MealItem→Food references BEFORE SwiftData opens the
    /// store. SwiftData traps the process the moment such a relationship
    /// resolves ("backing data could no longer be found"), so the context
    /// based sweep below can't even inspect the damage. Core Data can:
    /// `objectIDs(forRelationshipNamed:)` reads the stored reference
    /// without firing the fault, and `existingObject(with:)` throws
    /// instead of trapping when the target row is gone.
    ///
    /// `@MainActor` states the contract the single call site already
    /// keeps (`OnigiriApp.init`). `viewContext` is main-queue-confined and
    /// nothing here is wrapped in `perform`, so an off-main caller would
    /// produce exactly the wrong-thread crash class this function exists
    /// to prevent — now a compile error rather than a convention.
    ///
    /// Returns whether it is SAFE to proceed to the SwiftData-level pass
    /// (`repairDanglingFoodReferences`) — `true` for "definitely nothing to
    /// repair" (fresh install) or "repair ran to completion, store is
    /// clean," `false` for every exit that leaves the store's condition
    /// UNKNOWN. The caller must gate the next pass on this: that pass
    /// touches every `MealItem.food` unconditionally, and SwiftData KILLS
    /// THE PROCESS the instant that property resolves a genuinely dangling
    /// reference (CLAUDE.md's SwiftData landmine). A `Void`-returning
    /// version of this function let a silent early exit here (a bad
    /// bridge, a locked file, a failed save) run straight into that touch
    /// on EVERY launch thereafter — turning a one-time repair failure into
    /// a permanent crash loop, the exact class of bug this whole mechanism
    /// exists to prevent (health-check audit, 2026-08-31).
    @discardableResult
    @MainActor
    public static func repairStore(at url: URL) -> Bool {
        // No store yet is every fresh install — silence is right there,
        // and there is nothing for the next pass to trip over.
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        // The model must match what's ACTUALLY on disk, never just the
        // newest schema the migration plan knows — this repair runs
        // BEFORE SwiftData opens (and migrates) the store, and automatic
        // migration is deliberately off below, so loading a store that
        // still sits at an older schema version against the latest
        // model would fail as a version mismatch and skip BOTH repair
        // passes right when a migration is about to run — exactly the
        // moment relationship damage is likeliest (health-check audit,
        // 2026-09-14; latent today since only one schema version has
        // ever shipped, live the moment a second one does). A hardcoded
        // `OnigiriSchemaV1` has the same failure mode in the other
        // direction the moment OnigiriSchemaV2 ships (2026-08-31 audit)
        // — the fix is neither hardcoded nor always-latest, it's
        // whichever schema the store's own metadata says it is.
        guard let model = Self.matchingModel(forStoreAt: url) else {
            // No schema in the plan matches — the bridge failed, or the
            // store predates every schema on record. Either way the
            // repair switched itself off; never silent.
            maintenanceLog.error("repairStore: no matching schema for the on-disk store — repair skipped")
            return false
        }
        let container = NSPersistentContainer(name: "Onigiri", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.shouldAddStoreAsynchronously = false
        // This tool inspects a store; it must never evolve one — schema
        // changes are OnigiriMigrationPlan's job alone. Both flags
        // default TRUE, so left unset, a future model/store mismatch
        // could quietly attempt an automatic migration of the shared
        // store against this repair-only model. Mismatches now fail the
        // load — loudly, below (audit, 2026-08-17).
        description.shouldMigrateStoreAutomatically = false
        description.shouldInferMappingModelAutomatically = false
        // SwiftData stores track persistent history; without opting in the
        // store mounts read-only and the repair can't save.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }

        // Computed BEFORE unloading below, so the unload step can fold
        // ITS OWN outcome into the same result the caller sees. A defer
        // can't do that: Swift captures a `return`'s value the moment
        // that statement runs, before any deferred code executes, so a
        // defer block that failed to unload could never downgrade an
        // already-decided `true` — it could only log, which is what this
        // used to do (health-check audit, 2026-09-14).
        var repairSucceeded: Bool
        if let loadError {
            // The second exit that used to be silent — and the one that
            // fires first when something is actually wrong (incompatible
            // store, disk fault, bad bridge).
            maintenanceLog.error("repairStore: store load failed, repair skipped: \(loadError)")
            repairSucceeded = false
        } else {
            repairSucceeded = Self.repairFetchedItems(in: container.viewContext)
        }

        // Always attempted, load failure or not — coordinator.persistentStores
        // is simply empty in that case, so this is a safe no-op then. A
        // store left mounted here would collide with SwiftData reopening
        // the same file, whose failure path is fatalError — never
        // silently report success over that.
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            do { try coordinator.remove(store) } catch {
                maintenanceLog.error("repairStore: store unload failed: \(error)")
                repairSucceeded = false
            }
        }
        return repairSucceeded
    }

    /// The MealItem fetch, repair, and save — everything that needs the
    /// store to already be loaded. Split out so `repairStore` can run the
    /// (always-attempted) unload after this regardless of outcome and
    /// still fold the unload's own success into what it returns.
    private static func repairFetchedItems(in context: NSManagedObjectContext) -> Bool {
        let fetchedItems: [NSManagedObject]
        do {
            fetchedItems = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "MealItem"))
        } catch {
            maintenanceLog.error("repairStore: MealItem fetch failed, skipping repair: \(error)")
            return false
        }
        var repaired = false
        for item in fetchedItems {
            let foodIDs = item.objectIDs(forRelationshipNamed: "food")
            let dangling = foodIDs.contains { rowIsMissing($0, in: context) }
            // No food at all is a phantom 0 kcal line; drop those too.
            guard dangling || foodIDs.isEmpty else { continue }
            if dangling { item.setValue(nil, forKey: "food") }
            context.delete(item)
            repaired = true
        }

        // No second pass over `Meal.items`, and the asymmetry is
        // deliberate — an audit proposed one on 2026-08-17 and measuring
        // the store refuted it. A TO-ONE (`MealItem.food`) is a foreign
        // key on the MealItem row, so the row it names can be deleted out
        // from under it and the key still points there: that dangles, and
        // that is the crash this function exists for. A TO-MANY is stored
        // as the child's foreign key (`ZMEALITEM.ZMEAL` — verified: the
        // store has no `Z_*ITEMS` join table), so `items` is a QUERY for
        // children pointing back. A deleted child is simply not returned.
        // There is no reference left to dangle, which is why the repair
        // is one-directional. Don't add the other half.
        guard repaired else { return true }
        do {
            try context.save()
            return true
        } catch {
            // The worst of the five exits: repairs were COMPUTED
            // (deletes staged in this context) but never PERSISTED —
            // the on-disk store still carries whatever was dangling,
            // indistinguishable from having never looked. Must report
            // failure like every other exit here.
            maintenanceLog.error("repairStore: save failed, repairs not persisted: \(error)")
            return false
        }
    }

    /// The `NSManagedObjectModel` for whichever schema in the migration
    /// plan is compatible with what's actually on disk — tried newest
    /// first, since a real version collision between two distinct
    /// schemas should not happen, but if it somehow did the newer one is
    /// the better guess.
    private static func matchingModel(forStoreAt url: URL) -> NSManagedObjectModel? {
        guard let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(
            type: .sqlite, at: url)
        else { return nil }
        for schema in OnigiriMigrationPlan.schemas.reversed() {
            guard let model = NSManagedObjectModel.makeManagedObjectModel(for: schema.models),
                  model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
            else { continue }
            return model
        }
        return nil
    }

    /// True only when Core Data affirmatively reports the referenced row
    /// is gone (`NSManagedObjectReferentialIntegrityError`). Any other
    /// `existingObject(with:)` failure — locked file, I/O hiccup — must
    /// NOT count as dangling: the repair deletes the item and persists
    /// that delete, so misreading a transient error would turn a
    /// recoverable failure into silent data loss.
    private static func rowIsMissing(_ id: NSManagedObjectID, in context: NSManagedObjectContext) -> Bool {
        do {
            _ = try context.existingObject(with: id)
            return false
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain,
               nsError.code == NSManagedObjectReferentialIntegrityError {
                return true
            }
            maintenanceLog.error(
                "repairStore: existingObject failed transiently (\(nsError.domain) \(nsError.code)); leaving item untouched"
            )
            return false
        }
    }

    /// Settings' library reset. INSTANCE deletes, not `delete(model:)`:
    /// batch deletes bypass relationship maintenance and die on the
    /// mandatory nullify inverse ("Constraint trigger violation …
    /// MealItem/food" — caught by the reset round-trip E2E). Items go
    /// first so nothing ever dangles mid-wipe.
    @MainActor
    public static func wipeLibrary(context: ModelContext) throws {
        for item in try context.fetch(FetchDescriptor<MealItem>()) { context.delete(item) }
        for meal in try context.fetch(FetchDescriptor<Meal>()) { context.delete(meal) }
        for food in try context.fetch(FetchDescriptor<Food>()) { context.delete(food) }
        try context.save()
    }

    /// Settings' goals reset (the deficit history is the caller's job —
    /// it lives in defaults, not the store).
    @MainActor
    public static func wipeGoals(context: ModelContext) throws {
        for goal in try context.fetch(FetchDescriptor<GoalSettings>()) { context.delete(goal) }
        try context.save()
    }

    /// Delete meal items whose food was removed out from under them.
    ///
    /// Stores written before Food↔MealItem had an inverse relationship can
    /// hold items whose food row no longer exists; resolving such an item's
    /// food and touching any property traps SwiftData with "backing data
    /// could no longer be found". Identifiers are safe to read without
    /// firing the fault, so membership in the live-food set is the test.
    /// Items already nullified (food == nil) are dropped too — a food-less
    /// item only contributes a phantom 0 kcal line to its meal.
    ///
    /// The SwiftData-level twin of `repairStore`'s first pass, for damage
    /// this process causes (a food deleted in Foods) rather than damage it
    /// inherits. It cannot replace that pass: by the time SwiftData is
    /// open, an inherited dangling reference has already trapped.
    ///
    /// `@MainActor` for the reason `repairStore` states: this store is
    /// main-context-only, and the annotation makes that a compile error
    /// rather than a convention every future caller has to know.
    @MainActor
    public static func repairDanglingFoodReferences(context: ModelContext) {
        let meals: [Meal]
        let foods: [Food]
        do {
            meals = try context.fetch(FetchDescriptor<Meal>())
            foods = try context.fetch(FetchDescriptor<Food>())
        } catch {
            // Same rule as the save below: a repair that silently could
            // not look is indistinguishable from one that found nothing
            // wrong.
            maintenanceLog.error("repairDanglingFoodReferences: fetch failed, skipping: \(error)")
            return
        }
        let liveFoodIDs = Set(foods.map(\.persistentModelID))
        var repaired = false
        for meal in meals {
            let dangling = meal.items.filter { item in
                guard let food = item.food else { return true }
                return !liveFoodIDs.contains(food.persistentModelID)
            }
            guard !dangling.isEmpty else { continue }
            // Set membership on the stable persistentModelID, not a
            // nested identity scan — the O(n×m) form was cheap at
            // personal-library scale but free to avoid while already
            // touching this function (health-check audit, 2026-08-31).
            let danglingIDs = Set(dangling.map(\.persistentModelID))
            meal.items.removeAll { danglingIDs.contains($0.persistentModelID) }
            dangling.forEach(context.delete)
            repaired = true
        }
        // Traced like `repairStore`'s save: a repair that silently failed
        // to persist looks identical to one that found nothing wrong, and
        // the difference is whether the next launch still crashes.
        if repaired {
            do { try context.save() } catch {
                maintenanceLog.error(
                    "repairDanglingFoodReferences: save failed, repairs not persisted: \(error)"
                )
            }
        }
    }
}
