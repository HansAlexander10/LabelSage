import SwiftUI

/// One CSS transform as `Mascot.dc.html` writes it: `translate(x, y) rotate(r) scale(sx, sy)`,
/// applied in that order about the layer's transform origin. Rotation is in degrees, clockwise
/// (SVG's y axis points down, as SwiftUI's does).
nonisolated struct MascotTransform: Equatable, Sendable {
    var x = 0.0
    var y = 0.0
    var r = 0.0
    var sx = 1.0
    var sy = 1.0

    /// CSS `transform: none`.
    static let none = MascotTransform()

    /// Uniform scale, as CSS `scale(s)`.
    init(x: Double = 0, y: Double = 0, r: Double = 0, s: Double) {
        self.init(x: x, y: y, r: r, sx: s, sy: s)
    }

    init(x: Double = 0, y: Double = 0, r: Double = 0, sx: Double = 1, sy: Double = 1) {
        self.x = x
        self.y = y
        self.r = r
        self.sx = sx
        self.sy = sy
    }
}

/// A value CSS interpolates between keyframes: a transform or an opacity.
nonisolated protocol MascotInterpolatable: Sendable {
    static func lerp(_ a: Self, _ b: Self, _ f: Double) -> Self
}

nonisolated extension Double: MascotInterpolatable {
    static func lerp(_ a: Double, _ b: Double, _ f: Double) -> Double { a + (b - a) * f }
}

nonisolated extension MascotTransform: MascotInterpolatable {
    static func lerp(_ a: MascotTransform, _ b: MascotTransform, _ f: Double) -> MascotTransform {
        MascotTransform(x: .lerp(a.x, b.x, f), y: .lerp(a.y, b.y, f), r: .lerp(a.r, b.r, f),
                        sx: .lerp(a.sx, b.sx, f), sy: .lerp(a.sy, b.sy, f))
    }
}

/// The timing function of one `@keyframes` animation, applied to each segment between two stops.
nonisolated enum MascotCurve: Sendable {
    /// tokens.json motion.easeInOut, `cubic-bezier(0.77, 0, 0.175, 1)`: every loop.
    case easeInOut
    /// tokens.json motion.easeOut, `cubic-bezier(0.23, 1, 0.32, 1)`: the jump, entrances, the disguise props.
    case easeOut
    /// `linear`: blinks, the eyes reading along the lines.
    case linear
    /// `steps(1, end)`: the talking mouth snaps open and shut.
    case step

    // Same control points as `Theme.motion.easeInOut` / `.easeOut`; those are `Animation`s, these
    // are sampled by hand because one frame mixes many tracks with different durations.
    private static let inOut = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.77, y: 0),
                                                endControlPoint: UnitPoint(x: 0.175, y: 1))
    private static let out = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.23, y: 1),
                                              endControlPoint: UnitPoint(x: 0.32, y: 1))

    /// Eased progress for linear progress `x` in 0...1.
    func value(_ x: Double) -> Double {
        switch self {
        case .easeInOut: Self.inOut.value(at: x)
        case .easeOut: Self.out.value(at: x)
        case .linear: x
        case .step: x < 1 ? 0 : 1
        }
    }
}

/// One CSS `@keyframes` block: stops at 0...100 %, sampled like a browser does.
nonisolated struct MascotKeyframes<Value: MascotInterpolatable>: Sendable {
    let stops: [Stop]

    struct Stop: Sendable {
        let offset: Double
        let value: Value
    }

    /// Mirrors the CSS: `[([0, 30, 100], a), ([12], b)]` is `0%,30%,100%{a} 12%{b}`.
    init(_ groups: [([Double], Value)]) {
        stops = groups
            .flatMap { group in group.0.map { Stop(offset: $0 / 100, value: group.1) } }
            .sorted { $0.offset < $1.offset }
    }

    /// The value at `progress` (0...1) through one iteration.
    func value(at progress: Double, curve: MascotCurve) -> Value {
        guard let first = stops.first, let last = stops.last else {
            preconditionFailure("MascotKeyframes needs at least one stop")
        }
        if progress <= first.offset { return first.value }
        if progress >= last.offset { return last.value }
        let next = stops.firstIndex { $0.offset > progress } ?? stops.count - 1
        let a = stops[next - 1], b = stops[next]
        let local = (progress - a.offset) / (b.offset - a.offset)
        return Value.lerp(a.value, b.value, curve.value(local))
    }

    /// An `infinite` animation of `duration` seconds starting `delay` seconds after the state
    /// began (negative delays start mid-cycle, as in CSS). Nil before it starts (CSS fill none).
    func loop(_ duration: Double, _ curve: MascotCurve = .easeInOut, delay: Double = 0, at time: Double) -> Value? {
        let local = time - delay
        guard local >= 0 else { return nil }
        return value(at: local.truncatingRemainder(dividingBy: duration) / duration, curve: curve)
    }

    /// A one-shot animation with `fill-mode: both`: holds the first stop before, the last after.
    func once(_ duration: Double, _ curve: MascotCurve, delay: Double = 0, at time: Double) -> Value {
        value(at: min(max((time - delay) / duration, 0), 1), curve: curve)
    }
}

/// Every `@keyframes tg-*` the 13 states use, transcribed from `Mascot.dc.html`. Pixel values are
/// artboard units (960 × 1210).
nonisolated enum MascotMotion {
    typealias T = MascotTransform
    typealias Moves = MascotKeyframes<MascotTransform>
    typealias Fades = MascotKeyframes<Double>

    // Shared
    static let blink = Moves([([0, 93, 100], T()), ([96], T(sy: 0.12))])
    static let cape = Moves([([0, 100], T(r: -7)), ([50], T(r: 7, sx: 0.94, sy: 1.05))])
    static let string = Moves([([0, 100], T(r: -9)), ([50], T(r: 9))])
    static let armSwayL = Moves([([0, 100], T(r: 5)), ([50], T(r: -5))])
    static let armSwayR = Moves([([0, 100], T(r: -5)), ([50], T(r: 5))])

    // idle, disguise
    static let idle = Moves([([0, 100], T(r: -2)), ([25, 75], T(sx: 1.01, sy: 1.022)), ([50], T(r: 2))])
    static let glance = Moves([([0, 34, 78, 100], T()), ([40, 54], T(x: -11, y: -2)), ([60, 72], T(x: 11, y: -2))])
    static let sneak = Moves([([0, 8, 92, 100], T(y: 2)), ([16, 40], T(x: -18, y: 2)), ([48, 52], T(y: 2)), ([60, 84], T(x: 18, y: 2))])
    static let twitch = Moves([([0, 62, 78, 100], T()), ([66], T(r: -5, sy: 1.06)), ([70], T(r: 4)), ([74], T(r: -3))])
    static let honk = Moves([([0, 62, 80, 100], T()), ([67], T(s: 1.12)), ([74], T(s: 0.96))])
    static let specsNudge = Moves([([0, 20, 34, 100], T()), ([25], T(y: -7)), ([29], T(y: 1))])

    // hum
    static let humBody = Moves([([0, 100], T(r: -6)), ([25, 75], T(y: -10, sx: 0.99, sy: 1.02)), ([50], T(r: 6))])
    static let humLegL = Moves([([0, 50, 100], T()), ([75], T(r: 14))])
    static let humLegR = Moves([([0, 50, 100], T()), ([25], T(r: -14))])
    static let humArmL = Moves([([0, 100], T(r: 12)), ([50], T(r: -10))])
    static let humArmR = Moves([([0, 100], T(r: 10)), ([50], T(r: -12))])
    static let humEyes = Moves([([0, 100], T(x: 9, y: -11)), ([50], T(x: 4, y: -13))])
    static let noteMove = Moves([([0], T(r: -8, s: 0.8)), ([100], T(x: 34, y: -110, r: 10, s: 1.05))])
    static let noteFade = Fades([([0], 0), ([20, 70], 1), ([100], 0)])

    // reading
    static let lens = Moves([([0, 30, 100], T()), ([12], T(x: -8)), ([22], T(x: 7)), ([42, 88], T(x: -153)), ([56], T(x: -161)), ([72], T(x: -146))])
    static let reach = Moves([([0, 30, 100], T(r: 100, s: 0.75)), ([12], T(r: 101, s: 0.77)), ([22], T(r: 99, s: 0.73)),
                              ([42, 88], T(r: 104.8, s: 1.3)), ([56], T(r: 104.9, s: 1.33)), ([72], T(r: 104.7, s: 1.28))])
    static let bigR = Fades([([0, 28, 100], 1), ([33, 97], 0)])
    static let bigL = Fades([([0, 39, 91, 100], 0), ([44, 86], 1)])
    static let eyeRUnder = Fades([([0, 30, 100], 0), ([35, 95], 1)])
    static let eyeLUnder = Fades([([0, 38, 92, 100], 1), ([42, 88], 0)])
    static let pupil = Moves([([0, 100], T(x: -5, y: 3)), ([50], T(x: 6, y: 3))])
    static let readBody = Moves([([0, 24, 46, 82, 100], T()), ([36], T(r: -2, sy: 0.985)), ([94], T(r: 2, sy: 0.985))])
    static let readLook = Moves([([0, 30, 100], T(x: 4, y: 6)), ([42, 88], T(x: -4, y: 6))])
    static let readBrow = Moves([([0, 40, 60, 100], T()), ([48], T(y: -8))])

    // done
    static let jump = Moves([([0, 100], T()), ([18], T(y: 16, sx: 1.07, sy: 0.91)), ([55], T(y: -120, sx: 0.96, sy: 1.05)), ([82], T(y: 8, sx: 1.04, sy: 0.96))])
    static let hop = Moves([([0, 18, 98, 100], T(r: -5)), ([24], T(r: -3, sx: 1.05, sy: 0.93)), ([33], T(y: -34, sx: 0.97, sy: 1.04)),
                            ([42], T(r: 5, sx: 1.05, sy: 0.94)), ([48, 68], T(r: 5)), ([74], T(r: 3, sx: 1.05, sy: 0.93)),
                            ([83], T(y: -34, sx: 0.97, sy: 1.04)), ([92], T(r: -5, sx: 1.05, sy: 0.94))])
    static let kickR = Moves([([0, 24, 92, 100], T(r: -24)), ([33, 83], T(r: -8)), ([42, 74], T())])
    static let kickL = Moves([([0, 24, 92, 100], T()), ([33, 83], T(r: 8)), ([42, 74], T(r: 24))])
    static let waveL = Moves([([0, 100], T(r: 108)), ([50], T(r: 140))])
    static let waveR = Moves([([0, 100], T(r: -108)), ([50], T(r: -140))])
    static let shadowJump = Moves([([0, 100], T()), ([55], T(s: 0.65))])
    static let shadowJumpFade = Fades([([0, 100], 1), ([55], 0.45)])
    static let shadowHop = Moves([([0, 24, 42, 74, 92, 100], T()), ([33, 83], T(s: 0.78))])
    static let shadowHopFade = Fades([([0, 24, 42, 74, 92, 100], 1), ([33, 83], 0.55)])
    static let spark = Moves([([0], T(s: 0.6)), ([60], T(s: 1.15)), ([100], T())])
    static let sparkFade = Fades([([0], 0), ([60, 100], 1)])
    static let twinkle = Moves([([0, 100], T()), ([50], T(r: 20, s: 0.78))])
    static let twinkleFade = Fades([([0, 100], 1), ([50], 0.6)])

    // thinking
    static let ponder = Moves([([0, 100], T(r: -2)), ([50], T(r: 2.5))])
    static let tap = Moves([([0, 16, 32, 46, 100], T(r: 123, s: 0.8)), ([8, 24], T(r: 115, s: 0.8))])
    static let thinkEyes = Moves([([0, 100], T(x: -8, y: -11)), ([45, 90], T(x: 9, y: -12))])
    static let brow = Moves([([0, 8, 58, 100], T()), ([16, 50], T(y: -14, r: -6))])
    static let hmm = Moves([([0, 30, 100], T()), ([45, 80], T(x: 8))])
    static let question = Moves([([0, 100], T(r: -8)), ([50], T(y: -20, r: 8, s: 1.08))])

    // talk, wave, point, listen
    static let mouthOpen = Fades([([0, 40, 100], 0), ([48, 88], 1)])
    static let mouthShut = Fades([([0, 40, 100], 1), ([48, 88], 0)])
    static let talkBody = Moves([([0, 100], T(r: -1)), ([50], T(r: 1, sx: 1.008, sy: 1.016))])
    static let talkArm = Moves([([0, 100], T(r: 4)), ([30], T(r: -26)), ([60], T(r: -14))])
    static let talkBrow = Moves([([0, 100], T()), ([30, 60], T(y: -8))])
    static let hi = Moves([([0, 100], T(r: -118)), ([50], T(r: -146))])
    static let hiBody = Moves([([0, 100], T(r: 1.5)), ([50], T(r: 3.5))])
    static let point = Moves([([0, 18, 34, 40, 100], T(r: -76)), ([10, 26], T(r: -88))])
    static let pointBody = Moves([([0, 100], T(r: 2.5)), ([50], T(r: 3.5))])
    static let nod = Moves([([0, 30, 60, 100], T()), ([12, 42], T(r: 1.5, sx: 1.01, sy: 0.975))])
    static let listenEyes = Moves([([0, 100], T(x: 6, y: 10)), ([50], T(x: -4, y: 10))])

    // compare
    static let cmpL = Moves([([0, 10, 45, 55, 90, 100], T(r: 48, s: 0.85)), ([22, 38], T(r: 104, s: 0.85))])
    static let prodL = Moves([([0, 10, 45, 55, 90, 100], T(r: -48)), ([22, 38], T(r: -104))])
    static let cmpR = Moves([([0, 10, 45, 55, 90, 100], T(r: -44, s: 0.85)), ([67, 83], T(r: -99, s: 0.85))])
    static let prodR = Moves([([0, 10, 45, 55, 90, 100], T(r: 44)), ([67, 83], T(r: 99))])
    static let cmpBody = Moves([([0, 10, 45, 55, 90, 100], T()), ([22, 38], T(r: -5)), ([67, 83], T(r: 5))])
    static let cmpBlink = Moves([([0, 8, 12, 43, 47, 53, 57, 88, 92, 100], T()), ([10, 45, 55, 90], T(sy: 0.1))])
    static let cmpEyes = Moves([([0, 10, 45, 55, 90, 100], T(y: 6)), ([22, 38], T(x: -32, y: -14)), ([67, 83], T(x: 32, y: -14))])
    static let cmpBrow = Moves([([0, 55, 90, 100], T()), ([67, 83], T(y: -12))])

    // sit
    static let sitRead = Moves([([0, 100], T(y: 150)), ([50], T(y: 150, r: 1.5, sy: 0.99))])
    static let sitEyes = Moves([([0], T(x: -10, y: 16)), ([40], T(x: 10, y: 16)), ([46], T(x: -10, y: 22)), ([86], T(x: 10, y: 22)), ([92, 100], T(x: -10, y: 16))])
    static let page = Moves([([0, 78], T()), ([90], T(sx: 0.05)), ([91, 100], T(sx: -1))])
    static let pageFade = Fades([([0, 90], 1), ([96, 100], 0)])
}
