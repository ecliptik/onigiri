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
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 44)
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
            parent.text = field.text ?? ""
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

/// The "Choose your own…" prompt: current emoji shown selected, emoji
/// keyboard up front, Use it / Cancel.
struct EmojiPromptSheet: View {
    let title: String
    @Binding var input: String
    let onUse: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("One emoji — it becomes the \(title.lowercased()).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                EmojiTextField(text: $input, onSubmit: onUse)
                    .frame(width: 96, height: 64)
            }
            .padding()
            .navigationTitle("Your own emoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use it") { onUse() }
                }
            }
        }
        .presentationDetents([.height(220)])
    }
}
