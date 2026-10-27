import Foundation

/// Every moving layer of the rig at one moment: what `MascotView` draws for a state at a time.
/// Layer names follow the `tg-*` classes in `Mascot.dc.html`; which layers show per state is the
/// renderer's job (`MascotRenderer`).
nonisolated struct MascotPose: Equatable, Sendable {
    typealias T = MascotTransform

    /// One layer that both moves and fades.
    struct Layer: Equatable, Sendable {
        var transform = T.none
        var opacity = 1.0
    }

    /// The whole figure, about the feet (`tg-all`).
    var all = T.none
    /// The body above the ground line (`tg-lean`).
    var lean = T.none
    var shadow = Layer()
    var cape = T.none
    var string = T.none
    var legL = T.none
    var legR = T.none
    var armL = T.none
    var armR = T.none
    /// The left arm folded across the body in `thinking`.
    var armFold = T(r: -92)
    /// Both eyes and brows together (`tg-eyes`).
    var eyes = T.none
    /// Blink of each eye; opacity hides the eye under the magnifier in `reading`.
    var eyeL = Layer()
    var eyeR = Layer()
    /// Brows together (`guard` lowers them).
    var brows = T.none
    var browR = T.none
    var smileOpacity = 1.0
    var talkMouthOpacity = 1.0
    var mouthFlat = T.none
    // reading
    var reach = T.none
    var lens = T.none
    var bigEyeR = 1.0
    var bigEyeL = 0.0
    var pupil = T.none
    // compare
    var compareArmL = T.none
    var productL = T.none
    var compareArmR = T.none
    var productR = T.none
    // sit
    var page = Layer()
    // thinking
    var question = T.none
    // disguise
    var mustache = T.none
    var nose = T.none
    var glasses = T.none
    // hum notes, done sparks (hidden until they start)
    var notes = Array(repeating: Layer(opacity: 0), count: 3)
    var sparks = Array(repeating: Layer(opacity: 0), count: 5)

    /// Note start delays in `hum` (`.n2`, `.n3`).
    static let noteDelays = [0.0, 0.8, 1.6]
    /// Spark entrance and twinkle delays in `done` (`.tg-spark.a` … `.e`).
    static let sparkDelays: [(enter: Double, twinkle: Double)] = [(0, 0.7), (0.08, 0.9), (0.16, 1.1), (0.24, 0.8), (0.3, 1.0)]
    /// The jump in `done` lasts 620 ms; the hops start after it.
    static let jumpDuration = 0.62

    /// The pose of `state` at `time` seconds after it began. `frozen` (Reduce Motion) draws the
    /// first key frame, with the few overrides `Mascot.dc.html` makes under
    /// `prefers-reduced-motion` so the frozen pose still reads (sparks shown, arms up).
    static func at(_ state: MascotState, time t: Double, frozen: Bool = false) -> MascotPose {
        typealias M = MascotMotion
        var p = MascotPose()
        // guard: still and serious. Nothing moves, brows down (open-questions Q21).
        if state == .guard {
            p.brows = T(y: 14)
            return p
        }
        let t = frozen ? 0 : t
        p.cape = M.cape.loop(2.4, at: t) ?? .none
        p.string = M.string.loop(2.4, delay: -0.4, at: t) ?? .none
        let blink = M.blink.loop(4.2, .linear, at: t) ?? .none
        p.eyeL.transform = blink
        p.eyeR.transform = blink

        func sway() {
            p.armL = M.armSwayL.loop(2.4, delay: -0.3, at: t) ?? .none
            p.armR = M.armSwayR.loop(2.4, delay: -0.3, at: t) ?? .none
        }

        switch state {
        case .idle:
            p.all = M.idle.loop(4.8, at: t) ?? .none
            p.eyes = M.glance.loop(6, at: t) ?? .none
            sway()
        case .hum:
            p.all = M.humBody.loop(1.6, at: t) ?? .none
            p.legL = M.humLegL.loop(1.6, at: t) ?? .none
            p.legR = M.humLegR.loop(1.6, at: t) ?? .none
            p.armL = M.humArmL.loop(1.6, at: t) ?? .none
            p.armR = M.humArmR.loop(1.6, at: t) ?? .none
            p.eyes = M.humEyes.loop(3.2, at: t) ?? .none
            for (i, delay) in noteDelays.enumerated() {
                p.notes[i] = Layer(transform: M.noteMove.loop(2.4, .easeOut, delay: delay, at: t) ?? .none,
                                   opacity: M.noteFade.loop(2.4, .easeOut, delay: delay, at: t) ?? 0)
            }
        case .reading:
            p.lean = T(r: -3)
            p.all = M.readBody.loop(3.2, at: t) ?? .none
            p.lens = M.lens.loop(3.2, at: t) ?? .none
            p.reach = M.reach.loop(3.2, at: t) ?? .none
            p.bigEyeR = M.bigR.loop(3.2, at: t) ?? 1
            p.bigEyeL = M.bigL.loop(3.2, at: t) ?? 0
            p.eyeR.opacity = M.eyeRUnder.loop(3.2, at: t) ?? 1
            p.eyeL.opacity = M.eyeLUnder.loop(3.2, at: t) ?? 1
            p.pupil = M.pupil.loop(0.9, at: t) ?? .none
            p.eyes = M.readLook.loop(3.2, at: t) ?? .none
            p.browR = M.readBrow.loop(1.6, at: t) ?? .none
            p.armL = M.armSwayL.loop(2.4, delay: -0.3, at: t) ?? .none
        case .done:
            let hop = jumpDuration
            p.all = M.hop.loop(2, delay: hop, at: t) ?? M.jump.once(hop, .easeOut, at: t)
            p.legR = M.kickR.loop(2, delay: hop, at: t) ?? .none
            p.legL = M.kickL.loop(2, delay: hop, at: t) ?? .none
            p.shadow = Layer(transform: M.shadowHop.loop(2, delay: hop, at: t) ?? M.shadowJump.once(hop, .easeOut, at: t),
                             opacity: M.shadowHopFade.loop(2, delay: hop, at: t) ?? M.shadowJumpFade.once(hop, .easeOut, at: t))
            p.armL = M.waveL.loop(1, delay: hop, at: t) ?? T(r: 116)
            p.armR = M.waveR.loop(1, delay: 1.07, at: t) ?? T(r: -116)
            for (i, delay) in sparkDelays.enumerated() {
                p.sparks[i] = Layer(
                    transform: M.twinkle.loop(1.2, delay: delay.twinkle, at: t) ?? M.spark.once(0.52, .easeOut, delay: delay.enter, at: t),
                    opacity: M.twinkleFade.loop(1.2, delay: delay.twinkle, at: t) ?? M.sparkFade.once(0.52, .easeOut, delay: delay.enter, at: t))
            }
            if frozen {
                p.armL = T(r: 124)
                p.armR = T(r: -124)
                p.sparks = Array(repeating: Layer(), count: 5)
            }
        case .thinking:
            p.all = M.ponder.loop(3.2, at: t) ?? .none
            p.armR = M.tap.loop(3.2, at: t) ?? .none
            p.eyes = frozen ? T(x: 8, y: -12) : M.thinkEyes.loop(3.2, at: t) ?? .none
            p.browR = M.brow.loop(3.2, at: t) ?? .none
            p.mouthFlat = M.hmm.loop(3.2, at: t) ?? .none
            p.question = M.question.loop(1.6, at: t) ?? .none
        case .talk:
            p.all = M.talkBody.loop(1.2, at: t) ?? .none
            p.talkMouthOpacity = M.mouthOpen.loop(0.5, .step, at: t) ?? 1
            p.smileOpacity = M.mouthShut.loop(0.5, .step, at: t) ?? 1
            p.armR = M.talkArm.loop(1.8, at: t) ?? .none
            p.armL = M.armSwayL.loop(2.4, at: t) ?? .none
            p.browR = M.talkBrow.loop(1.8, at: t) ?? .none
        case .wave:
            p.armR = M.hi.loop(0.6, at: t) ?? .none
            p.all = M.hiBody.loop(1.2, at: t) ?? .none
            p.armL = M.armSwayL.loop(2.4, at: t) ?? .none
        case .point:
            p.armR = M.point.loop(2.4, at: t) ?? .none
            p.all = M.pointBody.loop(2.4, at: t) ?? .none
            p.eyes = T(x: 10, y: -2)
            p.armL = M.armSwayL.loop(2.4, at: t) ?? .none
        case .listen:
            p.all = M.nod.loop(2.4, at: t) ?? .none
            p.eyes = M.listenEyes.loop(3.2, at: t) ?? .none
            p.armL = M.armSwayL.loop(2.4, at: t) ?? .none
            p.armR = M.armSwayR.loop(2.4, at: t) ?? .none
        case .compare:
            p.compareArmL = M.cmpL.loop(3.6, at: t) ?? .none
            p.productL = M.prodL.loop(3.6, at: t) ?? .none
            p.compareArmR = M.cmpR.loop(3.6, at: t) ?? .none
            p.productR = M.prodR.loop(3.6, at: t) ?? .none
            p.all = M.cmpBody.loop(3.6, at: t) ?? .none
            p.eyes = M.cmpEyes.loop(3.6, at: t) ?? .none
            let blink = M.cmpBlink.loop(3.6, .linear, at: t) ?? .none
            p.eyeL.transform = blink
            p.eyeR.transform = blink
            p.browR = M.cmpBrow.loop(3.6, at: t) ?? .none
        case .sit:
            p.lean = M.sitRead.loop(3.6, at: t) ?? .none
            p.eyes = M.sitEyes.loop(3.6, .linear, at: t) ?? .none
            p.page = Layer(transform: M.page.loop(3.6, at: t) ?? .none, opacity: M.pageFade.loop(3.6, .linear, at: t) ?? 1)
            p.armL = T(r: -58, s: 0.55)
            p.armR = T(r: 58, s: 0.55)
        case .disguise:
            p.all = M.idle.loop(4.8, at: t) ?? .none
            sway()
            p.eyes = M.sneak.loop(4.8, at: t) ?? .none
            p.mustache = M.twitch.loop(2.4, .easeOut, at: t) ?? .none
            p.nose = M.honk.loop(2.4, .easeOut, at: t) ?? .none
            p.glasses = M.specsNudge.loop(4.8, .easeOut, at: t) ?? .none
        case .guard:
            break
        }
        return p
    }
}
