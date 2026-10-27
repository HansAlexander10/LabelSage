import SwiftUI
import Testing
@testable import LabelSage

/// The one-mascot rule: a host claims him, the others render nothing.
@MainActor
struct MascotPresenceTests {
    @Test func nobodyHoldsHimAtFirst() {
        let presence = MascotPresence()
        #expect(presence.holder == nil)
        #expect(!presence.shows(.dock))
    }

    @Test func theLatestClaimShowsHimAndTheOthersDoNot() {
        let presence = MascotPresence()
        presence.claim(.dock)
        #expect(presence.shows(.dock))
        presence.claim(.sheet)
        #expect(presence.shows(.sheet))
        #expect(!presence.shows(.dock))
        #expect(!presence.shows(.tip))
    }

    @Test func releasingGivesHimBackToThePreviousHost() {
        let presence = MascotPresence()
        presence.claim(.dock)
        presence.claim(.sheet)
        presence.release(.sheet)
        #expect(presence.holder == .dock)
        presence.release(.dock)
        #expect(presence.holder == nil)
    }

    @Test func releasingAHostThatDoesNotHoldHimChangesNothing() {
        let presence = MascotPresence()
        presence.claim(.dock)
        presence.claim(.tip)
        presence.release(.dock)
        #expect(presence.holder == .tip)
        presence.release(.sheet)
        #expect(presence.holder == .tip)
        presence.release(.tip)
        #expect(presence.holder == nil)
    }

    @Test func claimingAgainMovesAHostBackOnTop() {
        let presence = MascotPresence()
        presence.claim(.dock)
        presence.claim(.sheet)
        presence.claim(.dock)
        #expect(presence.claims == [.sheet, .dock])
        #expect(presence.shows(.dock))
    }
}

/// Sampling the CSS keyframes, and the poses that must hold still.
struct MascotMotionTests {
    typealias T = MascotTransform

    @Test func keyframesHitTheirStopsAndEaseBetween() {
        let string = MascotMotion.string // 0,100: -9°, 50: 9°
        #expect(string.value(at: 0, curve: .easeInOut).r == -9)
        #expect(string.value(at: 0.5, curve: .easeInOut).r == 9)
        #expect(string.value(at: 1, curve: .easeInOut).r == -9)
        // Halfway through a segment, the curve decides how far along the value is.
        let half = MascotCurve.easeInOut.value(0.5)
        #expect(half > 0.55 && half < 0.65) // cubic-bezier(0.77, 0, 0.175, 1) at x 0.5
        #expect(abs(string.value(at: 0.25, curve: .easeInOut).r - (-9 + 18 * half)) < 0.0001)
        // and slow at the start: 10 % into a segment moves far less than 10 % of the way.
        #expect(string.value(at: 0.05, curve: .easeInOut).r < -8.5)
    }

    @Test func loopsRepeatAndHonorDelays() {
        let blink = MascotMotion.blink
        #expect(blink.loop(4.2, .linear, at: 4.2 * 0.96)?.sy == 0.12)
        #expect(abs((blink.loop(4.2, .linear, at: 4.2 + 4.2 * 0.96)?.sy ?? 1) - 0.12) < 0.001)
        // Before a positive delay, the animation has not started (CSS fill none).
        #expect(MascotMotion.waveL.loop(1, delay: 0.62, at: 0.3) == nil)
        // A negative delay starts mid-cycle.
        #expect(MascotMotion.armSwayL.loop(2.4, delay: -1.2, at: 0)?.r == -5)
    }

    @Test func stepsSnapTheTalkingMouth() {
        // steps(1, end): holds the start value of each segment until its end.
        #expect(MascotMotion.mouthOpen.value(at: 0.45, curve: .step) == 0)
        #expect(MascotMotion.mouthOpen.value(at: 0.5, curve: .step) == 1)
    }

    @Test func guardStaysStill() {
        let first = MascotPose.at(.guard, time: 0)
        for time in stride(from: 0.1, through: 10, by: 0.7) {
            #expect(MascotPose.at(.guard, time: time) == first)
        }
        #expect(first.brows == T(y: 14))
    }

    @Test func everyOtherStateMoves() {
        for state in MascotState.allCases where state != .guard {
            let poses = stride(from: 0.0, through: 5, by: 0.37).map { MascotPose.at(state, time: $0) }
            #expect(Set(poses.map { "\($0)" }).count > 1, "\(state) should animate")
        }
    }

    @Test func reduceMotionFreezesOnTheFirstKeyFrame() {
        for state in MascotState.allCases {
            #expect(MascotPose.at(state, time: 3.3, frozen: true) == MascotPose.at(state, time: 0, frozen: true))
        }
        // Frozen `done` shows its sparkles and raised arms, as the prototype's reduced-motion rules do.
        let done = MascotPose.at(.done, time: 0, frozen: true)
        #expect(done.sparks.allSatisfy { $0.opacity == 1 })
        #expect(done.armL == T(r: 124))
    }

    @Test func doneJumpsOnceThenHops() {
        // Mid-jump the body is up in the air; after 620 ms the hop loop takes over.
        #expect(MascotPose.at(.done, time: 0.62 * 0.55).all.y == -120)
        #expect(MascotPose.at(.done, time: 0.62).all == MascotMotion.hop.value(at: 0, curve: .easeInOut))
    }
}

/// rig.json and the part images in the app bundle.
@MainActor
struct MascotRigTests {
    @Test func rigAndPartsLoad() throws {
        let art = try MascotArt.load()
        #expect(art.rig.artboard.width == 960)
        #expect(art.rig.artboard.height == 1210)
        #expect(art.rig.drawOrder.first == "shadow")
        #expect(art.rig.drawOrder.count == 15)
        #expect(art.rig.parts["magnifier"]?.scale == CGSize(width: -0.72, height: 0.72))
        #expect(art.rig.parts["cape"]?.rotate == -40)
        #expect(art.rig.parts["sparks"]?.points["spark_b"] == CGPoint(x: 860, y: 320))
        #expect(art.rig.parts["label_line_highlights"]?.lines.count == 3)
    }

    @Test func everyDrawnPartHasAnImageAtStageSize() throws {
        let art = try MascotArt.load()
        let drawn = ["tag", "cape", "string", "leg_l", "leg_r", "arm_l", "arm_r", "eye_l", "eye_r", "brow_l", "brow_r",
                     "mouth_smile", "mouth_open", "mouth_flat", "magnifier", "question",
                     "spark_a", "spark_b", "spark_c", "dot_a", "dot_b"]
        for name in drawn {
            #expect(art.images[name] != nil, "missing \(name).png")
        }
        // parts-full: one pixel per stage unit (the prototype draws the tag 453 × 711).
        #expect(art.images["tag"]?.size == CGSize(width: 453, height: 711))
    }

    @Test func svgPathsParse() {
        let path = Path(svg: "M-18 -10 H18 M-14 4 H14")
        #expect(path.boundingRect == CGRect(x: -18, y: -10, width: 36, height: 14))
        let curve = Path(svg: "M526 690 C 500 676, 470 678, 452 694 Z")
        #expect(!curve.isEmpty)
    }
}
