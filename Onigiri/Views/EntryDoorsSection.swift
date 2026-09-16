import SwiftUI
import OnigiriKit

/// The shared entry door: ONE row, identical on the Log sheet and the
/// Add Food form.
///
/// **AI on**: a compact icon-only camera button beside a "Describe food
/// or meal" text field — two doors in one row (the user, 2026-08-29).
/// The field drives the host's `AIEstimateSection` the same way it
/// always has; only where its query comes from moved. This UNDOES part
/// of an earlier merge (below) on purpose: a describe field lived here
/// once, moved into the bottom `.searchable` field so the screen carried
/// only one text field, and now splits back out — but the bottom field
/// stays search-only this time, so there is still exactly one field per
/// job, just two jobs instead of one.
///
/// **The button and the field draw their OWN chip each**, not one
/// shared row card — a plain `TextField` has no visible bound of its
/// own, so the row's single grouped-list background read as ONE object
/// with a circle floating inside it, button and field blurred together
/// (the user, 2026-08-29: "doesn't look separate from the camera").
/// Giving the field the SAME `.quaternary` chip treatment the button's
/// circle already used makes them read as two controls with a gap
/// between them, not one — and freed from matching the field's own
/// (borderless, row-height) size, the button is free to be as large as
/// the row allows, so it no longer needs to punch above its actual
/// weight to be seen inside a shared card that outsized it either way.
///
/// **The field also drives online lookups now** (2026-08-29): typing
/// shows the AI estimate row AND `OnlineResultsSection` (OpenFoodFacts /
/// USDA) together, in the AI → online order the rest of the app already
/// uses. Both are tap-to-run, never per-keystroke — `TapToEstimateRow`
/// and `OnlineResultsSection`'s own "Search…" button — so combining them
/// under one field costs nothing extra. This is what makes the field's
/// gating below `isAvailable || onlineLookups` rather than `isAvailable`
/// alone: online lookups don't need AI, and hiding the field whenever AI
/// is off would strand them with no way to search.
///
/// **Neither on**: the camera button falls back to the full labeled row
/// (`ScanRowLabel`, "Scan Barcode, Label, or Menu") and the describe
/// field is hidden entirely — nothing behind it works, and a field with
/// nowhere to send its text is a dead end, not a door.
///
/// The camera button carries the SAME accessibility label the row used
/// to show as its visible title ("Scan Barcode, Label, Menu, or Food"),
/// icon-only or not — VoiceOver and `OnigiriUITests.scanRow(in:)` both
/// find it by that label, and it is still one tap to the same scanner.
struct EntryDoorsSection: View {
    /// Scan-door state owned by the host (barcode lookups etc.).
    var scanBusy = false
    /// Host-provided caption under the scan door (barcode/label/photo
    /// provenance) — nil when there's nothing to say.
    var scanCaption: String?
    /// What's typed to describe a food or meal in prose. Owned by the
    /// host so it survives this view's own remounts and so the host can
    /// drive its `AIEstimateSection` from it and clear it after a pick.
    @Binding var describeQuery: String
    let onScan: () -> Void
    /// Keyboard-submit convenience for the online leg only — matches
    /// what the retired bottom `.searchable` field did on
    /// `.onSubmit(of: .search)`. AI stays tap-only (its own button in
    /// `TapToEstimateRow`'s idle phase, one inference per tap on
    /// purpose); typing a description and hitting Return has never
    /// needed to also run inference to feel complete, but online search
    /// did offer a "just search" fast path before. `nil` = no
    /// submit-triggered search — hosts with online lookups off can skip
    /// wiring it.
    var onDescribeSubmit: (() -> Void)?

    /// Matched by the "select all on focus" notification handler in
    /// `FoodFormView` — an in-progress description must not be
    /// select-all'd out from under someone refocusing it, the same
    /// exemption the bottom search field already gets. A SwiftUI
    /// `TextField`'s accessibility identifier rides its bridged
    /// `UITextField`, which is the only handle that notification hands
    /// back.
    static let describeFieldAccessibilityID = "entryDoorsDescribeField"

    /// Whether the describe field has anything to drive — AI, online
    /// lookups, or both. `false` only when neither is on, which is the
    /// one case the field would be a dead end.
    private var describeFieldAvailable: Bool {
        FoodIntelligence.isAvailable || SharedStore.onlineLookups
    }

    var body: some View {
        Section {
            if describeFieldAvailable {
                HStack(spacing: 14) {
                    // 44pt — LogButton's own frame, exactly, so this
                    // row's content height caps at the same place
                    // Water's does and the two pills match (the
                    // user, 2026-08-29). Larger read as its own
                    // control once the field stopped sharing its
                    // card (previous round); this is the same idea
                    // bounded by a second row it now has to agree
                    // with.
                    EntryDoorScanButton(scanBusy: scanBusy, onScan: onScan) {
                        DoorCircleGlyph(systemImage: "camera", diameter: 44, font: .body.weight(.bold))
                    }
                    EntryDoorDescribeField(describeQuery: $describeQuery, onDescribeSubmit: onDescribeSubmit)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        // The SAME fill `DoorCircleGlyph`'s circle uses —
                        // one "control chip" language for both, so they
                        // read as siblings rather than a button floating
                        // inside a field's own row. `.tertiarySystemGroupedBackground`,
                        // not `.quaternary` — the hierarchical material
                        // washed out light on a real device in dark mode
                        // (the user, 2026-08-30, from-device screenshot:
                        // "light mode button leak"); this is a flat,
                        // deterministic system color instead, matching
                        // `DoorCircleGlyph`'s own fix.
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            } else {
                Button(action: onScan) {
                    ScanRowLabel()
                }
                .disabled(scanBusy)
            }

            if scanBusy {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Looking up product…")
                        .foregroundStyle(.secondary)
                }
            }
            if let scanCaption {
                Text(scanCaption)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }
}

/// The camera door's button: glyph + accessibility label + the
/// disabled/action wiring, extracted so the Add Food form's in-list row
/// and the Log sheet's floating bar (`LogSheetDoorBar`,
/// `plans/PLAN-log-sheet-layout.md`, 2026-09-15) can't say something
/// different about what a tap does. Each caller supplies its own
/// rendering of the glyph — the chip circle here, glass there.
struct EntryDoorScanButton<Content: View>: View {
    var scanBusy = false
    let onScan: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        Button(action: onScan) { content() }
            .buttonStyle(.plain)
            .disabled(scanBusy)
            .accessibilityLabel("Scan Barcode, Label, Menu, or Food")
    }
}

/// The describe field itself: sparkle + `TextField` + its accessibility
/// identifier/label + submit wiring, extracted for the same reason as
/// `EntryDoorScanButton` above — `describeFieldAccessibilityID` is what
/// `FoodFormView`'s select-all-on-focus handler matches against, and a
/// second hand-copied field could silently stop matching it. Callers
/// wrap this in their own padding/background; it draws no chrome of its
/// own.
struct EntryDoorDescribeField: View {
    @Binding var describeQuery: String
    var onDescribeSubmit: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            // AI ONLY, not "online lookups can search too" — the
            // sparkle is a promise about what's behind the field, and a
            // plain database search isn't AI (the user, 2026-08-29:
            // "a sparkle... if AI is enabled").
            if FoodIntelligence.isAvailable {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.riceToast)
                    .font(.callout)
            }
            TextField("Describe food or meal", text: $describeQuery)
                .accessibilityLabel("Describe food or meal")
                .accessibilityIdentifier(EntryDoorsSection.describeFieldAccessibilityID)
                .onSubmit { onDescribeSubmit?() }
        }
    }
}

/// The Log sheet's camera + describe door (`plans/PLAN-log-sheet-layout.md`,
/// 2026-09-15): pulled OFF the list-row chip `EntryDoorsSection` still
/// uses in the Add Food form, into its own glass-chrome pill — Liquid
/// Glass on iOS 26+, camera tinted (the app's one primary action per
/// the HIG's "tint one, not everything" rule), describe plain. Shares
/// `EntryDoorScanButton`/`EntryDoorDescribeField` with `EntryDoorsSection`
/// so the glyph, the label, and the accessibility contract can't drift
/// between the two homes — only the surrounding chrome differs.
///
/// PINNED below QuickLogSheet's List via `entryDoorBar` (Style.swift),
/// hidden while searching. It spent part of 2026-09-16 as the list's
/// trailing row instead, to close the empty canvas a short Favorites
/// list leaves above a pinned bar — and was then unreachable on any
/// real library without scrolling to the very end. The user chose
/// pinned with both in hand; `entryDoorBar`'s doc comment has the rest.
struct LogSheetDoorBar: View {
    var scanBusy = false
    @Binding var describeQuery: String
    let onScan: () -> Void
    var onDescribeSubmit: (() -> Void)?

    /// Same rule as the form's chip: a field with nowhere to send its
    /// text is a dead end, not a door.
    private var describeFieldAvailable: Bool {
        FoodIntelligence.isAvailable || SharedStore.onlineLookups
    }

    var body: some View {
        Group {
            if describeFieldAvailable {
                // GlassEffectContainer: glass can't sample glass, and
                // without it the circle and the capsule fight each
                // other at 14pt apart (Liquid Glass guidance). Below
                // the floor there's no glass to coordinate, so a plain
                // HStack does the same job.
                //
                // Camera LEADING, describe field trailing — tried the
                // reverse (the user, 2026-09-16: "the camera button on
                // log is on the right of the search") and it silently
                // broke real barcode scanning: `testBarcodeLookupPrefillsForm`
                // failed twice, reproducibly, with the tap on the camera
                // never opening the scanner at all — no crash, no error,
                // just a no-op. Swapping the two views' ORDER in this
                // HStack was the only change between a passing and a
                // failing run (isolated by testing each independently);
                // the exact mechanism wasn't found (a `GlassEffectContainer`
                // hit-testing quirk when the fixed-size circle trails a
                // flexible-width field is the leading suspect, but
                // unconfirmed) and wasn't worth guessing further at
                // under time pressure. Don't reorder these two without
                // re-running that test on a device — it will not fail
                // loudly.
                if #available(iOS 26.0, *) {
                    GlassEffectContainer(spacing: 14) {
                        HStack(spacing: 14) {
                            scanControl
                            describeControl
                        }
                    }
                } else {
                    HStack(spacing: 14) {
                        scanControl
                        describeControl
                    }
                }
            } else {
                // Neither AI nor online: one full-width labeled door,
                // matching `ScanRowLabel`'s copy — the field would be a
                // dead end with nothing behind it.
                EntryDoorScanButton(scanBusy: scanBusy, onScan: onScan) {
                    fallbackLabel
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var fallbackLabel: some View {
        HStack(spacing: 10) {
            if scanBusy {
                ProgressView()
            } else {
                Image(systemName: "camera")
                    .font(.body.weight(.semibold))
            }
            Text("Scan Barcode, Label, or Menu")
                .font(.body.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: Self.controlHeight)
        .modifier(DoorBarChrome(tinted: true, shape: AnyShape(RoundedRectangle(cornerRadius: 22, style: .continuous))))
    }

    /// 50pt — matched against the rows above it (the AI estimate row,
    /// the online search row, the Water row below), which all read
    /// visibly taller than this bar's original 44pt (Apple's minimum
    /// tap target, but too skinny sitting under full-height list rows —
    /// the user, from-device screenshot, 2026-09-16). Both controls
    /// share this height so their tops and bottoms line up.
    private static let controlHeight: CGFloat = 50

    private var scanControl: some View {
        EntryDoorScanButton(scanBusy: scanBusy, onScan: onScan) {
            Group {
                if scanBusy {
                    ProgressView()
                } else {
                    // No explicit foreground override on 26+: glass
                    // supplies vibrant, legible content automatically
                    // (Liquid Glass guidance) — riceToast here is only
                    // for the pre-26 chip fallback, matching
                    // `DoorCircleGlyph`'s own treatment.
                    Image(systemName: "camera")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(preGlassForeground)
                }
            }
            .frame(width: Self.controlHeight, height: Self.controlHeight)
        }
        .modifier(DoorBarChrome(tinted: true, shape: AnyShape(Circle())))
    }

    private var describeControl: some View {
        EntryDoorDescribeField(describeQuery: $describeQuery, onDescribeSubmit: onDescribeSubmit)
            .padding(.horizontal, 16)
            // minHeight, not a fixed height: large Dynamic Type sizes
            // need MORE than 50pt for the field's text to fit, and a
            // fixed frame would clip it.
            .frame(minHeight: Self.controlHeight)
            .modifier(DoorBarChrome(tinted: false, shape: AnyShape(Capsule())))
    }

    private var preGlassForeground: Color {
        if #available(iOS 26.0, *) { .primary } else { .riceToast }
    }
}

/// The floating bar's per-control chrome: Liquid Glass on iOS 26+
/// (tinted riceToast for the camera, plain regular for the describe
/// capsule — one tint, not two, per the HIG's "when everything is
/// tinted, nothing stands out" rule); the existing
/// `.tertiarySystemGroupedBackground` chip below the floor, matching
/// `EntryDoorsSection`'s own fallback exactly.
private struct DoorBarChrome: ViewModifier {
    var tinted: Bool
    var shape: AnyShape

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(
                tinted ? .regular.tint(.riceToast).interactive() : .regular.interactive(),
                in: shape
            )
        } else {
            content.background(Color(.tertiarySystemGroupedBackground), in: shape)
        }
    }
}
