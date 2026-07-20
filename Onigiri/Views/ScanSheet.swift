import SwiftUI
import PhotosUI
import VisionKit
import AVFoundation
import OnigiriKit
import os

/// Scan outcomes only reach any log through here — visible in the device
/// console during pantry QA, invisible to users.
private let scanLog = Logger(subsystem: "com.ecliptik.Onigiri", category: "scan")

/// ONE camera for the whole package (the user: one scan button): the live
/// scanner fires on a barcode exactly as before, and a shutter button
/// photographs the Nutrition Facts panel for foods no database knows —
/// no mode to pick. The same still cascades (PLAN-identify-food): a
/// photo that yields no nutrition panel falls through to on-device food
/// identification when Apple Intelligence is around, so photographing
/// the food itself is the third door with zero new controls. A
/// photo-library pick covers labels photographed earlier; the no-camera
/// fallback (simulator) keeps manual barcode entry and the photo paths.
struct ScanSheet: View {
    let onCode: (String) -> Void
    let onLabel: (ParsedLabel) -> Void
    /// An identified food photo, prefill-shaped like the label path.
    let onFood: (ScannedProduct) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var manualCode = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var isReading = false
    /// The one in-flight OCR/identify pipeline. Stored so Cancel (and
    /// backgrounding) actually STOPS it — an orphaned cascade used to
    /// fire onLabel/onFood into the parent after dismissal, silently
    /// re-presenting sheets or overwriting form fields (2026-07-20
    /// audit HIGH).
    @State private var readTask: Task<Void, Never>?
    /// Camera permission explicitly denied/restricted — distinct from
    /// "no camera hardware", which shares the same fallback layout.
    @State private var cameraAuthDenied = false
    /// What the progress capsule says — the cascade's second leg takes
    /// long enough that "Reading label…" would read as a hang.
    @State private var readingStatus = ""
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
                    Button("Cancel") {
                        readTask?.cancel()
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                readTask?.cancel()
                readTask = Task {
                    defer { photoItem = nil }
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        failureMessage = "Couldn't load that photo — try another."
                        return
                    }
                    await read(image)
                }
            }
            .onAppear { refreshCameraAuth() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    // Coming back from Settings after granting camera
                    // access: re-evaluate, so the sheet recovers without
                    // a relaunch.
                    refreshCameraAuth()
                } else {
                    // A cascade mid-flight when the app suspends either
                    // burns background time or dies unrecoverably —
                    // cancel and reset instead.
                    readTask?.cancel()
                    isReading = false
                }
            }
            .interactiveDismissDisabled(isReading)
        }
    }

    // MARK: Camera layout

    private var cameraLayout: some View {
        // isCapturing gates live barcode delivery: a label photo almost
        // always still has the package barcode in frame, and an
        // undeferred barcode hit would race the OCR/identify cascade
        // for the same single-slot sheet state in every host
        // (2026-07-20 audit HIGH).
        ScannerRepresentable(proxy: scannerProxy, isCapturing: { isReading }) { code in
            readTask?.cancel()
            onCode(code)
            dismiss()
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            VStack(spacing: 12) {
                if isReading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(readingStatus)
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
                // The hint only promises the food-photo door when the
                // model that opens it is actually available.
                Text(FoodIntelligence.isAvailable
                    ? "Point at a barcode, or photograph the nutrition label or the food itself."
                    : "Point at a barcode or take a photo of the nutrition facts label.")
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
                    // isReading flips SYNCHRONOUSLY here — set inside the
                    // task (after the capture await) a fast double-tap
                    // started two concurrent pipelines.
                    Button {
                        guard !isReading else { return }
                        isReading = true
                        readingStatus = "Reading label…"
                        failureMessage = nil
                        readTask = Task { await captureLabel() }
                    } label: {
                        ZStack {
                            Circle().strokeBorder(.white, lineWidth: 4)
                                .frame(width: 68, height: 68)
                            Circle().fill(.white)
                                .frame(width: 54, height: 54)
                        }
                    }
                    .accessibilityLabel(FoodIntelligence.isAvailable
                        ? "Photograph the nutrition label or your food"
                        : "Photograph the nutrition label")
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
        // The shutter set isReading before this task started; every
        // early exit must clear it (read() re-sets and clears its own).
        defer { isReading = false }
        guard let scanner = scannerProxy.controller else {
            failureMessage = "The camera isn't ready — try again."
            return
        }
        do {
            let photo = try await scanner.capturePhoto()
            guard !Task.isCancelled else { return }
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
                // Denied is FIXABLE — say so and open the door; the
                // generic copy made a revoked permission read as
                // missing hardware with no way back.
                if cameraAuthDenied {
                    Text("Camera access is turned off, so scanning can't run. You can still enter the barcode digits manually or read a label from a photo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Turn On Camera Access", systemImage: "gear")
                    }
                } else {
                    Text("Camera scanning isn't available — enter the barcode digits manually, or read a nutrition label from a photo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
                        Text(readingStatus)
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
        readTask?.cancel()
        readTask = Task { await read(image) }
    }

    private func refreshCameraAuth() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraAuthDenied = status == .denied || status == .restricted
    }

    // MARK: Label pipeline

    private func read(_ image: UIImage) async {
        isReading = true
        readingStatus = "Reading label…"
        failureMessage = nil
        defer { isReading = false }
        // Vision needs legible text, not sensor resolution: a 48 MP
        // library pick decoded at full size spikes memory across the
        // whole cascade (stacked against the model's own footprint —
        // jetsam territory on older devices). The redraw also bakes
        // orientation upright, so Vision gets .up pixels.
        let image = image.downsampled(maxEdge: 3000)
        guard let cgImage = image.cgImage else {
            failureMessage = "Couldn't read that photo — try another."
            return
        }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        do {
            let result = try await LabelScan.scan(cgImage, orientation: orientation)
            // A cancelled cascade must never deliver: the host would
            // re-present a sheet the user already backed out of.
            guard !Task.isCancelled else { return }
            // iOS 26 + Apple Intelligence: the on-device model fills
            // whatever the deterministic parse left blank — invisible,
            // and every model failure keeps the deterministic result.
            let parsed = await FoodIntelligence.refine(result.parsed, transcript: result.transcript)
            guard !Task.isCancelled else { return }
            if !parsed.isEmpty {
                scanLog.notice("Label parsed: kcal \(parsed.kcal.map(String.init(describing:)) ?? "nil"), \(result.transcript.count) observations")
                onLabel(parsed)
                dismiss()
                return
            }
            scanLog.notice("Label parse empty from \(result.transcript.count) observations")
        } catch {
            scanLog.error("Label OCR failed: \(String(describing: error))")
            failureMessage = "Couldn't read that photo — try another."
            return
        }
        // The cascade (PLAN-identify-food): no nutrition panel in the
        // still, so maybe it's a photo of the food itself. Classifier
        // names the dish, the model decomposes it into a reviewable
        // food; any failure lands on the same retry message as before.
        if FoodIntelligence.isAvailable {
            readingStatus = "Identifying food…"
            let food = await FoodIntelligence.identifyFood(photo: cgImage, orientation: orientation)
            guard !Task.isCancelled else { return }
            if let food {
                scanLog.notice("Photo identified: \(food.name), \(food.components.count) components, \(food.kcal) kcal")
                onFood(food.scannedProduct)
                dismiss()
                return
            }
            scanLog.notice("Photo identify came up empty")
            failureMessage = "Couldn't read a nutrition panel or recognize a food there — try a closer shot."
        } else {
            failureMessage = "Couldn't read a nutrition panel there — try a closer, straighter shot with the whole panel in frame."
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
    /// True while the shutter cascade runs — live barcode hits are
    /// ignored so the two paths can't race each other's sheet slot.
    let isCapturing: () -> Bool
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
        context.coordinator.isCapturing = isCapturing
        // Dismissal after a successful scan re-runs updates — don't
        // restart the camera for the teardown animation.
        guard !context.coordinator.delivered else { return }
        try? scanner.startScanning()
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        // Deterministic camera-off on EVERY dismissal path (Cancel,
        // swipe, label/food success) — not just the barcode-hit one.
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        var isCapturing: () -> Bool = { false }
        private(set) var delivered = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !delivered, !isCapturing() else { return }
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

private extension UIImage {
    /// Cap the long edge before Vision: OCR wants legible text, not
    /// sensor resolution. Draws through a renderer, which also bakes
    /// the orientation upright.
    func downsampled(maxEdge: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxEdge, longest > 0 else { return self }
        let scale = maxEdge / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
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
