# Storage Audit — Onigiri (2026-07-16)

## Summary
- CRITICAL: 0, HIGH: 0, MEDIUM: 0, LOW: 1
- Health: SAFE

## Storage Map
- Locations in use: `Documents/Backups/` (JSON library safety-net backups only) and App Group container `group.com.ecliptik.Onigiri` (shared SwiftData store + shared UserDefaults). Keychain holds the FDC API key. No Caches/, Application Support/, tmp/, or iCloud Drive usage anywhere.
- Backup-exclusion discipline: N/A — the only file-system writes (Documents/Backups) are backed up by design (intentional user-visible safety net); no regenerable/cache content exists that would need isExcludedFromBackup.
- FDC key: confirmed in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, legacy-UserDefaults migration with cleanup — no regression.
- App Group used correctly for widget/App Intents access to library + settings.

## Issues by Severity

### LOW — Missing explicit FileProtectionType on the library backup write
**File**: `Onigiri/Models/BackupService.swift:44`
**Issue**: `try data.write(to: url, options: .atomic)` sets no explicit FileProtectionType (default `.completeUntilFirstUserAuthentication`). Backup payload includes goal/weight data (health-adjacent, not a credential).
**Impact**: Low — not a secret, default protection already encrypts at rest except pre-first-unlock boot windows.
**Fix** (optional hardening): `try data.write(to: url, options: [.atomic, .completeFileProtection])`

## Phase 3 Completeness Checklist — all passed
- Tokens/credentials in Keychain: yes, no regression.
- App Group for extensions: yes, SwiftData store + UserDefaults suite both in group.com.ecliptik.Onigiri.
- Bounded-size cache policy: yes — BackupService.prune() keeps only 5 backups; DeficitTargetHistory caps at 400 entries.
- Temp files: N/A, no NSTemporaryDirectory usage.
- Orphan files on entity delete: N/A, no file/image attachments on Food/Meal models.
- iCloud Drive: N/A, no iCloud entitlements (intentional per free-team constraint).
- Migration path for storage layout changes: LibraryExport/LibraryTransfer explicitly version the export format with documented fallback semantics.

## Recommendations
1. No CRITICAL/HIGH issues.
2. Optional: add `.completeFileProtection` to BackupService.swift:44 write for defense-in-depth.
3. If the app ever adds cached network images or downloaded label-scan photos, revisit this audit — first Caches/backup-exclusion surface it doesn't currently have.
