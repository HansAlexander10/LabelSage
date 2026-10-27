import SwiftUI

/// Draws one frame of the rig into a `Canvas`: the parts from `rig.json` in its draw order, moved
/// by a `MascotPose`, plus the few vector props `Mascot.dc.html` draws as SVG (shadow, books,
/// disguise, products, notes, lens). Which layers show per state follows the prototype's
/// `.st-*` rules. Custom drawing: there is no native component for a rigged character.
struct MascotRenderer {
    let art: MascotArt

    private var rig: MascotRig { art.rig }

    /// Draws `state` in `pose`, scaled so the artboard height fills `size.height`.
    /// `found` (0...3) turns that many label lines green.
    func draw(_ state: MascotState, pose: MascotPose, found: Int, in context: inout GraphicsContext, size: CGSize) {
        let s = size.height / rig.artboard.height
        var stage = context
        stage.scaleBy(x: s, y: s)
        stage.translateBy(x: 0, y: -rig.artboard.originYOffset)

        var body = stage
        body.apply(pose.all, about: CGPoint(x: 528, y: 1226))
        body.apply(pose.lean, about: CGPoint(x: 526, y: 1030))
        var eyes = body
        eyes.apply(pose.eyes)

        for layer in rig.drawOrder {
            switch layer {
            case "shadow":
                if state == .sit { drawBooks(stage) } else { drawShadow(stage, pose.shadow) }
            case "cape":
                placeRig("cape", in: body.moved(pose.cape, about: CGPoint(x: 460, y: 620)))
            case "leg_l" where state != .sit:
                placeRig("leg_l", in: body.moved(pose.legL, about: CGPoint(x: 465, y: 1030)))
            case "leg_r" where state != .sit:
                placeRig("leg_r", in: body.moved(pose.legR, about: CGPoint(x: 590, y: 1030)))
            case "arm_l" where state != .thinking && state != .compare:
                placeRig("arm_l", in: body.moved(pose.armL, about: Self.shoulderL))
            case "tag":
                placeRig("tag", in: body)
            case "label_line_highlights":
                let count = state == .done ? 3 : min(max(found, 0), 3)
                for line in rig.parts[layer]?.lines.prefix(count) ?? [] where line.count == 3 {
                    var path = Path()
                    path.move(to: CGPoint(x: line[0], y: line[1]))
                    path.addLine(to: CGPoint(x: line[2], y: line[1]))
                    body.stroke(path, with: .color(Palette.found), style: Self.round(8))
                }
            case "string":
                placeRig("string", in: body.moved(pose.string, about: CGPoint(x: 529, y: 425)))
            case "eyes" where state != .done:
                var left = eyes.moved(pose.eyeL.transform, about: CGPoint(x: 450, y: 592))
                left.opacity = pose.eyeL.opacity
                placeRig("eye_l", in: left)
                var right = eyes.moved(pose.eyeR.transform, about: CGPoint(x: 603, y: 592))
                right.opacity = pose.eyeR.opacity
                placeRig("eye_r", in: right)
            case "brows":
                if state == .done {
                    // Happy closed eyes: the brows drawn at the eyes, 10 % bigger.
                    place("brow_l", in: body, at: CGPoint(x: 450, y: 592), scale: 1.1)
                    place("brow_r", in: body, at: CGPoint(x: 603, y: 592), scale: 1.1)
                } else {
                    let brows = eyes.moved(pose.brows)
                    placeRig("brow_l", in: brows)
                    placeRig("brow_r", in: brows.moved(pose.browR, about: CGPoint(x: 603, y: 512)))
                }
            case "mouth":
                drawMouth(state, pose: pose, in: body)
            case "arm_r":
                if state == .thinking {
                    placeRig("arm_l", in: body.moved(pose.armFold, about: Self.shoulderL))
                }
                if state != .reading && state != .compare {
                    placeRig("arm_r", in: body.moved(pose.armR, about: Self.shoulderR))
                }
            case "magnifier_arm":
                switch state {
                case .reading: drawMagnifier(pose, in: body)
                case .compare: drawProducts(pose, in: body)
                case .sit: drawBook(pose, in: body)
                default: break
                }
            case "question" where state == .thinking:
                placeRig("question", in: body.moved(pose.question, about: CGPoint(x: 830, y: 370)))
            case "sparks":
                if state == .hum { drawNotes(pose, in: stage) }
                if state == .done { drawSparks(pose, in: stage) }
            default:
                break
            }
        }
    }

    // MARK: Parts

    static let shoulderL = CGPoint(x: 316, y: 750)
    static let shoulderR = CGPoint(x: 737, y: 750)

    /// Draws part image `file` with its `anchor` (default: its center) at `at`, rotated and scaled about that point.
    private func place(_ file: String, in context: GraphicsContext, at: CGPoint, anchor: CGPoint? = nil,
                       rotate: Double = 0, scale: CGSize = CGSize(width: 1, height: 1)) {
        guard let part = art.images[file] else { return }
        var c = context
        c.translateBy(x: at.x, y: at.y)
        c.rotate(by: .degrees(rotate))
        c.scaleBy(x: scale.width, y: scale.height)
        let anchor = anchor ?? CGPoint(x: part.size.width / 2, y: part.size.height / 2)
        c.translateBy(x: -anchor.x, y: -anchor.y)
        c.draw(part.image, in: CGRect(origin: .zero, size: part.size))
    }

    private func place(_ file: String, in context: GraphicsContext, at: CGPoint, scale: Double) {
        place(file, in: context, at: at, scale: CGSize(width: scale, height: scale))
    }

    /// Draws the rig.json part `key` where the rig puts it.
    private func placeRig(_ key: String, in context: GraphicsContext) {
        guard let part = rig.parts[key], let at = part.at else { return }
        place(key, in: context, at: at, anchor: part.points["anchor"], rotate: part.rotate, scale: part.scale)
    }

    private func drawMouth(_ state: MascotState, pose: MascotPose, in body: GraphicsContext) {
        switch state {
        case .done:
            placeRig("mouth_open", in: body)
        case .hum:
            place("mouth_open", in: body, at: CGPoint(x: 540, y: 678), scale: 0.36)
        case .thinking, .guard:
            placeRig("mouth_flat", in: body.moved(pose.mouthFlat, about: CGPoint(x: 526, y: 675)))
        case .disguise:
            drawDisguise(pose, in: body)
        default:
            var smile = body
            smile.opacity = state == .wave ? 0 : pose.smileOpacity
            placeRig("mouth_smile", in: smile)
        }
        if state == .talk || state == .wave {
            var open = body
            open.opacity = state == .talk ? pose.talkMouthOpacity : 1
            place("mouth_open", in: open, at: CGPoint(x: 526, y: 674), scale: 0.78)
        }
    }

    // MARK: Props

    private func drawShadow(_ stage: GraphicsContext, _ layer: MascotPose.Layer) {
        var c = stage.moved(layer.transform, about: CGPoint(x: 528, y: 1228))
        c.opacity = layer.opacity
        c.fill(Self.ellipse(528, 1229, 170, 13), with: .color(Palette.shadow))
        c.fill(Self.ellipse(421, 1226, 44, 8), with: .color(Palette.contact))
        c.fill(Self.ellipse(634, 1226, 44, 8), with: .color(Palette.contact))
    }

    private func drawBooks(_ stage: GraphicsContext) {
        stage.fill(Self.ellipse(526, 1252, 300, 20), with: .color(Palette.shadow))
        let cover = Shapes.bookCover
        let edge = Shapes.bookEdge
        for (x, y, color) in [(520.0, 1214.0, Palette.bookGreen), (534, 1150, Palette.bookAmber), (522, 1088, Palette.bookOrange)] {
            var c = stage
            c.translateBy(x: x, y: y)
            Self.paint(c, cover, fill: color, stroke: Palette.outline, width: 7)
            c.stroke(edge, with: .color(Palette.paper), style: Self.round(9))
        }
    }

    private func drawMagnifier(_ pose: MascotPose, in body: GraphicsContext) {
        placeRig("arm_r", in: body.moved(pose.reach, about: Self.shoulderR))
        let lens = body.moved(pose.lens)
        // The prototype's reading pose (lens over the right eye, then the left); rig.json's static
        // `magnifier` placement is the older pose (open-questions Q22).
        place("magnifier", in: lens, at: CGPoint(x: 603, y: 592), anchor: rig.parts["magnifier"]?.points["anchor"],
              rotate: 34.9, scale: CGSize(width: -0.65, height: 0.65))
        var glass = lens
        let circle = Self.ellipse(603, 592, 62, 62)
        glass.clip(to: circle)
        glass.fill(circle, with: .color(Palette.lens.opacity(0.55)))
        for (file, opacity) in [("eye_r", pose.bigEyeR), ("eye_l", pose.bigEyeL)] {
            var eye = glass.moved(pose.pupil)
            eye.opacity = opacity
            place(file, in: eye, at: CGPoint(x: 603, y: 592), scale: 1.7)
        }
        lens.fill(Self.ellipse(582, 568, 12, 12), with: .color(.white.opacity(0.55)))
    }

    private func drawProducts(_ pose: MascotPose, in body: GraphicsContext) {
        let sides: [(arm: MascotTransform, product: MascotTransform, file: String, x: Double, color: Color)] = [
            (pose.compareArmL, pose.productL, "arm_l", 216, Palette.bookAmber),
            (pose.compareArmR, pose.productR, "arm_r", 837, Palette.bookGreen),
        ]
        let pack = Shapes.pack
        let window = Self.ellipse(0, -6, 34, 26)
        let text = Shapes.packText
        for side in sides {
            let shoulder = side.file == "arm_l" ? Self.shoulderL : Self.shoulderR
            let arm = body.moved(side.arm, about: shoulder)
            placeRig(side.file, in: arm)
            var c = arm.moved(side.product, about: CGPoint(x: side.x, y: 1005))
            c.translateBy(x: side.x, y: 855)
            c.scaleBy(x: 1.9, y: 1.9)
            Self.paint(c, pack, fill: side.color, stroke: Palette.outline, width: 4.5)
            Self.paint(c, window, fill: Palette.paper, stroke: Palette.outline, width: 4.5)
            c.stroke(text, with: .color(Palette.outline), style: Self.round(5))
        }
    }

    private func drawBook(_ pose: MascotPose, in body: GraphicsContext) {
        Self.paint(body, Shapes.bookCoverLeft, fill: Palette.bookBlue, stroke: Palette.outline, width: 7)
        Self.paint(body, Shapes.bookCoverRight, fill: Palette.bookBlue, stroke: Palette.outline, width: 7)
        Self.paint(body, Shapes.pageLeft, fill: Palette.page, stroke: Palette.outline, width: 7)
        Self.paint(body, Shapes.pageRight, fill: Palette.page, stroke: Palette.outline, width: 7)
        body.stroke(Shapes.bookLines,
                    with: .color(Palette.outline.opacity(0.55)), style: Self.round(5))
        var page = body.moved(pose.page.transform, about: CGPoint(x: 526, y: 820))
        page.opacity = pose.page.opacity
        Self.paint(page, Shapes.pageRight, fill: Palette.turningPage, stroke: Palette.outline, width: 6)
        body.fill(Self.ellipse(372, 842, 20, 20), with: .color(Palette.dark))
        body.fill(Self.ellipse(680, 842, 20, 20), with: .color(Palette.dark))
    }

    private func drawDisguise(_ pose: MascotPose, in body: GraphicsContext) {
        let mustache = body.moved(pose.mustache, about: CGPoint(x: 526, y: 700))
        Self.paint(mustache, Shapes.mustache,
                   fill: Palette.dark, stroke: Palette.outline, width: 5)
        mustache.stroke(Shapes.mustacheLines,
                        with: .color(Palette.mustacheLine.opacity(0.6)), style: Self.round(5))

        let nose = body.moved(pose.nose, about: CGPoint(x: 526, y: 666))
        Self.paint(nose, Self.ellipse(526, 666, 30, 30), fill: Palette.red, stroke: Palette.outline, width: 6)
        nose.stroke(Shapes.noseShine, with: .color(.white.opacity(0.85)), style: Self.round(7))

        let glasses = body.moved(pose.glasses, about: CGPoint(x: 526, y: 590))
        for frame in [Shapes.glassesArms, Shapes.glassesBridge] {
            glasses.stroke(frame, with: .color(Palette.outline), style: Self.round(19))
            glasses.stroke(frame, with: .color(Palette.red), style: Self.round(10))
        }
        for x in [450.0, 603] {
            let rim = Self.ellipse(x, 590, 50, 50)
            Self.paint(glasses, rim, fill: Palette.glassTint.opacity(0.16), stroke: Palette.outline, width: 22)
            glasses.stroke(rim, with: .color(Palette.red), style: Self.round(13))
        }
        glasses.stroke(Shapes.glassesShine,
                       with: .color(.white.opacity(0.7)), style: Self.round(5))
    }

    private func drawNotes(_ pose: MascotPose, in stage: GraphicsContext) {
        // Each note: its group placement, and its bounding-box center for the float transform.
        let notes: [(x: Double, y: Double, scale: Double, center: CGPoint, beamed: Bool)] = [
            (820, 480, 1.7, CGPoint(x: 834, y: 434), false),
            (880, 420, 1.5, CGPoint(x: 913, y: 374), true),
            (790, 400, 1.35, CGPoint(x: 801, y: 364), false),
        ]
        for (i, note) in notes.enumerated() {
            var c = stage.moved(pose.notes[i].transform, about: note.center)
            c.opacity = pose.notes[i].opacity
            c.translateBy(x: note.x, y: note.y)
            c.scaleBy(x: note.scale, y: note.scale)
            if note.beamed {
                for (x, y) in [(0.0, 0.0), (44, -10)] {
                    let head = Shapes.beamedHead.applying(CGAffineTransform(translationX: x, y: y))
                    Self.paint(c, head, fill: Palette.note, stroke: Palette.outline, width: 5)
                }
                c.stroke(Shapes.beamedStems, with: .color(Palette.outline), style: Self.round(5))
            } else {
                let head = Shapes.noteHead
                Self.paint(c, head, fill: Palette.note, stroke: Palette.outline, width: 5)
                c.stroke(Shapes.noteStem, with: .color(Palette.outline), style: Self.round(5))
            }
        }
    }

    private func drawSparks(_ pose: MascotPose, in stage: GraphicsContext) {
        guard let points = rig.parts["sparks"]?.points else { return }
        for (i, file) in ["spark_a", "spark_b", "spark_c", "dot_a", "dot_b"].enumerated() {
            guard let at = points[file] else { continue }
            var c = stage.moved(pose.sparks[i].transform, about: at)
            c.opacity = pose.sparks[i].opacity
            place(file, in: c, at: at)
        }
    }

    /// The prototype's SVG paths, parsed once.
    private enum Shapes {
        static let bookCover = Path(svg: "M-230 -26 L210 -34 Q228 -34 228 -16 L228 14 Q228 30 210 30 L-230 38 Q-246 38 -246 22 L-246 -10 Q-246 -26 -230 -26 Z")
        static let bookEdge = Path(svg: "M-200 2 L196 -6")
        static let pack = Path(svg: "M-52 -78 L-40 -86 L-28 -78 L-14 -86 L0 -78 L14 -86 L28 -78 L40 -86 L52 -78 Q58 0 52 78 L40 86 L28 78 L14 86 L0 78 L-14 86 L-28 78 L-40 86 L-52 78 Q-58 0 -52 -78 Z")
        static let packText = Path(svg: "M-18 -10 H18 M-14 4 H14")
        static let bookCoverLeft = Path(svg: "M526 742 Q446 712 360 730 L362 904 Q446 888 526 916 Z")
        static let bookCoverRight = Path(svg: "M526 742 Q606 712 692 730 L690 904 Q606 888 526 916 Z")
        static let pageLeft = Path(svg: "M526 752 Q450 726 376 740 L378 888 Q450 876 526 902 Z")
        static let pageRight = Path(svg: "M526 752 Q602 726 676 740 L674 888 Q602 876 526 902 Z")
        static let bookLines = Path(svg: "M402 780 H498 M402 806 H498 M402 832 H480 M554 780 H650 M554 806 H650 M554 832 H632")
        static let mustache = Path(svg: "M526 690 C 500 676, 470 678, 452 694 C 436 708, 424 730, 400 738 C 428 754, 470 744, 494 726 C 508 715, 518 709, 526 709 C 534 709, 544 715, 558 726 C 582 744, 624 754, 652 738 C 628 730, 616 708, 600 694 C 582 678, 552 676, 526 690 Z")
        static let mustacheLines = Path(svg: "M470 700 Q 488 694 500 702 M552 702 Q 564 694 582 700")
        static let noseShine = Path(svg: "M510 652 Q 520 644 532 646")
        static let glassesShine = Path(svg: "M424 566 Q 432 556 444 554 M577 566 Q 585 556 597 554")
        static let beamedStems = Path(svg: "M13 -4 L13 -62 L57 -72 L57 -14 M13 -50 L57 -60")
        static let noteStem = Path(svg: "M14 -4 L14 -66 Q30 -58 34 -40 Q36 -30 30 -24")
        static let glassesArms = Path(svg: "M398 584 L 326 572 M654 584 L 726 572")
        static let glassesBridge = Path(svg: "M498 584 Q 526 566 554 584")
        static let noteHead = Path(ellipseIn: CGRect(x: -17, y: -12, width: 34, height: 24))
            .applying(CGAffineTransform(rotationAngle: -22 * .pi / 180))
        static let beamedHead = Path(ellipseIn: CGRect(x: -16, y: -11, width: 32, height: 22))
            .applying(CGAffineTransform(rotationAngle: -22 * .pi / 180))
    }

    // MARK: Drawing helpers

    private static func round(_ width: Double) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }

    private static func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    /// SVG paint order: fill, then the stroke on top.
    private static func paint(_ c: GraphicsContext, _ path: Path, fill: Color, stroke: Color, width: Double) {
        c.fill(path, with: .color(fill))
        c.stroke(path, with: .color(stroke), style: round(width))
    }

    /// Illustration colors from `Mascot.dc.html`. They belong to the drawing, not the UI, so
    /// they are not tokens (and `Color(hex:)` stays private to Theme).
    enum Palette {
        private static func rgb(_ hex: UInt32) -> Color {
            Color(.sRGB, red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255)
        }

        static let outline = rgb(0x4f2c1e)
        static let dark = rgb(0x3d2318)
        static let found = rgb(0x52794a)
        static let shadow = rgb(0x3d2318).opacity(0.16)
        static let contact = rgb(0x3d2318).opacity(0.28)
        static let red = rgb(0xd8453a)
        static let glassTint = rgb(0xffe1dc)
        static let mustacheLine = rgb(0x6b4a3a)
        static let bookGreen = rgb(0x9cc77f)
        static let bookAmber = rgb(0xf0b54a)
        static let bookOrange = rgb(0xd9744f)
        static let bookBlue = rgb(0x3f7fbf)
        static let paper = rgb(0xfff8e7)
        static let page = rgb(0xfffaf0)
        static let turningPage = rgb(0xfffdf6)
        static let note = rgb(0xf5b53d)
        static let lens = rgb(0xcfe7df)
    }
}

extension GraphicsContext {
    /// Applies a CSS transform about `origin` (CSS `transform-origin`).
    mutating func apply(_ t: MascotTransform, about origin: CGPoint = .zero) {
        translateBy(x: origin.x + t.x, y: origin.y + t.y)
        rotate(by: .degrees(t.r))
        scaleBy(x: t.sx, y: t.sy)
        translateBy(x: -origin.x, y: -origin.y)
    }

    /// A copy with `t` applied about `origin`, for one nested SVG group.
    func moved(_ t: MascotTransform, about origin: CGPoint = .zero) -> GraphicsContext {
        var copy = self
        copy.apply(t, about: origin)
        return copy
    }
}

extension Path {
    /// Absolute SVG path data as the prototype writes it. Supported: the absolute commands
    /// `M L H V Q C Z`, with numbers separated by spaces or commas (or a minus sign), and implicit
    /// repeats of a command. Not supported: relative (lowercase) commands, `S T A`, exponents.
    /// Anything else trips an assertion in debug builds.
    init(svg: String) {
        self.init()
        var tokens: [String] = []
        var number = ""
        for char in svg {
            if char.isLetter {
                if !number.isEmpty { tokens.append(number); number = "" }
                tokens.append(String(char))
            } else if char == " " || char == "," {
                if !number.isEmpty { tokens.append(number); number = "" }
            } else if char == "-", !number.isEmpty {
                tokens.append(number)
                number = "-"
            } else {
                number.append(char)
            }
        }
        if !number.isEmpty { tokens.append(number) }

        var command = "M"
        var values: [Double] = []
        var current = CGPoint.zero
        func flush() {
            var v = values[...]
            func take(_ n: Int) -> [Double]? {
                guard v.count >= n else { return nil }
                defer { v = v.dropFirst(n) }
                return Array(v.prefix(n))
            }
            switch command {
            case "M", "L":
                var first = command == "M"
                while let p = take(2) {
                    current = CGPoint(x: p[0], y: p[1])
                    if first { move(to: current) } else { addLine(to: current) }
                    first = false
                }
            case "H":
                while let p = take(1) { current.x = p[0]; addLine(to: current) }
            case "V":
                while let p = take(1) { current.y = p[0]; addLine(to: current) }
            case "Q":
                while let p = take(4) {
                    current = CGPoint(x: p[2], y: p[3])
                    addQuadCurve(to: current, control: CGPoint(x: p[0], y: p[1]))
                }
            case "C":
                while let p = take(6) {
                    current = CGPoint(x: p[4], y: p[5])
                    addCurve(to: current, control1: CGPoint(x: p[0], y: p[1]), control2: CGPoint(x: p[2], y: p[3]))
                }
            case "Z":
                closeSubpath()
            default:
                assertionFailure("Path(svg:) does not support command \(command)")
            }
            if !v.isEmpty {
                assertionFailure("Path(svg:) has \(v.count) values left over after \(command)")
            }
        }
        for token in tokens {
            if let value = Double(token) {
                values.append(value)
            } else {
                assert(token.count == 1, "Path(svg:) cannot read \(token)")
                flush()
                command = token
                values = []
            }
        }
        flush()
    }
}
