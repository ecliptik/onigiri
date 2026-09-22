import Foundation

#if DEBUG
/// Appends one timestamped line to Documents/visual-intelligence-debug.log
/// — pull with:
/// `xcrun devicectl device copy from --device <UDID> --domain-type
/// appDataContainer --domain-identifier com.ecliptik.Onigiri --source
/// Documents/visual-intelligence-debug.log --destination <local path>`.
/// No live console access to this device from the agent shell — same
/// problem the menu-parser's `debugScanned`/`scanNote` solves
/// (CLAUDE.md), same fix. Deliberately OUTSIDE the `canImport
/// (VisualIntelligence)` gate below despite the name: `ContentView.swift`'s
/// `drainMenuInbox()` (simulator-buildable, no VisualIntelligence
/// dependency at all) needs to call this too, to trace the receiving
/// half of the hand-off, not just the sending half.
nonisolated func viDebugLog(_ line: String) {
    let url = URL.documentsDirectory.appendingPathComponent("visual-intelligence-debug.log")
    var lines = (try? String(contentsOf: url, encoding: .utf8))?
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map(String.init) ?? []
    lines.append("[\(Date())] \(line)")
    // Uncapped, this grew without bound over a long debugging session —
    // same cap WidgetBurnGate's journals use (health-check audit,
    // 2026-09-14).
    let cap = 500
    if lines.count > cap { lines.removeFirst(lines.count - cap) }
    try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
}
#endif

// VisualIntelligence.framework does not exist in the iOS SIMULATOR SDK
// at all (Xcode 27.0 GA, verified 2026-09-14 — a real build failure,
// "Unable to resolve module dependency: 'VisualIntelligence'", not a
// runtime/@available gate) — only on real devices. `#if canImport`,
// not `@available`: an availability check is a RUNTIME gate on an API
// that still compiles everywhere; this is a compile-time gate on a
// module that doesn't exist for this build target at all. Without it
// the standard simulator build in CLAUDE.md fails outright.
#if canImport(VisualIntelligence)
import AppIntents
import CoreImage
import CoreVideo
import OnigiriKit
import UIKit
import VisualIntelligence

// Visual Intelligence: point Camera Control or a screenshot at a food
// and go straight to the SAME photo-read cascade a shared screenshot
// already uses (`FoodImageReader`'s OCR → LabelParser → refine →
// identify, via `ShareInbox` + `ContentView.drainMenuInbox()`), never
// a new door.
//
// **Deliberately NOT a library search** (redesigned 2026-09-14, the
// user's own call after watching it fail on a real device). Visual
// Intelligence's classifier labels are too generic to identify a
// specific product — a real can of "Bravo Mango Yerba Mate" produced
// the single label "food", nothing more — so matching those labels
// against saved foods by name almost never finds anything real. The
// thing that DOES work, verified on device, is running the actual
// photo through Onigiri's own OCR/AI reader — so that's what this
// offers directly, one tap away, instead of a guessing game.
//
// No watchOS entry point exists for Visual Intelligence, so unlike
// `LogFoodIntent`/`LogMealIntent` this lives in the APP target, not
// `SharedIntents/` — that directory's whole reason to exist is
// compiling once into both the phone and watch targets, which doesn't
// apply here. `FoodEntity` (SharedIntents/LogIntents.swift) is visible
// without an import: SharedIntents compiles directly into this
// target's module, same as DescribeFoodIntent relies on for
// `FoodIntelligence`.

/// The one and only result this feature ever offers — a placeholder,
/// not a real library item. Its own dedicated `AppEntity`/`EntityQuery`
/// pair, NOT a fabricated `FoodEntity`: reusing `FoodEntity` (tried
/// first) broke on a real device — tapping it re-resolves the entity
/// through `FoodEntityQuery`, which only knows about REAL App-Group
/// foods, so a made-up ID it's never seen fails resolution ("An error
/// occurred while opening this result", 2026-09-14). A dedicated type
/// also means this can carry its own icon without touching the shared
/// `FoodEntity` display used by actual foods elsewhere in the app.
@available(iOS 26.0, *)
struct IdentifyPhotoEntity: AppEntity {
    /// Changed suffix (2026-09-14): the FIRST version of this
    /// placeholder (a fabricated `FoodEntity`, since replaced) used the
    /// bare `.identify` ID with NO image at all. If Visual
    /// Intelligence/Spotlight caches entity display metadata by ID —
    /// unconfirmed, but the symbol name and initializer both check out
    /// against the real SDK, so a stale cache is the next most likely
    /// explanation for an icon that still doesn't render — reusing that
    /// exact ID could keep serving the old, image-less record. A fresh
    /// ID forces a fresh registration either way.
    static let placeholderID = "onigiri.visual-intelligence.identify.v2"
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Identify from Photo"
    static let defaultQuery = IdentifyPhotoEntityQuery()

    var id: String { Self.placeholderID }

    /// The user's choice among onigiri/AI-themed icon options
    /// (2026-09-14) — sparkle + search reads as "identify/scan", the
    /// closest system glyph to what this result actually does.
    ///
    /// A rendered BITMAP, not `.init(systemName:)` — the symbol name is
    /// real (verified against the actual SF Symbols catalog) and the
    /// initializer matches the real SDK, but on device the icon slot
    /// stayed empty through two rounds of fixes (a fresh entity ID, an
    /// explicit `isTemplate: false`). Whatever the cause, resolving an
    /// SF Symbol BY NAME inside Visual Intelligence's own results UI
    /// isn't working; rendering the exact same glyph to a PNG ourselves
    /// and handing over the bytes sidesteps that resolution step
    /// entirely and is a genuinely different code path to test.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "Identify from Photo",
            subtitle: "Read this with Onigiri's photo scanner",
            image: Self.renderedIcon
        )
    }

    /// Renders "sparkle.magnifyingglass" to a PNG at load time, once —
    /// see the doc comment above for why a rendered bitmap, not
    /// `.init(systemName:)`. Centered on a transparent square canvas,
    /// large enough to stay crisp at whatever size Visual Intelligence
    /// actually displays it. `riceToast` isn't reachable here (an
    /// OnigiriKit SwiftUI Color, not a UIColor asset this target can
    /// name), so a plain system orange stands in for the app's accent.
    private static let renderedIcon: DisplayRepresentation.Image? = {
        let canvas = CGSize(width: 512, height: 512)
        let config = UIImage.SymbolConfiguration(pointSize: 220, weight: .regular)
        guard let symbol = UIImage(systemName: "sparkle.magnifyingglass", withConfiguration: config)?
            .withTintColor(.systemOrange, renderingMode: .alwaysOriginal)
        else { return nil }
        let rendered = UIGraphicsImageRenderer(size: canvas).image { _ in
            let origin = CGPoint(x: (canvas.width - symbol.size.width) / 2,
                                  y: (canvas.height - symbol.size.height) / 2)
            symbol.draw(at: origin)
        }
        guard let data = rendered.pngData() else { return nil }
        return DisplayRepresentation.Image(data: data, isTemplate: false)
    }()
}

@available(iOS 26.0, *)
struct IdentifyPhotoEntityQuery: EntityQuery {
    init() {}

    func entities(for identifiers: [String]) async throws -> [IdentifyPhotoEntity] {
        identifiers.contains(IdentifyPhotoEntity.placeholderID) ? [IdentifyPhotoEntity()] : []
    }
}

/// Converts a Visual Intelligence pixel buffer to JPEG and deposits it
/// into `ShareInbox`, deduped by content hash. Shared by the query
/// (which deposits eagerly, so a single tap on its one result opens
/// straight to the estimate) and `FoodVisualSearchMoreResultsIntent`
/// (kept as a second path to the same place, in case Apple's system
/// offers it independently of what the query returns).
///
/// The DEDUP matters on its own, independent of who calls it: Visual
/// Intelligence invokes both the query and the more-results intent
/// several times per single user action (5-6 times within ~2 seconds,
/// measured on device, cause unconfirmed) — without it, each redundant
/// call deposited its own copy, and `ShareInbox` only drains ONE per
/// app foreground, so the SAME estimate screen kept reappearing on
/// every later app open until the backlog drained.
@available(iOS 26.0, *)
enum VisualIntelligencePhotoHandoff {
    @MainActor
    private static var lastDeposit: (hash: Int, at: Date)?

    /// `async`, not `@MainActor`: `IntentValueQuery.values(for:)`
    /// (the query's call site) runs off the main actor, unlike
    /// `FoodVisualSearchMoreResultsIntent.perform()` (explicitly
    /// `@MainActor`) — this needs to be callable from both, so it hops
    /// to the main actor only for the shared `lastDeposit` state rather
    /// than requiring its caller's isolation to match.
    @discardableResult
    static func depositIfNew(_ pixelBuffer: CVReadOnlyPixelBuffer?) async -> Bool {
        guard let pixelBuffer, let data = jpegData(from: pixelBuffer) else {
            #if DEBUG
            viDebugLog("photoHandoff: no pixel buffer, or JPEG conversion failed")
            #endif
            return false
        }
        let hash = data.hashValue
        let isDuplicate = await MainActor.run { () -> Bool in
            if let last = lastDeposit, last.hash == hash, Date().timeIntervalSince(last.at) < 10 {
                return true
            }
            lastDeposit = (hash, Date())
            return false
        }
        guard !isDuplicate else {
            #if DEBUG
            viDebugLog("photoHandoff: duplicate of the last deposit (same image, <10s ago) — skipped")
            #endif
            return false
        }
        let deposited = ShareInbox.deposit(data, name: "visual-intelligence.jpg", kind: .image)
        #if DEBUG
        viDebugLog("photoHandoff: deposited=\(deposited ?? "NIL — deposit failed") bytes=\(data.count)")
        #endif
        return deposited != nil
    }

    private static func jpegData(from pixelBuffer: CVReadOnlyPixelBuffer) -> Data? {
        pixelBuffer.withUnsafeBuffer { buffer -> Data? in
            let ciImage = CIImage(cvPixelBuffer: buffer)
            guard let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent) else {
                return nil
            }
            return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.85)
        }
    }
}

/// One entity, always: "Identify from Photo". Deposits the photo
/// immediately (queries get `SemanticContentDescriptor.pixelBuffer`
/// too, not just the more-results intent), so by the time the user
/// taps this single result, the image is already waiting — tapping it
/// (`OpenIdentifyPhotoIntent`, below) just needs to bring the app
/// forward, and `ContentView.drainMenuInbox()`'s existing foreground
/// hook does the rest, presenting the estimate exactly as a shared
/// screenshot would. A real, if rare, name match is no longer
/// attempted here — it needs the platform to hand over more than
/// "food", which it doesn't.
@available(iOS 26.0, *)
struct FoodVisualSearchQuery: IntentValueQuery {
    init() {}

    func values(for input: SemanticContentDescriptor) async throws -> [IdentifyPhotoEntity] {
        guard input.pixelBuffer != nil else {
            #if DEBUG
            viDebugLog("query: no pixel buffer, nothing to offer")
            #endif
            return []
        }
        await VisualIntelligencePhotoHandoff.depositIfNew(input.pixelBuffer)
        #if DEBUG
        viDebugLog("query labels=\(input.labels) pixelBuffer=true — offering the Identify placeholder")
        #endif
        return [IdentifyPhotoEntity()]
    }
}

/// Visual Intelligence's own build-time requirement, not new Siri
/// vocabulary: Apple's `appintentsmetadataprocessor` refuses to export
/// ANY `IntentValueQuery` whose result types aren't each associated
/// with an `OpenIntent` — "not openable" is a HALTING build error,
/// caught only by attempting a real device build (the simulator SDK
/// has no VisualIntelligence.framework to trigger it against).
///
/// The tap itself does almost nothing: the photo was already deposited
/// by the query above, so all this needs to do is bring the app
/// forward — `openAppWhenRun` handles that, and the existing foreground
/// hook (`ContentView.drainMenuInbox()`) takes it from there.
@available(iOS 26.0, *)
struct OpenIdentifyPhotoIntent: OpenIntent {
    static let title: LocalizedStringResource = "Identify from Photo"
    /// Not trusted to `OpenIntent`'s own default — the same lesson
    /// `FoodVisualSearchMoreResultsIntent` (below) learned the hard way
    /// for a different protocol's `openAppWhenRun`.
    static var openAppWhenRun: Bool { true }
    @Parameter(title: "Result") var target: IdentifyPhotoEntity

    init() {}
    init(target: IdentifyPhotoEntity) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if DEBUG
        viDebugLog("OpenIdentifyPhotoIntent called")
        #endif
        return .result()
    }
}

/// The "More Results" hand-off — kept as a second path to the exact
/// same place the query's single result already leads, in case Apple's
/// system offers this affordance independently of what the query
/// returns. Both go through `VisualIntelligencePhotoHandoff`, so
/// whichever the user actually taps, the dedup guard means only one
/// copy of the photo ever queues up.
///
/// **`criteria`/`searchScopes` are REQUIRED, not decorative** — found
/// on a real device, not in any doc (2026-09-14). Apple's own bundled
/// tutorial shows this intent conforming to a protocol named
/// `VisualIntelligenceSearchIntent`, which DOES NOT EXIST in the
/// Xcode 27 SDK (grepped — zero hits). The schema's real name,
/// `ShowVisualSearchResultsInAppIntent`, is the actual clue: the macro
/// attaches `ShowInAppSearchResultsIntent`, whose contract is
/// `associatedtype Criteria: SearchCriteria` + `criteria` + `searchScopes`
/// — nothing about `SemanticContentDescriptor` at all. Without `criteria`
/// declared, the app built and even ran (no compile error — the schema
/// macro apparently synthesizes SOMETHING to satisfy the protocol without
/// it), but on device the system called `perform()` repeatedly for one
/// tap and never brought the app forward once — caught only via the
/// Documents-log trick above, since there is no live console access to
/// this device from the agent shell. `StringSearchCriteria` gets
/// `searchScopes` for free from a stdlib extension (`Criteria ==
/// StringSearchCriteria` → `[.general]`).
@available(iOS 26.0, *)
@AppIntent(schema: .visualIntelligence.semanticContentSearch)
struct FoodVisualSearchMoreResultsIntent {
    @Parameter(title: "Semantic Content")
    var semanticContent: SemanticContentDescriptor
    /// Required by `ShowInAppSearchResultsIntent`. Unused by `perform()`
    /// below — this intent's real input is the photo, not a typed term
    /// — but the protocol has no bare "criteria-less" form. Optional:
    /// Apple's own `appintentsmetadataprocessor` refuses a non-Optional
    /// parameter that the `.visualIntelligence.semanticContentSearch`
    /// schema doesn't itself define ("Intent parameters must be optional
    /// when not defined by the AppSchemaIntent" — a real build error,
    /// found only via a device build; the simulator SDK can't run this
    /// check at all).
    @Parameter(title: "Search Criteria")
    var criteria: StringSearchCriteria?

    /// Explicit, not trusted to the protocol's own default: the
    /// `criteria`/`searchScopes` fix satisfied Apple's BUILD-time
    /// validator but alone changed nothing observed on device.
    /// CONFIRMED the missing piece (2026-09-14, real device test after
    /// adding this): the app now opens straight into the estimate
    /// screen, reading the photographed can correctly ("Yerba Madre
    /// Organic Yerba Mate - Mango"). Apple documents no default value
    /// for this property anywhere found — it had to be forced.
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if DEBUG
        viDebugLog("moreResults called, pixelBuffer=\(semanticContent.pixelBuffer != nil)")
        #endif
        await VisualIntelligencePhotoHandoff.depositIfNew(semanticContent.pixelBuffer)
        return .result()
    }
}
#endif
