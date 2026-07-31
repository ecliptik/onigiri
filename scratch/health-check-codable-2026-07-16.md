# Codable Audit — Onigiri (2026-07-16)

## Summary
- CRITICAL: 0, HIGH: 0, MEDIUM: 3, LOW: 2
- Health: HARDENING NEEDED

## Serialization Architecture Map
- LibraryExport.encoded()/decode() explicitly set .iso8601 on both encoder and decoder (consistent). WatchSync uses default JSONEncoder()/JSONDecoder() with no explicit date strategy for SyncedGoal.targetDate at 4 independent call sites — self-consistent only by coincidence.
- 3 manual init(from:)/encode(to:) implementations: SearchHit (OFF, flexible type coercion), OFFNutriments (OFF, flexible type coercion + dynamic micronutrient keys), NutrientValues (WatchSync, versioned optional fields).
- No legacy JSONSerialization calls in these files; [String: Any] in WatchSync is required WCSession API bridging, not an anti-pattern.

## Issues by Severity

### MEDIUM — Discarded DecodingError context in FDC parsing
**File**: `Packages/OnigiriKit/Sources/OnigiriKit/FoodDataCentralClient.swift:256-262, 282-288`
**Issue**: `parseSearch`/`parsePortions` catch the underlying DecodingError and replace it with generic `FoodDataCentralError.badResponse`, with zero logging anywhere in the file. Compare OpenFoodFactsClient, which lets the original DecodingError propagate.
**Impact**: A future FDC schema change is undiagnosable from field logs.
**Fix**: Log the DecodingError (Logger.error) before rethrowing as badResponse in both functions.

### MEDIUM — Silent field drop: lastUsedAt not preserved by LibraryExport
**File**: `Packages/OnigiriKit/Sources/OnigiriKit/LibraryExport.swift:8-37, 49-68`, `Onigiri/Models/LibraryTransfer.swift:14-35`
**Issue**: Food.lastUsedAt/Meal.lastUsedAt (drives Favorites/recency ordering on phone+watch) is not included in FoodItem/MealDef export structs; LibraryTransfer.export never reads it. Every backup/restore silently resets recency ordering to createdAt = .now for every reimported item.
**Impact**: Real, user-visible regression after restore — Favorites/recents ordering scrambled with no error surfaced.
**Fix**: Add `lastUsedAt: Date?` to FoodItem/MealDef, populate on export, apply on import (fallback .now for new items).

### MEDIUM — WatchSync Date strategy consistency is implicit, not enforced
**File**: `Packages/OnigiriKit/Sources/OnigiriKit/WatchSync.swift:182-183, 195, 233, 290`
**Issue**: SyncedGoal.targetDate encoded/decoded at 4 independent call sites, all bare JSONEncoder()/JSONDecoder() with no explicit date strategy — agree today only by coincidence (all default to .deferredToDate). No shared encoder/decoder instance.
**Impact**: A future one-line change to any single site would silently corrupt every targetDate round-trip with no compile-time/runtime signal (decode error path is swallowed by try?).
**Fix**: Centralize a single configured `WatchSync.encoder`/`WatchSync.decoder` static so all four sites can't drift independently.

### LOW — LibraryTransfer.importData catch discards structured decode detail
**File**: `Onigiri/Models/LibraryTransfer.swift:131-133`
**Issue**: `catch { return "Import failed: \(error.localizedDescription)" }` — DecodingError.localizedDescription is generic, no keyNotFound/typeMismatch context logged.
**Fix**: Log full error via Logger before returning the friendly user-facing string.

### LOW — FDC numeric slot fallback silently zeros malformed values (informational)
**File**: `Packages/OnigiriKit/Sources/OnigiriKit/WatchSync.swift:259-267`
**Issue**: `defaults.set(Double(value) ?? 0, forKey: key)` — mostly harmless since 0 is already treated as "unset, use default" elsewhere (LibraryModels.swift:237-244). Documentation note only.

## Recommendations
1. No CRITICAL issues — nothing here handles payment/auth/injection-risk data.
2. Short-term: add logging to FDC parse catch blocks; add lastUsedAt to LibraryExport; centralize WatchSync encoder/decoder.
3. Long-term: log full error (not just localizedDescription) in LibraryTransfer.importData; document the 0-is-safe-sentinel convention in WatchSync.
