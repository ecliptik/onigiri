# Security & Privacy Audit — Onigiri (2026-07-16)

## Security & Privacy Map
- **Privacy Manifest**: MISSING entirely. No `PrivacyInfo.xcprivacy` found anywhere in the repo (checked all 4 targets: Onigiri, OnigiriWatch, OnigiriWidgets, OnigiriWatchWidgets).
- **Credential storage**: Keychain, correctly. `Packages/OnigiriKit/Sources/OnigiriKit/LibraryModels.swift:303-377` stores the FDC API key via `kSecClassGenericPassword` with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, and auto-migrates/clears any legacy plaintext `UserDefaults` copy on first read (`fdcAPIKey` getter, lines 323-333). This confirms the CLAUDE.md/commit history claim — the migration holds.
- **Network surface**: HTTPS-only. No `http://` literals found; both `FoodDataCentralClient` (`https://api.nal.usda.gov/...`) and OpenFoodFactsClient use HTTPS. No `NSAppTransportSecurity`/`NSAllowsArbitraryLoads` keys in any Info.plist (default ATS enforced).
- **Logging discipline**: Clean. `Logger` calls log only counts/enum-like values (`item.type, privacy: .public` in `Onigiri/Models/QuickActions.swift:55,70`) or `error.localizedDescription`. No credential, token, or raw HealthKit sample values found in any `print`/`Logger`/`NSLog` call.
- **ATT usage**: Absent — no `ATTrackingManager`/`requestTrackingAuthorization` calls anywhere, and correspondingly no `NSUserTrackingUsageDescription` in Info.plist. Consistent (no tracking, so no description needed).
- **Export compliance**: No `ITSAppUsesNonExemptEncryption` key in Info.plist, and no `CryptoKit`/`CommonCrypto` imports found anywhere — no custom encryption in use, so this is currently a non-issue (standard HTTPS/Keychain use is exempt), but the declaration should still be set explicitly for a clean submission.
- **Required Reason APIs actually in use** (confirmed by grep + Read): `UserDefaults` (pervasively, via `SharedStore.defaults`, an App Group suite) and File Timestamp APIs (`resourceValues(forKeys: [.contentModificationDateKey])` in `Onigiri/Models/BackupService.swift:59-63,72-73`). Both require declaration and neither is declared, because no manifest file exists at all.
- **Entitlements**: HealthKit + App Group only, across all 4 targets — no unused/over-broad entitlements (no iCloud, no Keychain-sharing, no HealthKit-clinical-records).

## Summary
- CRITICAL: 1
- HIGH: 1
- MEDIUM: 1
- LOW: 1

## App Store Readiness: NOT READY

Reason: missing Privacy Manifest with two Required Reason API categories in active use (`UserDefaults`, `File Timestamp`) is a guaranteed App Store Connect rejection since May 2024.

## Issues by Severity

### CRITICAL — Missing Privacy Manifest with Required Reason APIs in use
**File**: repo-wide (no `PrivacyInfo.xcprivacy` in `Onigiri/`, `OnigiriWatch/`, `OnigiriWidgets/`, `OnigiriWatchWidgets/`, or `Packages/OnigiriKit/`)
**Evidence**:
- `UserDefaults` used pervasively via `SharedStore.defaults` (App Group suite), e.g. `Packages/OnigiriKit/Sources/OnigiriKit/LibraryModels.swift:495` and 40+ `@AppStorage` call sites across `Onigiri/Views/*.swift` and `OnigiriWatch/*.swift`.
- File Timestamp API (`URL.resourceValues(forKeys: [.contentModificationDateKey])`) in `Onigiri/Models/BackupService.swift:59-63` and `:72-73`.
**Issue**: Since May 2024, App Store Connect statically scans binaries for Required Reason API symbol usage and rejects builds lacking a matching `NSPrivacyAccessedAPITypes` declaration with a valid reason code.
**Impact**: Guaranteed App Store Connect rejection on next submission.
**Fix**: Add `PrivacyInfo.xcprivacy` to the main app target (and to OnigiriKit if it ships as a separate framework bundle) declaring `NSPrivacyAccessedAPICategoryUserDefaults` (reason `CA92.1`) and `NSPrivacyAccessedAPICategoryFileTimestamp` (reason `C617.1`).

### HIGH — Export compliance declaration absent
**File**: `Onigiri/Info.plist`, `OnigiriWatch/Info.plist`, `OnigiriWidgets/Info.plist`, `OnigiriWatchWidgets/Info.plist`
**Issue**: No `ITSAppUsesNonExemptEncryption` key present in any target's Info.plist. No CryptoKit/CommonCrypto usage found — only standard HTTPS (exempt). Absent the key, App Store Connect prompts for the export compliance questionnaire on every build upload.
**Fix**: Add `ITSAppUsesNonExemptEncryption` = `false` to each Info.plist.

### MEDIUM — FDC API key transmitted as URL query parameter
**File**: `Packages/OnigiriKit/Sources/OnigiriKit/FoodDataCentralClient.swift:145` and `:225`
**Issue**: `components.queryItems = [.init(name: "api_key", value: apiKey)]` places the credential in the URL query string rather than a header. Transport is HTTPS (encrypted in transit); this is dictated by api.data.gov's API contract, not a code choice Onigiri controls.
**Impact**: Low — not exploitable over HTTPS in transit, but increases exposure surface in any logging layer between client and USDA's servers.
**Fix**: No action required today (constrained by third-party API contract); noted for completeness.

### LOW — No snapshot/background obscuring for sensitive screens
**File**: `Onigiri/ContentView.swift:15,77`, `OnigiriWatch/OnigiriWatchApp.swift:14,58`
**Issue**: `scenePhase` is observed but not used to obscure the UI on backgrounding. Onigiri shows calorie/sodium/water logs and body weight trends — moderately sensitive personal health data visible in the App Switcher snapshot.
**Fix**: Optional — add a blur/privacy overlay on `.background` scenePhase transition.

## Things verified clean (no issues found)
- No hardcoded API keys/secrets/tokens (checked AWS/OpenAI/GitHub/PEM patterns — 0 matches).
- FDC API key: confirmed in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, with automatic plaintext-UserDefaults migration and cleanup.
- No HTTP (cleartext) endpoints; no ATS bypass keys in any Info.plist.
- No sensitive data in any print/Logger/NSLog call.
- No ATT usage, so no missing-usage-description risk.
- Entitlements (HealthKit, HealthKit background-delivery, App Group) all exercised by code — no unused/over-broad entitlements.
- No third-party SPM dependencies — no bundled-SDK privacy-manifest gap.
