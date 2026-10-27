import SwiftUI
import UIKit
import AVFoundation
import VisionKit
import Vision

/// The live camera: VisionKit `DataScannerViewController` (native-components.md, "Camera feed +
/// barcode reading"). `recognizedDataTypes` is a `let`, so the parent rebuilds this view with
/// `.id(mode)` when Barcode | Ingredients changes.
struct ScannerView: UIViewControllerRepresentable {
    let mode: ScanModel.Mode
    /// The frame rect in this view's coordinates; reads outside it are ignored.
    let regionOfInterest: CGRect?
    let handle: ScannerHandle
    let onBarcode: (String) -> Void

    /// The device can run the scanner and the camera is not restricted.
    static var canScan: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let types: Set<DataScannerViewController.RecognizedDataType> = mode == .barcode
            ? [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])]
            : [.text()]
        let controller = DataScannerViewController(recognizedDataTypes: types, qualityLevel: .balanced,
                                                   recognizesMultipleItems: mode == .barcode,
                                                   isHighlightingEnabled: false)
        controller.delegate = context.coordinator
        handle.controller = controller
        do {
            try controller.startScanning()
        } catch {
            Log.lookup.error("Scanner failed to start: \(String(describing: error), privacy: .public)")
        }
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onBarcode = onBarcode
        // The first permission prompt can leave the scanner stopped; start it once it is available.
        if !controller.isScanning && DataScannerViewController.isAvailable {
            try? controller.startScanning()
        }
        if controller.regionOfInterest != regionOfInterest { controller.regionOfInterest = regionOfInterest }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onBarcode: onBarcode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onBarcode: (String) -> Void
        init(onBarcode: @escaping (String) -> Void) { self.onBarcode = onBarcode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd added: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            pick(scanner, allItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didUpdate updated: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            pick(scanner, allItems)
        }

        private func pick(_ scanner: DataScannerViewController, _ allItems: [RecognizedItem]) {
            // Two barcodes in view: take the one closest to the frame center (spec 03, edge cases).
            let center = scanner.regionOfInterest.map { CGPoint(x: $0.midX, y: $0.midY) }
                ?? CGPoint(x: scanner.view.bounds.midX, y: scanner.view.bounds.midY)
            let codes: [(value: String, distance: CGFloat)] = allItems.compactMap { item in
                guard case .barcode(let code) = item, let value = code.payloadStringValue else { return nil }
                let b = code.bounds
                let mid = CGPoint(x: (b.topLeft.x + b.bottomRight.x) / 2, y: (b.topLeft.y + b.bottomRight.y) / 2)
                return (value, hypot(mid.x - center.x, mid.y - center.y))
            }
            if let best = codes.min(by: { $0.distance < $1.distance }) { onBarcode(best.value) }
        }
    }
}

/// Reaches the running scanner for the shutter, and the torch (the scanner has no torch API).
@Observable
final class ScannerHandle {
    @ObservationIgnored weak var controller: DataScannerViewController?
    /// Mirrors `device.torchMode` after each change, so the button redraws.
    private(set) var torchOn = false

    /// The torch shows only when the device has one (spec 03, edge cases). Read once.
    let hasTorch = AVCaptureDevice.default(for: .video)?.hasTorch ?? false

    /// Ingredients shutter: a still from the running scanner.
    func capturePhoto() async throws -> UIImage? {
        try await controller?.capturePhoto()
    }

    func toggleTorch() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = device.torchMode == .on ? .off : .on
            device.unlockForConfiguration()
            torchOn = device.torchMode == .on
        } catch {
            Log.lookup.error("Torch failed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// On-device OCR for an ingredients photo: Vision `RecognizeTextRequest`, accurate level. The image
/// stays in memory and is dropped after this call.
nonisolated enum TextRecognizer {
    static func lines(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        do {
            let observations = try await request.perform(on: cgImage, orientation: orientation(image.imageOrientation))
            return observations.compactMap { $0.topCandidates(1).first?.string }
        } catch {
            Log.lookup.error("Text recognition failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    private static func orientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
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
