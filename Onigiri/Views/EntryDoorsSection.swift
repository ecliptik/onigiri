import SwiftUI
import PhotosUI
import OnigiriKit

// The entry doors — the camera and the "Describe food or meal" field —
// as ONE pinned bar (`EntryDoorBar`, hosted through `entryDoorBar` in
// Style.swift) under both places that create foods: the Log sheet and
// a BLANK Add Food form. History, since each turn was the user's call:
// a labeled scan row and a describe field lived in the list (2026-07);
// the describe field merged into the bottom search field, then split
// back out beside a compact camera button as an in-form chip row
// (`EntryDoorsSection`, 2026-08-29); the Log sheet's pair moved into a
// floating glass bar (2026-09-15) while the form kept its chip row; and
// on 2026-09-16 the form got the same bar ("add the camera/describe on
// the Add food dialog like the camera/describe when logging food") and
// the chip row was retired. One set of doors, one chrome, two hosts.
//
// The field drives BOTH the host's `AIEstimateSection` and its
// `OnlineResultsSection` (2026-08-29), AI → online, each tap-to-run —
// never per-keystroke — so combining them under one field costs nothing.
// That is why the field is gated on `isAvailable || onlineLookups`, not
// `isAvailable` alone: online lookups don't need AI, and hiding the
// field whenever AI is off would strand them with no way to search. When
// NEITHER is on the bar collapses to one full-width labeled camera door
// ("Scan Barcode, Label, or Menu") — a field with nowhere to send its
// text is a dead end, not a door. The Log sheet's field ALSO searches
// the library (2026-09-17, `searchesLibrary`), so there it always has
// somewhere to send its text and never collapses.

/// The camera door's button: glyph + accessibility label + the
/// disabled/action wiring, extracted so no host can say something
/// different about what a tap does. The label is the row's OLD visible
/// title, "Scan Barcode, Label, Menu, or Food", icon-only or not —
/// VoiceOver and `OnigiriUITests.scanRow(in:)` both find it by that
/// label (`label BEGINSWITH 'Scan Barcode'`).
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
/// `EntryDoorScanButton` above — `accessibilityID` is what
/// `FoodFormView`'s select-all-on-focus handler matches against, and a
/// second hand-copied field could silently stop matching it. Callers
/// wrap this in their own padding/background; it draws no chrome of its
/// own. The query is OWNED BY THE HOST (`QuickLogSheet.describeQuery`,
/// `FoodFormView.describeQuery`), separate from any search field, and
/// the host clears it on a successful pick or the estimate row lingers
/// after its job is done.
struct EntryDoorDescribeField: View {
    @Binding var describeQuery: String
    /// Keyboard-submit convenience for the ONLINE leg only — what the
    /// retired bottom `.searchable` field did on `.onSubmit(of:
    /// .search)`. AI stays tap-only (its own button in
    /// `TapToEstimateRow`'s idle phase, one inference per tap on
    /// purpose). `nil` = no submit-triggered search.
    var onDescribeSubmit: (() -> Void)?
    /// The placeholder, which doubles as the accessibility label: what
    /// the field does differs by host. The Log sheet's also searches the
    /// library, and says so (`QuickLogSheet`, 2026-09-17); the Add Food
    /// form's has no library behind it and keeps the default.
    var prompt = EntryDoorDescribeField.defaultPrompt

    static let defaultPrompt = "Describe food or meal"

    /// Matched by the "select all on focus" notification handler in
    /// `FoodFormView` — an in-progress description must not be
    /// select-all'd out from under someone refocusing it. A SwiftUI
    /// `TextField`'s accessibility identifier rides its bridged
    /// `UITextField`, which is the only handle that notification hands
    /// back. The string predates the bar; don't rename it.
    static let accessibilityID = "entryDoorsDescribeField"

    /// The in-capsule keyboard dismiss. Its own identifier because the
    /// app has two other "Done"s on this screen (the sheet's, and the
    /// system's) and a test must not tap one meaning the other.
    static let dismissAccessibilityID = "entryDoorsHideKeyboard"

    /// The HOST owns this. It started owned here — the accessory below
    /// is all the field itself needs — but the Log sheet's leading
    /// toolbar button changes with it too (2026-09-17), and a toolbar
    /// lives in the host, not down here.
    @FocusState.Binding var isFocused: Bool

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
            // An explicit prompt in a CONCRETE color, `Color(.secondaryLabel)`,
            // not the hierarchical `.secondary`. The default placeholder
            // (tertiary) read too faint on the bar's glass capsule over
            // the dark canvas (the user, 2026-09-16: "a bit too light to
            // read on the Dark theme"), and `.secondary` still did on the
            // PHONE while looking fine on the simulator: inside
            // `glassEffect` a hierarchical style is rendered vibrant —
            // blended with the backdrop — and a dark backdrop dims it
            // again; a concrete Color is drawn as-is. Typed text stays
            // primary, so this still reads as a placeholder.
            TextField(
                prompt, text: $describeQuery,
                prompt: Text(prompt).foregroundStyle(Color(.secondaryLabel))
            )
                .accessibilityLabel(prompt)
                .accessibilityIdentifier(Self.accessibilityID)
                .focused($isFocused)
                .onSubmit { onDescribeSubmit?() }
            // Put the keyboard away without leaving the screen (the
            // user, 2026-09-17). Until this there was no way out of it
            // but Cancel or Done, which take the whole sheet with them,
            // or picking a row.
            //
            // INSIDE the capsule, not a `.keyboard` toolbar accessory:
            // that accessory and this bar both sit above the keyboard,
            // so they overlapped — the Done floated across the field's
            // trailing edge (the user, from device: "overlaps the
            // search field"). A control that belongs to the field is
            // laid out BY the field and cannot collide with it. And not
            // in the nav bar either, where a keyboard glyph replacing
            // Cancel didn't land ("I don't like the keyboard icon").
            //
            // A chevron, not a keyboard glyph: this collapses the thing
            // it sits on, which is what the arrow says and what the
            // same arrow means on every disclosure in the app.
            if isFocused {
                Button {
                    isFocused = false
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(.secondaryLabel))
                        // A 44pt target around a small glyph, without
                        // the glyph growing to match.
                        .frame(width: 30, height: 30)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide Keyboard")
                .accessibilityIdentifier(Self.dismissAccessibilityID)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

/// The camera + describe door bar (`plans/PLAN-log-sheet-layout.md`,
/// 2026-09-15): a glass-chrome pill — Liquid Glass on iOS 26+, camera
/// tinted (the app's one primary action per the HIG's "tint one, not
/// everything" rule), describe plain; the flat chip fallback below the
/// floor. PINNED via `entryDoorBar` (Style.swift) under the Log sheet's
/// List (hidden while searching) and under a blank Add Food form (hidden
/// once the form is no longer blank — a form opened from a search result
/// or editing a saved food offering another search was a loop).
///
/// In the Log sheet it spent part of 2026-09-16 as the list's trailing
/// row instead, to close the empty canvas a short Favorites list leaves
/// above a pinned bar — and was then unreachable on any real library
/// without scrolling to the very end. The user chose pinned with both
/// in hand; `entryDoorBar`'s doc comment has the rest.
struct EntryDoorBar: View {
    var scanBusy = false
    @Binding var describeQuery: String
    let onScan: () -> Void
    var onDescribeSubmit: (() -> Void)?
    /// The describe field's focus, owned by the host — see
    /// `EntryDoorDescribeField.isFocused`.
    @FocusState.Binding var describeFocused: Bool
    /// Passed through to `EntryDoorDescribeField`; see its doc comment.
    var describePrompt = EntryDoorDescribeField.defaultPrompt
    /// Open the attach chooser — camera, photos, or a file. nil hides
    /// the "+". A sheet rather than a `Menu` (the user, 2026-09-18,
    /// with the Claude app's "Add context" as the reference): three
    /// tiles you can hit with a thumb, not a list you read.
    var onAddContext: (() -> Void)?
    /// Run the AI estimate on what's typed. nil = this host has no
    /// estimate to offer, and the button doesn't render.
    var onEstimate: (() -> Void)?
    /// Search the online database for what's typed. nil, same rule.
    var onSearchOnline: (() -> Void)?
    /// An estimate is in flight — the button says so and won't start a
    /// second one. One inference at a time is a standing rule: two
    /// serialize on-device and double-bill a BYO-AI provider.
    var isEstimating = false
    /// The host searches its LIBRARY with this field too (the Log
    /// sheet, since 2026-09-17), so the field has somewhere to send its
    /// text even with AI and online lookups both off — and must stay.
    /// The first run of `testLogWithoutSaving` after the merge (which
    /// switches online off, on a sim where AI is off) found a Log sheet
    /// with no text field at all. The form leaves this false: it has
    /// no library, and the fallback door is right for it.
    var searchesLibrary = false

    /// `searchesLibrary || isAvailable || onlineLookups`, never
    /// `isAvailable` alone (see the file header): a field with nowhere
    /// to send its text is a dead end, not a door — and a library is
    /// somewhere.
    private var describeFieldAvailable: Bool {
        searchesLibrary || FoodIntelligence.isAvailable || SharedStore.onlineLookups
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
                // Camera LEADING, describe field trailing. THE REVERSE
                // HAS NOW BROKEN BARCODE SCANNING TWICE, asked for in
                // the same words both times (the user, 2026-09-16 and
                // again 2026-09-17: "Move the camera button to the
                // right of the unified search field"), and reverted the
                // same day both times.
                //
                // The failure is silent: the camera button is present,
                // hittable and taps cleanly — `scanRow` finds it, the
                // tap "succeeds" — and the scanner never opens. No
                // crash, no error, nothing in the log.
                // `testBarcodeLookupPrefillsForm` is the ONLY thing
                // that catches it, and it catches it on the scanner's
                // own "Barcode" field never appearing, two assertions
                // downstream of the tap.
                //
                // The 09-17 retry was deliberate, not forgetful: this
                // bar had changed underneath the old note — the field
                // gained a trailing dismiss button, the row's metrics
                // changed with `defaultMinListRowHeight`, and the whole
                // search moved into this field. None of it mattered.
                // Swapping these two views was again the ONLY change
                // between a passing and a failing run, isolated by
                // reverting just the order and re-running (the chevron
                // was cleared of involvement the same way).
                //
                // The mechanism is still unconfirmed — a
                // `GlassEffectContainer` hit-testing quirk when the
                // fixed-size circle trails a flexible-width field is
                // the standing suspicion. DON'T swap these two again
                // hoping the third time differs. If the camera has to
                // move right, diagnose the hit-testing first, or move
                // it out of this HStack entirely (the composer's action
                // row, `plans/PLAN-log-composer.md`, is the obvious
                // home and sidesteps the arrangement completely).
                // Text row, then the actions that act ON that text —
                // the composer shape (`plans/PLAN-log-composer.md`, the
                // user, 2026-09-17, after the Claude app's own: "See how
                // there's typing area with actions underneath?"). One
                // container, so every door this bar offers is in one
                // place and the list above is left meaning results.
                VStack(alignment: .leading, spacing: 10) {
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
                    // Only while the field is ACTIVE (the user,
                    // 2026-09-17, from device). They were always
                    // present and dimmed at first — chosen so they'd be
                    // discoverable at rest — and at rest is exactly
                    // where they earn nothing: three dead controls
                    // under a sheet you are reading, with "Estimate
                    // with AI" truncated to "Estimate wit…" for the
                    // privilege. The bar's height changes with the
                    // keyboard now, which is the moment it was always
                    // going to move anyway.
                    if describeFocused {
                        actionRow
                    }
                }
            } else {
                // Neither AI nor online: one full-width labeled door —
                // the field would be a dead end with nothing behind it.
                // "Menu" but not "Food": a menu document is read by the
                // deterministic table parser, open with AI off; the
                // identify cascade is not, so the label only promises
                // what it can keep.
                EntryDoorScanButton(scanBusy: scanBusy, onScan: onScan) {
                    fallbackLabel
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    /// What the typed text can be sent to. ALWAYS PRESENT, dimmed until
    /// there is something to send (the user's call, 2026-09-17): the
    /// actions stay discoverable at rest, and the bar never changes
    /// height as you type — a bar that grew on the first keystroke
    /// would shove the list it sits under.
    ///
    /// Empty when neither AI nor online lookups are on. The row draws
    /// nothing then rather than an empty strip; the text row above it
    /// is still a library search where the host has a library, and
    /// where it doesn't, `describeFieldAvailable` has already collapsed
    /// the whole bar to the labeled camera door.
    @ViewBuilder
    private var actionRow: some View {
        let hasQuery = !describeQuery.trimmingCharacters(in: .whitespaces).isEmpty
        if onEstimate != nil || onSearchOnline != nil || onAddContext != nil {
            HStack(spacing: 10) {
                // "+" in the camera's column, the two actions SPLITTING
                // what's left (the user, 2026-09-18: "fill the entire
                // row, with + left aligned and then increase the width
                // of the other two buttons"). The attach affordance
                // shares the camera's vertical; the actions on the text
                // span the field's width, as the field does.
                if let onAddContext {
                    Button(action: onAddContext) {
                        Image(systemName: "plus")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Color(.label))
                            .frame(width: 36, height: 36)
                            .contentShape(.circle)
                            .modifier(DoorBarChrome(tinted: false, shape: AnyShape(Circle())))
                    }
                    .accessibilityLabel("Add a Photo or File")
                    // LEADING EDGE, not centred under the camera (the
                    // user, 2026-09-18: "left aligned the +"). It spent
                    // a day in a `controlHeight`-wide column so its
                    // smaller circle sat on the camera's axis, and that
                    // column is 7pt wider than the glyph on each side —
                    // so the + started 7pt in from the camera above it
                    // AND the gap to the first pill measured 17pt
                    // against the 10pt between the pills. Uneven gaps
                    // read as a mistake more loudly than an off-axis
                    // circle does. At its natural width the row's three
                    // controls share one spacing, the + starts where the
                    // camera and the field start, and the 14pt this
                    // frees goes to the pills.
                }
                if let onEstimate {
                    ComposerAction(
                        // "Estimate with AI" — the active voice the
                        // rest of the app's buttons are written in, and
                        // the shorter "AI Estimate" only existed to fit
                        // a pill that wasn't filling its slot (the
                        // user, 2026-09-18, restoring it once it did).
                        // The sparkle still carries the ✨ mark.
                        title: isEstimating ? "Estimating…" : "Estimate with AI",
                        systemImage: "sparkles",
                        tint: Color.riceToast,
                        // Disabled, not hidden, once the row is up: you
                        // can see what the field's actions are before
                        // there is anything to act on.
                        isEnabled: hasQuery && !isEstimating,
                        action: onEstimate
                    )
                }
                if let onSearchOnline {
                    ComposerAction(
                        title: "Search Online",
                        systemImage: "magnifyingglass",
                        tint: nil,
                        isEnabled: hasQuery,
                        action: onSearchOnline
                    )
                }
            }
        }
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
                    // for the pre-26 chip fallback, matching LogButton's
                    // circle.
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
        EntryDoorDescribeField(
            describeQuery: $describeQuery, onDescribeSubmit: onDescribeSubmit,
            prompt: describePrompt, isFocused: $describeFocused)
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

/// The bar's per-control chrome: Liquid Glass on iOS 26+ (tinted
/// riceToast for the camera, plain regular for the describe capsule —
/// one tint, not two, per the HIG's "when everything is tinted, nothing
/// stands out" rule); a `.tertiarySystemGroupedBackground` chip below
/// the floor — that flat system color, NOT `.quaternary`, because the
/// hierarchical material is a vibrancy style that washed out light on a
/// real device in dark mode (the user, 2026-08-30, from-device
/// screenshot: "light mode button leak"). `LogButton`'s circle has the
/// same rule for the same reason.
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

/// One action under the composer's text row. A capsule with the bar's
/// own chrome, so the row reads as part of the bar rather than as list
/// content that wandered down — `DoorBarChrome` is the same glass the
/// camera and the field wear (and the same flat chip below the floor,
/// for the 2026-08-30 vibrancy reason recorded there).
///
/// Disabled state is `.secondaryLabel` on the glyph and the words, a
/// CONCRETE color for the same reason the field's placeholder is one:
/// inside `glassEffect` a hierarchical style renders vibrant, blends
/// with the backdrop, and a dark backdrop dims it twice over.
private struct ComposerAction: View {
    let title: String
    let systemImage: String
    /// The glyph's color when enabled — the sparkle keeps its riceToast
    /// so ✨ still reads as the AI mark it is everywhere else. nil takes
    /// the label color.
    let tint: Color?
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(glyphColor)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    // Shrink before clipping: an ellipsis lands on the
                    // one word that says what the button does
                    // ("Estimate wit…"). At 0.8 the longest label fits
                    // the narrowest phone this app supports.
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12)
            // INSIDE the chrome, so the CHIP fills the slot and not
            // just the slot the chip sits in. Hung on the Button
            // outside this label, the capsule drew at its natural
            // width and the row read as three pills adrift in their
            // own gaps (the user, 2026-09-18: "have the AI Estimate
            // and Search Online buttons be wider to fill in the space
            // in the second row").
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .contentShape(.capsule)
            .modifier(DoorBarChrome(tinted: false, shape: AnyShape(Capsule())))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        // The label already says it; without this the row reads its
        // glyph name out loud as well.
        .accessibilityLabel(title)
    }

    private var glyphColor: Color {
        guard isEnabled else { return Color(.secondaryLabel) }
        return tint ?? Color(.label)
    }

    private var textColor: Color {
        isEnabled ? Color(.label) : Color(.secondaryLabel)
    }
}

/// What the composer's "+" opens: camera, photos, or a file, as three
/// tiles (the user, 2026-09-18, with the Claude app's "Add context"
/// sheet in hand). A sheet rather than the `Menu` this replaced — a
/// menu is a list you read at the top of the screen, and these are
/// three equal doors a thumb picks between.
///
/// It only CHOOSES. Each tile hands the decision back and the host
/// opens the real door, so the one cascade behind all three
/// (`ScanSheet`) still owns every read.
struct AddContextSheet: View {
    let onCamera: () -> Void
    /// A pick, not a request: the chooser raises the pickers itself and
    /// hands back what came out, so the reader sheet appears only once
    /// there is something to read. It presented the reader FIRST for a
    /// day and that flashed an empty canvas on the way to the picker,
    /// and again on the way back out (the user, 2026-09-18: "Scan still
    /// comes up with +, but disappears itself, still looks janky").
    let onPhoto: (PhotosPickerItem) -> Void
    let onFile: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingPhotos = false
    @State private var showingFiles = false
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color(.label))
                        .frame(width: 34, height: 34)
                        .background(Color(.tertiarySystemGroupedBackground), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                Spacer()
                Text("Add Food From")
                    .font(.headline)
                Spacer()
                // Balances the close button so the title sits centred.
                Color.clear.frame(width: 34, height: 34)
            }
            HStack(spacing: 12) {
                // Only the camera closes the chooser on the tap: the
                // other two stay up under their picker, so cancelling
                // one lands back here — where the choice was made —
                // instead of dropping the whole errand.
                tile("Camera", systemImage: "camera") {
                    onCamera()
                    dismiss()
                }
                tile("Photos", systemImage: "photo") { showingPhotos = true }
                tile("Files", systemImage: "doc") { showingFiles = true }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .riceCanvas()
        .photosPicker(isPresented: $showingPhotos, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            deliver { onPhoto(item) }
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.pdf]) { result in
            // Cancelled: stay on the chooser. Nothing was picked, so
            // there is nothing for the host to open.
            guard case .success(let url) = result else { return }
            deliver { onFile(url) }
        }
    }

    /// Hand the pick up and close. The host swaps this sheet for the
    /// reader, and a synchronous swap inside a closure the sheet follows
    /// with its own `dismiss()` tears the new sheet down with the old
    /// (CLAUDE.md's 2026-07-22 race) — so the host defers its swap a
    /// turn, and this only has to keep the order.
    private func deliver(_ pick: () -> Void) {
        pick()
        dismiss()
    }

    private func tile(
        _ title: String, systemImage: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(.subheadline)
            }
            .foregroundStyle(Color(.label))
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .background(Color(.tertiarySystemGroupedBackground),
                        in: .rect(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
