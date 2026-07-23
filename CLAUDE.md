# Onigiri — agent notes

Personal iOS + watchOS calorie/sodium/water tracker. Design + roadmap: `plans/PLAN.md`.

## Repo, docs, license

- ORIGIN is GitHub (github.com/ecliptik/onigiri); Forgejo rides as a second
  push URL on origin, so one `git push` updates both. Fetch comes from GitHub.
- `docs/` IS the GitHub Pages site (marketing index.html + privacy.md +
  showcase/media assets) — anything committed there is published on push.
  Internal design docs live in `plans/`. The user guide lives ONLY in the
  GitHub wiki (onigiri.wiki.git); the privacy policy lives in both (site
  canonical). The site's app screenshots/clips exist in BOTH appearances
  (showcase/light + showcase/dark, media/*.mp4 + *-dark.mp4) and swap with
  the site theme — recapture both when screens change.
- License: PolyForm Noncommercial 1.0.0 since the commit after the v2.2.0
  tag (≤ v2.2.0 remains MIT). Say "source-available", not "open source".
  LICENSE is verbatim PolyForm text — never edit it. External PRs are
  declined by policy (CONTRIBUTING.md) to keep commercial rights clean.

## Build

- `xcode-select` may point at CommandLineTools; prefix Xcode commands with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if so.
- `xcodebuild`/`simctl` fail under the Bash sandbox (temp caches, CoreSimulator XPC) —
  run them with the sandbox disabled.
- The `.xcodeproj` is generated and gitignored — after editing `project.yml`, run `xcodegen generate`.

```sh
xcodegen generate
xcodebuild -project Onigiri.xcodeproj -scheme Onigiri \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build build
  # builds the watch app too (embedded). Do NOT pass CODE_SIGNING_ALLOWED=NO:
  # it strips the HealthKit entitlement; ad-hoc simulator signing needs no team.
cd Packages/OnigiriKit && swift test     # pure-logic tests; ALSO needs the
  # DEVELOPER_DIR prefix or @Model/#Preview macro plugins aren't found.
```

- `OnigiriTests` (app-hosted unit tests) is the Foundation Models eval
  suite for `FoodIntelligence` — golden sets with plausibility gates for
  describe-it, meal names, and label refinement. Opt-in (minutes of
  inference) and self-skipping: it needs `TEST_RUNNER_ONIGIRI_AI_EVALS=1`
  AND an available model (an iOS 26+ simulator works: verified 2026-07-16
  on the 26.5 sim WITH the host Mac's Apple Intelligence off, even though
  macOS-side FoundationModels reported appleIntelligenceNotEnabled — trust
  the suite's own skip/run behavior, and never trust a green run without
  checking for skips). Re-run after ANY prompt
  change in FoodIntelligence.swift and after OS updates (the model moves
  under the app). Thresholds live in `Gate` — set before tuning; change
  them only deliberately, in a commit that says why.

```sh
TEST_RUNNER_ONIGIRI_AI_EVALS=1 xcodebuild -project Onigiri.xcodeproj \
  -scheme Onigiri -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath build test -only-testing:OnigiriTests
```

- Commits are GPG-signed: run `git commit` with the sandbox disabled (gpg needs
  `~/.gnupg`). If it fails with "Operation cancelled", the passphrase cache
  expired and pinentry can't prompt from the agent shell — ask the user to run
  `! gpg --clearsign -o /dev/null <<< test` to prime gpg-agent, then retry.

## Deploying to devices

- **Repeated watch install failures (CoreDeviceError 4000 / tunnel timeouts)
  with the watch demonstrably awake usually mean the MAC-side daemon is
  wedged, not the watch.** Diagnose with `xcrun devicectl list devices` —
  "Timed out waiting for CoreDeviceService to fully initialize" confirms it.
  Fix: `pkill -f CoreDeviceService` (no sudo needed), wait ~15 s for the
  watch to reach "connecting/connected", then install. Don't send the user
  chasing watch reboots until this is ruled out.
- **If 4000/RemotePairingError-1001 persists past the daemon reset (watch
  "available (paired)", BT on, VPN exonerated): keep making contact and
  POLL.** The watch's "preparation errors" state clears with repeated
  attempts; once the error shifts to "Device is busy (Connecting…)", loop
  `devicectl list devices` every ~10 s until the state reads "connected"
  (it bounces available↔connecting↔connected) and build+install in that
  window. A patience loop succeeds where one-shot attempts time out
  (2026-07-11: ~an hour of identical failures, then connected on poll 7).
  ATTEMPT THE INSTALL every round, don't just watch the state: a loop
  that only polled `list devices` sat at "available (paired)" for 20
  rounds, while a loop that ran `devicectl device install app` each
  round succeeded on attempt 2 after one 3002 (2026-07-20) — the
  install attempt itself is the contact that wakes the channel.
  `IXRemoteErrorDomain code 6` belongs to the same retry-through family
  (2026-07-21: five of those + one network timeout, then success on
  attempt 7). deploy-phone.sh runs this loop itself now — and never
  gates the watch on a one-shot `list devices` (a not-yet-enumerated
  watch read as "unreachable" and got silently skipped).
- **Watch discovery requires Mac BLUETOOTH ON.** Two days of debugging
  (reboots, re-pairing, trust resets, cache wipes, VPN toggles) and the watch
  never appeared in Xcode/devicectl until the Mac's Bluetooth was enabled —
  the Mac↔watch developer channel bootstraps over BT/AWDL. Check this FIRST.
- Address the watch by ID, not display name (the curly apostrophe matches
  neither tool): xcodebuild wants the hardware UDID, devicectl wants the
  CoreDevice identifier. Both live in scripts/local-devices.env (gitignored;
  copy the .example).

- `scripts/deploy-phone.sh` builds and installs on BOTH the configured iPhone and the
  watch (override with `DEVICE_NAME=…` / `WATCH_BUILD_ID=…` / `WATCH_INSTALL_ID=…`).
  Run weekly — free-team provisioning expires after 7 days. Works over the
  network tunnel; phone and watch must be unlocked (watch on wrist, near the Mac).
- To verify a device install actually runs: `devicectl device process launch
  --console <bundle id>` prints crash reasons (e.g. SwiftData fatals) that never
  reach any log file. Requires the phone unlocked.

## Simulator automation notes

- XCUITest can drive springboard (`XCUIApplication(bundleIdentifier: "com.apple.springboard")`)
  for home-screen/widget-gallery flows; coordinate clicking via osascript/cliclick is
  unreliable for small controls. Health permission sheets have stable `UIA.Health.*`
  accessibility identifiers.
- Pass env vars to UI tests via `TEST_RUNNER_<NAME>=… xcodebuild test …`.
- `testAddWidgetToHomeScreen` (opt-in via `TEST_RUNNER_ADD_WIDGET=1`) installs the
  widget on the simulator home screen.
- The iPhone and Watch sims are PAIRED and share Health data — erase BOTH before
  running the flow test, or seeded totals will be off (`simctl erase <both udids>`).
  Same for the iPad sim: every `--seed-sample-data` launch ADDS samples, so after
  a few QA runs the flow test's total assertions fail on stale data — erase first.
- UI-test capture runs leave the sim in their last orientation; tests that
  assume portrait must set `XCUIDevice.shared.orientation` themselves (the flow
  and QA tests now do).
- Watch-window clicks need the window focused first (click its title bar); clicks
  silently stop landing after sheets open — relaunch the watch app to recover.
- The iOS 26.5 sim can't exercise Differentiate Without Color: the Settings
  toggle is inert to synthetic touch (as is the whole Settings switch layer)
  and writing the com.apple.Accessibility plist key changes nothing — verify
  DWC-gated UI on a device (done 2026-07-20). Synthesized taps also can't
  invoke a SwiftUI .accessibilityAction (only real VoiceOver's AXActivate
  can), so those need on-device VoiceOver too.
- Verifying scenePhase-transient UI (the PrivacyShield): single screenshots
  never catch it — record video through the background/foreground cycle and
  extract distinct frames (`ffmpeg -vsync vfr`). A constant-fps dump pads
  duplicates and LIES about what was on screen (looked like the sheet stayed
  visible; the VFR re-extraction showed the shield frame). 2026-07-20.
- Seeding app-group defaults from a test script: `simctl spawn <udid>
  defaults write group.com.ecliptik.Onigiri …` writes the sim's UNSANDBOXED
  root prefs — the sandboxed app never sees it. Write the real container
  plist instead: `data/Containers/Shared/AppGroup/<UUID>/Library/Preferences/
  group.com.ecliptik.Onigiri.plist` (pass the path minus `.plist` to
  `defaults write`, app terminated first). Cost a smoke-test cycle 2026-07-21.
  AND run that `defaults write` via `simctl spawn <udid>`, not the host: a
  host-side write to the same path landed in the file but the app still read
  stale values — the sim's own cfprefsd had the domain cached and served its
  copy. Spawning defaults inside the sim goes through that daemon (2026-07-22).

## SwiftData landmines (each cost a debugging session)

- Every relationship needs an explicit inverse. Without one, deleting the target
  leaves a dangling reference, and SwiftData KILLS THE PROCESS ("backing data
  could no longer be found") on the next property access — the app crash-looped
  at launch because the watch-sync push computes meal totals.
- A SwiftData-level repair can't fix that state (inspecting the reference traps
  too). `LibraryMaintenance.repairStore(at:)` opens the store with Core Data
  first — `objectIDs(forRelationshipNamed:)` reads references without firing
  faults — and must set `NSPersistentHistoryTrackingKey` or the store mounts
  read-only and the save silently fails.
- With an inverse declared, both sides must be inserted into the context before
  linking (`MealItem(food:)` traps on never-inserted foods) — relevant in tests.
- In tests, keep the `ModelContainer` alive for the test body; returning just a
  context from a helper deallocates the container and every operation traps.
- SwiftUI: multiple chained `.sheet` modifiers on one view compete (consolidate
  into one `.sheet(item:)`); a Bool "request" flag that can be set while no
  onChange observer exists goes permanently dead (true→true never fires) — use
  a consumable Optional checked on change, appear, and foreground.
- Two dismissal races, each a silent field failure (both 2026-07-22):
  swapping a `.sheet(item:)` binding synchronously inside a closure the
  presented sheet follows with its own `dismiss()` tears the NEW sheet down
  with the old (defer the swap one turn — `Task { }` — as the label and
  known-barcode handoffs now do); and List sections under `.searchable` get a
  transient onDisappear/onAppear pair (@State intact) when the keyboard
  dismisses, so an onDisappear that cancels work needs an onAppear that
  resumes it, or the section wedges in its in-flight state forever.

## Conventions

- Shared models/logic go in `Packages/OnigiriKit`, pure and unit-tested where possible.
  EXCEPTION — AppIntents: intent/entity/AppEnum types live in `SharedIntents/`,
  compiled INTO each target that exposes them (app, widget extension, watch app
  — see project.yml), NEVER in the kit. On-device linkd rejects SPM-delivered
  App Shortcuts metadata (`aggregateMetadataIsEmpty`, FB13281659) and the app
  silently never registers with Siri/Shortcuts; the 2.1 move into the kit broke
  registration invisibly for months (2026-07-16 evening). Pure logic the
  intents call (e.g. `StatusPhrasing`) stays in the kit with its tests. If
  intents ever fail with Shortcuts "internal error" while the app builds
  clean, check `log collect` for linkd `Failed to instantiate type … by name`
  (stale mangled name ⇒ delete app + reinstall re-registers; pull a backup
  out via devicectl FIRST — Documents/Backups dies with the container).
- HealthKit is the log store (food/sodium/water samples); SwiftData holds only the
  library (foods, meals, goals). Do not add a second source of truth for logs.
  The meal slot (Breakfast/…) rides in correlation metadata `OnigiriMealCategory`;
  entries without it infer the slot from time of day (`FoodCategory.slot(for:)`).
  The portion count rides in `OnigiriQuantity` (absent = 1) — log writes store
  multiplied totals PLUS this key, and the edit sheet divides totals by it to
  recover the per-portion basis, so "3 hot dogs" edits as 3, not one triple
  serving. A logged MEAL's composition rides in `OnigiriMealItems`
  (JSON [LoggedMealItem], per-portion kcal, snapshotted at log time —
  never resolved from the library, which lies after meal edits); absent =
  plain food or pre-feature log (no meal mark, no Contains section — by
  design). Any new log/re-log path must carry BOTH keys through or edits
  regress to 1 and history silently loses its breakdown.
- Free personal team: no iCloud/CloudKit entitlements; watch↔phone library sync is
  WatchConnectivity, log sync is HealthKit's own.
- Unit preferences (Settings → Units): display/entry-only. Storage is ALWAYS
  canonical — lb, US fl oz, sodium mg — in HealthKit, SwiftData, WatchSync,
  and backups; `WeightUnit`/`WaterUnit`/`SodiumUnit` (kit, UnitPreferences.swift)
  convert at the UI boundary and any new weight/water/sodium readout must go
  through them. Status/color/validation math stays canonical (the sodium
  near-limit band is an absolute 300 mg). "auto"/absent = follow region
  (sodium resolves via an EU/UK/EFTA region list, NOT measurementSystem —
  Australia is metric but labels sodium in mg). The three keys ALWAYS ride
  the watch sync with an explicit "auto" (an absent key would leave a stale
  explicit choice alive on the watch). Siri's LogWaterIntent parameter stays
  ounces by design; only its reply converts.
- OpenFoodFacts: the search index has NO nutrition fields — search rows lazily
  fetch the full product per barcode to show kcal/serving.
- Label scanning is the third door beside barcode and text search, and
  it shares ONE camera with barcodes: `ScanSheet` ("Scan Barcode or
  Nutrition Label" — the user's copy, one row on Foods, the Log sheet,
  and the blank food form) runs the live barcode scanner with a shutter
  button whose still goes to `LabelScan` (kit) — Vision OCR, `.accurate`,
  language correction OFF (correction mangles "0g" → "Og") — into the
  pure, fixture-tested `LabelParser`. Keep the request configuration in
  `LabelScan.swift` and `scripts/dump-label-ocr.swift` identical; capture
  new parser fixtures with that script, never by hand-transcribing. On
  iOS 26 the documents-request table branch runs first; real photos
  produce tables, rendered label graphics don't, so the geometry parser
  is a load-bearing fallback, not legacy. Foundation Models code lives
  ONLY in `Onigiri/Models/FoodIntelligence.swift` (the kit never imports
  it); every AI affordance hides behind `FoodIntelligence.isAvailable`
  and every model failure falls back silently to the deterministic path.
- Text search can route to USDA FoodData Central instead (Settings →
  Online Database; user-supplied api.data.gov key, device-local). FDC rows
  carry `fdc:{fdcId}` in the barcode slot and arrive with nutrients inline
  (no lazy fetch, no weeding). The FDC search endpoint must be POST — GET
  400s on the `Survey (FNDDS)` dataType parens. Barcode scans are always
  OpenFoodFacts.
- ALL online-search surfaces (Foods, Log sheet, and the food form's
  inline database search) render the shared `OnlineResultsSection` —
  a separate `FoodSearchSheet` with its own drifting list existed until
  2026-07-13. Keep it that way: search behavior changes go in the
  shared section only. Search fields are the STANDARD system
  `.searchable` (bottom placement) everywhere — the user vetoed custom
  bars and auto-focus; the scanner is a labeled list row (ScanRowLabel),
  never a toolbar icon.
