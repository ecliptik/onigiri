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
/// **AI off**: the camera button falls back to the full labeled row
/// (`ScanRowLabel`, "Scan Barcode, Label, or Menu") and the describe
/// field is hidden entirely — nothing behind it works without AI, and a
/// field with nowhere to send its text is a dead end, not a door.
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

    /// Matched by the "select all on focus" notification handler in
    /// `FoodFormView` — an in-progress description must not be
    /// select-all'd out from under someone refocusing it, the same
    /// exemption the bottom search field already gets. A SwiftUI
    /// `TextField`'s accessibility identifier rides its bridged
    /// `UITextField`, which is the only handle that notification hands
    /// back.
    static let describeFieldAccessibilityID = "entryDoorsDescribeField"

    var body: some View {
        Section {
            if FoodIntelligence.isAvailable {
                HStack(spacing: 12) {
                    Button(action: onScan) {
                        DoorCircleGlyph(systemImage: "camera")
                    }
                    .buttonStyle(.plain)
                    .disabled(scanBusy)
                    .accessibilityLabel("Scan Barcode, Label, Menu, or Food")
                    TextField("Describe food or meal", text: $describeQuery)
                        .accessibilityLabel("Describe food or meal")
                        .accessibilityIdentifier(Self.describeFieldAccessibilityID)
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
