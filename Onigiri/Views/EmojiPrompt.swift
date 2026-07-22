import SwiftUI
import UIKit
import OnigiriKit

/// A UITextField that opens straight onto the emoji keyboard (when the
/// device has one) and selects its content on focus, so typing a new
/// emoji replaces the old without a backspace. Alert text fields can't
/// do either — this rides in a small sheet instead.
private final class EmojiUITextField: UITextField {
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" }
            ?? super.textInputMode
    }

    // A stable identifier lets the system remember the emoji plane for
    // this field across presentations.
    override var textInputContextIdentifier: String? { "onigiri.emojiPrompt" }
}

private struct EmojiTextField: UIViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeUIView(context: Context) -> EmojiUITextField {
        let field = EmojiUITextField()
        field.text = text
        field.accessibilityIdentifier = "emojiPromptField"
        // VoiceOver lands here unlabeled otherwise — the nav title alone
        // doesn't name the field's purpose (2026-07-22 audit).
        field.accessibilityLabel = "Custom emoji"
        field.delegate = context.coordinator
        field.font = UIFontMetrics(forTextStyle: .title2)
            .scaledFont(for: .systemFont(ofSize: 24))
        field.adjustsFontForContentSizeCategory = true
        field.textAlignment = .center
        field.borderStyle = .roundedRect
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed), for: .editingChanged)
        // Focus after presentation settles; selection happens on focus.
        DispatchQueue.main.async { field.becomeFirstResponder() }
        return field
    }

    func updateUIView(_ field: EmojiUITextField, context: Context) {
        if field.text != text { field.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: EmojiTextField
        init(_ parent: EmojiTextField) { self.parent = parent }

        @objc func changed(_ field: UITextField) {
            // Keep only the newest emoji: picking another replaces the
            // current one — no backspace, and never two in the field.
            let value = field.text ?? ""
            let latest = value.count > 1 ? String(value.suffix(1)) : value
            if latest != value { field.text = latest }
            parent.text = latest
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            // Pre-selected: the next keystroke replaces the current emoji.
            field.selectAll(nil)
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.onSubmit()
            return true
        }
    }
}

/// The "Choose custom…" prompt: the chosen emoji previewed large above
/// the keyboard (the field itself is just the input conduit), emoji
/// keyboard up front, Save / Cancel.
struct EmojiPromptSheet: View {
    let title: String
    @Binding var input: String
    let onUse: () -> Void
    let onCancel: () -> Void
    /// Dynamic Type: the preview and field scale instead of freezing at
    /// fixed sizes exactly when the user asked for bigger text.
    @ScaledMetric(relativeTo: .largeTitle) private var previewSize = 56.0
    @ScaledMetric(relativeTo: .title2) private var fieldHeight = 44.0

    var body: some View {
        NavigationStack {
            // Top-aligned and keyboard-immune: on device the keyboard
            // pushed centered content out of the visible strip above it.
            VStack(spacing: 12) {
                // The preview IS the state: what's here is what Save keeps.
                Text(input.isEmpty ? " " : input)
                    .font(.system(size: previewSize))
                EmojiTextField(text: $input, onSubmit: onUse)
                    .frame(width: 96, height: fieldHeight)
                Spacer(minLength: 0)
            }
            .padding()
            .ignoresSafeArea(.keyboard, edges: .bottom)
            // The slot's name, not a hardcoded "Custom Emoji" — all five
            // icon slots presented identically with no context for which
            // icon was being changed.
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onUse() }
                }
            }
        }
        .presentationDetents([.height(240)])
    }
}
