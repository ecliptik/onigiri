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
    @MainActor
    public static func repairStore(at url: URL) {
        // No store yet is every fresh install — silence is right there.
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        // The entity list is the SCHEMA's own, never a hand copy: the
        // copy this replaced had nothing keeping it in step with
        // `OnigiriSchemaV1.models`, so a future schema version would
        // have silently starved the repair (audit, 2026-08-17).
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: OnigiriSchemaV1.models)
        else {
            // The bridge failing means the repair switched itself off —
            // at exactly the moment a schema change makes it likeliest
            // to be needed. Never silent.
            maintenanceLog.error("repairStore: SwiftData model bridge failed — repair skipped")
            return
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
        if let loadError {
            // The second exit that used to be silent — and the one that
            // fires first when something is actually wrong (incompatible
            // store, disk fault, bad bridge).
            maintenanceLog.error("repairStore: store load failed, repair skipped: \(loadError)")
            return
        }
        defer {
            // A store left mounted here would collide with SwiftData
            // reopening the same file, whose failure path is fatalError —
            // an unload failure deserves a trace, not silence.
            let coordinator = container.persistentStoreCoordinator
            for store in coordinator.persistentStores {
                do { try coordinator.remove(store) } catch {
                    maintenanceLog.error("repairStore: store unload failed: \(error)")
                }
            }
        }

        let context = container.viewContext
        let fetchedItems: [NSManagedObject]
        do {
            fetchedItems = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "MealItem"))
        } catch {
            maintenanceLog.error("repairStore: MealItem fetch failed, skipping repair: \(error)")
            return
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
        if repaired {
            do { try context.save() } catch {
                maintenanceLog.error("repairStore: save failed, repairs not persisted: \(error)")
            }
        }
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
            meal.items.removeAll { item in dangling.contains { $0 === item } }
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
