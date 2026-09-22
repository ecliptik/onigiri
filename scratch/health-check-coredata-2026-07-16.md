# Core Data Safety Audit — LibraryMaintenance.swift (2026-07-16)

## Summary
- CRITICAL: 1, HIGH: 1, MEDIUM: 1, LOW: 1

## Architecture note
Core Data here is purely a one-shot pre-flight repair tool: opens the SwiftData-backed SQLite file directly via NSPersistentContainer, heals dangling MealItem.food references via objectID-level introspection, saves, unloads, hands the file back to SwiftData (OnigiriApp.swift:36-39 → SharedStore.modelContainer(), which `fatalError`s on failure). Any silent Core Data failure here can cascade into an app-wide launch crash.

## Issues by Severity

### CRITICAL — existingObject(with:) failure conflated with "row is gone"
**File**: `Packages/OnigiriKit/Sources/OnigiriKit/LibraryMaintenance.swift:41`
```swift
let dangling = foodIDs.contains { (try? context.existingObject(with: $0)) == nil }
```
**Issue**: `try?` collapses every possible error (transient I/O, permission, locked store) into the same nil result as "legitimately deleted." A transient failure causes a valid MealItem to be classified dangling, unlinked/deleted, and the delete is PERSISTED via context.save() at line 48 — real, narrow data-loss path.
**Fix**: distinguish "not found" from other errors; only treat NSManagedObjectReferentialIntegrityError-class failures as dangling, skip deletion on ambiguous/transient errors.

### HIGH — Silent try? on store removal risks a locked file blocking the subsequent SwiftData open
**File**: `Packages/OnigiriKit/Sources/OnigiriKit/LibraryMaintenance.swift:32`
```swift
defer { coordinator.persistentStores.forEach { try? coordinator.remove($0) } }
```
**Issue**: If remove(_:) fails, failure is swallowed silently and the file may remain associated with this coordinator when OnigiriApp.init() immediately opens it with SwiftData, whose failure path is `fatalError`. Note: the project's own test (LibraryMaintenanceTests.swift:107-108) uses the throwing form and propagates errors — production code's silencing is inconsistent with tested/expected behavior.
**Fix**: log a diagnostic when remove throws; consider assertionFailure/os_log(.fault) in debug builds.

### MEDIUM — Repair fetch/save silently no-op on failure with zero observability
**File**: `Packages/OnigiriKit/Sources/OnigiriKit/LibraryMaintenance.swift:36-37, 48`
**Issue**: Both fetch and final save swallow errors entirely; no logging to tell whether repair silently fails run after run.
**Fix**: log both failure points (os_log at .error) so a stuck repair is discoverable via `devicectl device process launch --console`.

### LOW — No thread-confinement guard on the Core Data context
**File**: `Packages/OnigiriKit/Sources/OnigiriKit/LibraryMaintenance.swift:35-48`
**Issue**: context.fetch/setValue/delete/save called directly on viewContext with no context.perform wrapper; repairStore(at:) isn't @MainActor-isolated. Safe today only because the sole call site (OnigiriApp.init()) runs on main thread — no compiler/runtime guard enforces this.
**Fix**: wrap body in context.performAndWait{}, or mark repairStore(at:) @MainActor to match documented call-site contract (as wipeLibrary/wipeGoals already do).

## Verified correct (no issue)
- NSPersistentHistoryTrackingKey set unconditionally, durable (persists in store metadata, survives SwiftData reopen).
- shouldAddStoreAsynchronously = false makes loadPersistentStores synchronous, no race on loadFailed flag.
- No migration-option gap — schema already matches live SwiftData model via NSManagedObjectModel interop.
- Entity/property names match live @Model declarations.

## Recommendation priority
CRITICAL (existingObject error-conflation, line 41) has a real path to deleting a legitimate user log entry; HIGH (silent try? on remove, line 32) is most likely to convert a Core Data hiccup into a full app launch crash-loop.
