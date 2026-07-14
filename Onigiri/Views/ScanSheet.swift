import SwiftUI
import PhotosUI
import VisionKit
import OnigiriKit
import os

/// Scan outcomes only reach any log through here — visible in the device
/// console during pantry QA, invisible to users.
private let scanLog = Logger(subsystem: "com.ecliptik.Onigiri", category: "scan")

/// ONE camera for the whole package (the user: one scan button): the live
/// scanner fires on a barcode exactly as before, and a shutter button
/// photographs the Nutrition Facts panel for foods no database knows —
/// no mode to pick. A photo-library pick covers labels photographed
/// earlier; the no-camera fallback (simulator) keeps manual barcode entry
/// and the photo paths.
struct ScanSheet: View {
    let onCode: (String) -> Void
    let onLabel: (ParsedLabel) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var manualCode = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var isReading = false
    @State private var failureMessage: String?
    /// Reaches the live scanner for capturePhoto() — the representable
    /// parks its controller here.
    @State private var scannerProxy = ScannerProxy()

    /// UI-test hook (LABEL_SCAN=1): a bundled label photo stands in for
    /// the pickers, exercising the real Vision request end to end.
    private static let sampleAvailable =
        ProcessInfo.processInfo.arguments.contains("--label-scan-sample")

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    cameraLayout
                } else {
                    fallbackLayout
                }
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
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

    // MARK: Camera layout

    private var cameraLayout: some View {
        ScannerRepresentable(proxy: scannerProxy) { code in
            onCode(code)
            dismiss()
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            VStack(spacing: 12) {
                if isReading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Reading label…")
                    }
                    .padding(10)
                    .background(.regularMaterial, in: .capsule)
                }
                if let failureMessage {
                    Text(failureMessage)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(10)
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                }
                Text("Point at a barcode, or photograph the Nutrition Facts panel.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(.regularMaterial, in: .capsule)
                HStack {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(.ultraThinMaterial, in: .circle)
                    }
                    .accessibilityLabel("Choose a label photo")
                    Spacer()
                    // The shutter: a still of the label for the OCR path.
                    Button {
                        Task { await captureLabel() }
                    } label: {
                        ZStack {
                            Circle().strokeBorder(.white, lineWidth: 4)
                                .frame(width: 68, height: 68)
                            Circle().fill(.white)
                                .frame(width: 54, height: 54)
                        }
                    }
                    .accessibilityLabel("Photograph the nutrition label")
                    .disabled(isReading)
                    Spacer()
                    // Balances the picker so the shutter stays centered.
                    Color.clear.frame(width: 52, height: 52)
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 24)
            .padding(.horizontal, 16)
        }
    }

    private func captureLabel() async {
        guard let scanner = scannerProxy.controller else {
            failureMessage = "The camera isn't ready — try again."
            return
        }
        do {
            let photo = try await scanner.capturePhoto()
            await read(photo)
        } catch {
            scanLog.error("Label capture failed: \(String(describing: error))")
            failureMessage = "Couldn't take that photo — try again."
        }
    }

    // MARK: No-camera fallback (simulator, restricted devices)

    private var fallbackLayout: some View {
        Form {
            Section {
                Text("Camera scanning isn't available — enter the barcode digits manually, or read a nutrition label from a photo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("Barcode", text: $manualCode)
                    .keyboardType(.numberPad)
                Button("Look Up") {
                    onCode(manualCode)
                    dismiss()
                }
                .disabled(manualCode.count < 8)
            }
            Section {
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
            }
        }
        .riceCanvas()
    }

    private func useSamplePhoto() {
        guard let url = Bundle.main.url(forResource: "sample-nutrition-label", withExtension: "png"),
              let image = UIImage(contentsOfFile: url.path) else {
            failureMessage = "Sample photo missing from the bundle."
            return
        }
        Task { await read(image) }
    }

    // MARK: Label pipeline

    private func read(_ image: UIImage) async {
        isReading = true
        failureMessage = nil
        defer { isReading = false }
        guard let cgImage = image.cgImage else {
            failureMessage = "Couldn't read that photo — try another."
            return
        }
        do {
            let result = try await LabelScan.scan(
                cgImage,
                orientation: CGImagePropertyOrientation(image.imageOrientation))
            // iOS 26 + Apple Intelligence: the on-device model fills
            // whatever the deterministic parse left blank — invisible,
            // and every model failure keeps the deterministic result.
            let parsed = await FoodIntelligence.refine(result.parsed, transcript: result.transcript)
            if parsed.isEmpty {
                scanLog.notice("Label parse empty from \(result.transcript.count) observations")
                failureMessage = "Couldn't read a nutrition panel there — try a closer, straighter shot with the whole panel in frame."
            } else {
                scanLog.notice("Label parsed: kcal \(parsed.kcal.map(String.init(describing:)) ?? "nil"), \(result.transcript.count) observations")
                onLabel(parsed)
                dismiss()
            }
        } catch {
            scanLog.error("Label OCR failed: \(String(describing: error))")
            failureMessage = "Couldn't read that photo — try another."
        }
    }
}

/// Hands the live controller to the SwiftUI layer for capturePhoto().
@MainActor
final class ScannerProxy {
    weak var controller: DataScannerViewController?
}

private struct ScannerRepresentable: UIViewControllerRepresentable {
    let proxy: ScannerProxy
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        proxy.controller = scanner
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        // Dismissal after a successful scan re-runs updates — don't
        // restart the camera for the teardown animation.
        guard !context.coordinator.delivered else { return }
        try? scanner.startScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private(set) var delivered = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !delivered else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let code = barcode.payloadStringValue {
                    delivered = true
                    dataScanner.stopScanning()
                    onCode(code)
                    return
                }
            }
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
