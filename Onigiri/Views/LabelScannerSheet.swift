import SwiftUI
import PhotosUI
import OnigiriKit
import os

/// Scan outcomes only reach any log through here — visible in the device
/// console during pantry QA, invisible to users.
private let scanLog = Logger(subsystem: "com.ecliptik.Onigiri", category: "labelScan")

/// Photograph (or pick) a Nutrition Facts panel; Vision OCR plus the kit's
/// LabelParser turn it into a ParsedLabel for the food form. Sibling of
/// BarcodeScannerSheet — the third door beside barcode and text search,
/// for foods no database knows.
struct LabelScannerSheet: View {
    let onParsed: (ParsedLabel) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isReading = false
    @State private var failureMessage: String?

    private static let cameraAvailable =
        UIImagePickerController.isSourceTypeAvailable(.camera)
    /// UI-test hook (LABEL_SCAN=1): a bundled label photo stands in for
    /// the pickers, exercising the real Vision request end to end.
    private static let sampleAvailable =
        ProcessInfo.processInfo.arguments.contains("--label-scan-sample")

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if Self.cameraAvailable {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                        }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose Photo", systemImage: "photo.on.rectangle")
                    }
                    if Self.sampleAvailable {
                        Button {
                            useSamplePhoto()
                        } label: {
                            Label("Use Sample Photo", systemImage: "testtube.2")
                        }
                        .accessibilityIdentifier("labelScanSample")
                    }
                    if isReading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Reading label…")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let failureMessage {
                        Text(failureMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } footer: {
                    Text("Frame the Nutrition Facts panel — the form fills in with whatever the photo shows. A pantry shot from your library works too.")
                }
            }
            .riceCanvas()
            .navigationTitle("Scan Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView { image in
                    Task { await read(image) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    defer { photoItem = nil }
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        failureMessage = "Couldn't load that photo — try another."
                        return
                    }
                    await read(image)
                }
            }
            .interactiveDismissDisabled(isReading)
        }
    }

    private func useSamplePhoto() {
        guard let url = Bundle.main.url(forResource: "sample-nutrition-label", withExtension: "png"),
              let image = UIImage(contentsOfFile: url.path) else {
            failureMessage = "Sample photo missing from the bundle."
            return
        }
        Task { await read(image) }
    }

    private func read(_ image: UIImage) async {
        isReading = true
        failureMessage = nil
        defer { isReading = false }
        guard let cgImage = image.cgImage else {
            failureMessage = "Couldn't read that photo — try another."
            return
        }
        do {
            let observations = try await LabelScan.observations(
                from: cgImage,
                orientation: CGImagePropertyOrientation(image.imageOrientation))
            let parsed = LabelParser.parse(observations)
            if parsed.isEmpty {
                scanLog.notice("Label parse empty from \(observations.count) observations")
                failureMessage = "Couldn't read a nutrition panel there — try a closer, straighter shot with the whole panel in frame."
            } else {
                scanLog.notice("Label parsed: kcal \(parsed.kcal.map(String.init(describing:)) ?? "nil"), \(observations.count) observations")
                onParsed(parsed)
                dismiss()
            }
        } catch {
            scanLog.error("Label OCR failed: \(String(describing: error))")
            failureMessage = "Couldn't read that photo — try another."
        }
    }
}

/// Still-photo camera capture (UIImagePickerController): labels want a
/// single deliberate frame, not the barcode scanner's live stream.
private struct CameraCaptureView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: { dismiss() })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        let dismiss: () -> Void

        init(onImage: @escaping (UIImage) -> Void, dismiss: @escaping () -> Void) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

private extension CGImagePropertyOrientation {
    /// UIKit and ImageIO disagree on orientation raw values; Vision wants
    /// the ImageIO flavor.
    init(_ orientation: UIImage.Orientation) {
        self = switch orientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
