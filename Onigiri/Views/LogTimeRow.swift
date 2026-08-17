import SwiftUI

/// When a log entry happened — moved without leaving the sheet that owns
/// it.
///
/// Two shapes were tried before this one, and both failed the same way:
/// they had nowhere to put the picker.
///
/// - A compact `DatePicker` (what shipped) opens its calendar as a
///   floating overlay with no controls of its own. You dismiss it by
///   tapping OUTSIDE — and on a `.medium` detent sheet, outside is the
///   dimmed backdrop, the gesture that closes the whole edit. A date
///   could be chosen and then neither confirmed nor abandoned (the user,
///   2026-08-17, moving an entry to yesterday).
/// - Expanding the picker IN the form fixes the controls and moves the
///   problem: at the medium detent the calendar unrolls below the fold,
///   so tapping the chip appears to do nothing until you scroll, and
///   the month header then slides under the sheet's own toolbar
///   (measured on the 16 sim, same day).
///
/// So the picker gets its own sheet, sized to itself: fully visible at
/// any detent of the sheet behind it, with Cancel and Done where every
/// other sheet in the app puts them. The binding is written only by
/// Done, which is what makes Cancel mean something — the entry keeps the
/// time it already had.
struct LogTimeRow: View {
    @Binding var date: Date

    private enum Field: String, Identifiable {
        case day, time
        var id: String { rawValue }
        var title: String { self == .day ? "Date" : "Time" }
    }

    @State private var editing: Field?
    /// The pending edit, kept apart from `date`: a picker bound straight
    /// to the entry has already changed it by the time you look for a
    /// way out.
    @State private var draft = Date.now

    var body: some View {
        LabeledContent("Time") {
            HStack(spacing: 8) {
                chip(date.formatted(.dateTime.month(.abbreviated).day().year()),
                     field: .day, accessibility: "Date")
                chip(date.formatted(date: .omitted, time: .shortened),
                     field: .time, accessibility: "Time of day")
            }
        }
        .sheet(item: $editing) { field in
            NavigationStack {
                picker(for: field)
                    .navigationTitle(field.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel", role: .cancel) { editing = nil }
                                .accessibilityIdentifier("logTime.cancel")
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                date = min(draft, .now)
                                editing = nil
                            }
                            .accessibilityIdentifier("logTime.done")
                        }
                    }
            }
            // Medium fits the calendar; large is there for the type
            // sizes it doesn't.
            .presentationDetents([.medium, .large])
        }
    }

    /// A log is a record, not a plan: no future days. The TIME picker
    /// carries no bound of its own — the day it belongs to may be
    /// yesterday, where every hour is legal — so Done clamps instead.
    @ViewBuilder
    private func picker(for field: Field) -> some View {
        switch field {
        case .day:
            DatePicker("", selection: $draft, in: ...Date.now, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(.horizontal)
        case .time:
            DatePicker("", selection: $draft, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func chip(_ text: String, field: Field, accessibility: String) -> some View {
        Button {
            draft = date
            editing = field
        } label: {
            Text(text).monospacedDigit()
        }
        .buttonStyle(.bordered)
        .tint(Color.secondary)
        .accessibilityLabel("\(accessibility), \(text)")
        .accessibilityHint("Opens the picker")
    }
}
