import SwiftUI
import Synchronization
import UIKit

/// `Resources/Mascot/rig.json`: the artboard, the draw order and where each part sits.
nonisolated struct MascotRig: Decodable, Sendable {
    let artboard: Artboard
    let drawOrder: [String]
    let parts: [String: Part]

    struct Artboard: Decodable, Sendable {
        let width: Double
        let height: Double
        /// The artboard's top edge in stage units (the prototype's viewBox starts at y 60).
        let originYOffset: Double

        enum CodingKeys: String, CodingKey {
            case width, height
            case originYOffset = "origin_y_offset"
        }
    }

    /// One part entry. Every two-number array (`anchor`, `at`, `center_at`, `spark_a`…) lands
    /// in `points`; `scale` is a number or an `[x, y]` pair.
    struct Part: Decodable, Sendable {
        let points: [String: CGPoint]
        let rotate: Double
        let scale: CGSize
        let lines: [[Double]]

        /// Where the part's `anchor` (or its center, for `center_at` parts) goes on the stage.
        var at: CGPoint? { points["at"] ?? points["center_at"] }

        private struct Key: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            var points: [String: CGPoint] = [:]
            for key in container.allKeys {
                if let pair = try? container.decode([Double].self, forKey: key), pair.count == 2 {
                    points[key.stringValue] = CGPoint(x: pair[0], y: pair[1])
                }
            }
            self.points = points
            rotate = try container.decodeIfPresent(Double.self, forKey: Key(stringValue: "rotate")) ?? 0
            if let uniform = try? container.decode(Double.self, forKey: Key(stringValue: "scale")) {
                scale = CGSize(width: uniform, height: uniform)
            } else if let pair = try? container.decode([Double].self, forKey: Key(stringValue: "scale")), pair.count == 2 {
                scale = CGSize(width: pair[0], height: pair[1])
            } else {
                scale = CGSize(width: 1, height: 1)
            }
            lines = (try? container.decode([[Double]].self, forKey: Key(stringValue: "lines"))) ?? []
        }
    }

    enum CodingKeys: String, CodingKey {
        case artboard, parts
        case drawOrder = "draw_order_back_to_front"
    }
}

/// The rig plus its part images, loaded and decoded once from the bundle's `Mascot` folder.
nonisolated struct MascotArt: Sendable {
    /// The part images MascotView draws. `parts-full`: one image pixel per stage unit, as
    /// rig.json's note says ("stage units = pixels of the parts at full size"), so every part
    /// is placed with the rig's numbers unchanged and stays sharp up to the hero size.
    static let partsFolder = "Mascot/parts-full"

    let rig: MascotRig
    /// Part images by file name (without `.png`), with their size in stage units.
    let images: [String: (image: Image, size: CGSize)]
    /// The full-size decoded images, the source for `scaled(pixelsPerUnit:)`.
    private var sources: [String: UIImage] = [:]

    /// Loaded on first use; nil only if the bundle is missing `rig.json` (MascotView then draws nothing).
    static let shared: MascotArt? = try? load()

    /// Starts loading `shared` off the main thread, once, so the first frame does not decode PNGs.
    /// Every `MascotView` calls it on appear; the app root may call it earlier.
    static func warm() {
        guard !warmed.withLock({ started in defer { started = true }; return started }) else { return }
        Task.detached(priority: .userInitiated) { Perf.measure("launch.mascotArt") { _ = shared } }
    }

    private static let warmed = Mutex(false)

    enum LoadError: Error {
        case missing(String)
    }

    static func load(from bundle: Bundle = .main) throws -> MascotArt {
        guard let rigURL = bundle.url(forResource: "rig", withExtension: "json", subdirectory: "Mascot") else {
            throw LoadError.missing("Mascot/rig.json")
        }
        let rig = try JSONDecoder().decode(MascotRig.self, from: Data(contentsOf: rigURL))
        let urls = bundle.urls(forResourcesWithExtension: "png", subdirectory: partsFolder) ?? []
        var images: [String: (image: Image, size: CGSize)] = [:]
        var sources: [String: UIImage] = [:]
        for url in urls {
            // Decoded now (`preparingForDisplay`), not on the first draw.
            guard let loaded = UIImage(contentsOfFile: url.path) else { continue }
            let image = loaded.preparingForDisplay() ?? loaded
            let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
            let name = url.deletingPathExtension().lastPathComponent
            images[name] = (Image(uiImage: image).interpolation(.high), pixels)
            sources[name] = image
        }
        guard !images.isEmpty else { throw LoadError.missing(partsFolder) }
        var art = MascotArt(rig: rig, images: images)
        art.sources = sources
        return art
    }

    // MARK: Pre-scaled parts

    /// Parts drawn bigger than their rig size (the eyes under the reading lens, 1.7×) keep this
    /// much more resolution, so they stay as sharp as before.
    private static let headroom: [String: CGFloat] = ["eye_l": 2, "eye_r": 2]

    private static let scaledCache = Mutex<[Int: MascotArt]>([:])

    /// The same art with every part resampled once to `pixelsPerUnit` (the on-screen scale times the
    /// display scale) and cached, so a frame draws small images instead of resampling the full
    /// 453 × 711 PNGs. Sizes stay in stage units, so the renderer places them unchanged.
    func scaled(pixelsPerUnit: CGFloat) -> MascotArt {
        guard pixelsPerUnit < 1, !sources.isEmpty else { return self }
        let key = Int((pixelsPerUnit * 1000).rounded())
        if let hit = Self.scaledCache.withLock({ $0[key] }) { return hit }
        var scaledImages = images
        for (name, source) in sources {
            guard let size = images[name]?.size else { continue }
            let factor = min(1, pixelsPerUnit * (Self.headroom[name] ?? 1))
            let pixels = CGSize(width: max(1, (size.width * factor).rounded(.up)),
                                height: max(1, (size.height * factor).rounded(.up)))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let small = UIGraphicsImageRenderer(size: pixels, format: format).image { context in
                context.cgContext.interpolationQuality = .high
                source.draw(in: CGRect(origin: .zero, size: pixels))
            }
            scaledImages[name] = (Image(uiImage: small).interpolation(.high), size)
        }
        let art = MascotArt(rig: rig, images: scaledImages)
        Self.scaledCache.withLock { $0[key] = art }
        return art
    }
}
