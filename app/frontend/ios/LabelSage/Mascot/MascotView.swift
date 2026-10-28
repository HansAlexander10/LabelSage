import SwiftUI

/// LabelSage, the mascot: the rig from `Resources/Mascot/rig.json` playing one of the 13 states
/// (`docs/mascot.md`). `size` is the width; the view is `size × 1.26` tall, the 960 × 1210
/// artboard. Decorative for VoiceOver; his bubble carries the words.
///
/// One per screen: give it a `host` and put a `MascotPresence` in the environment, and only the
/// view that claimed him last draws him; the others keep his frame empty. Without a host (or
/// without a presence) it always draws.
struct MascotView: View {
    let state: MascotState
    let size: CGFloat
    /// Label lines turned green (0...3), as items are found while `reading`. `done` shows all three.
    var found: Int = 0
    var host: MascotHost?
    /// False draws him still on the state's first key frame. For tiny mascots whose motion does not show.
    var animates = true

    /// Height over width: the artboard height maps to `size × 1.26`.
    static let heightRatio: CGFloat = 1.26
    /// `idle` becomes `hum` after this long without a tap.
    static let humDelay: Duration = .seconds(15)
    /// UI tests launch with `-uitest`. The mascot is hidden from VoiceOver (decorative), and
    /// then also from XCUITest's query, so under `-uitest` it stays exposed for the one-mascot test.
    static let exposedForUITests = ProcessInfo.processInfo.arguments.contains("-uitest")

    @Environment(MascotPresence.self) private var presence: MascotPresence?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bored = false
    @State private var taps = 0
    /// This view's claim in `MascotPresence`, so two hosts of the same kind (stacked sheets) never both draw him.
    @State private var claimID = UUID()
    /// Off screen (scrolled away, or a covered tab), the timeline pauses.
    @State private var isVisible = true
    @Environment(\.scenePhase) private var scenePhase

    init(state: MascotState, size: CGFloat, found: Int = 0, host: MascotHost? = nil, animates: Bool = true) {
        self.state = state
        self.size = size
        self.found = found
        self.host = host
        self.animates = animates
    }

    /// The state on screen: `idle` turns into `hum` once he is bored.
    var shownState: MascotState { state == .idle && bored ? .hum : state }

    private var isShown: Bool {
        guard host != nil, let presence else { return true }
        return presence.shows(claimID)
    }

    var body: some View {
        // One stable container, so claiming and losing him does not re-run onAppear. When another
        // view has him, the frame stays and is empty, so layouts don't jump.
        ZStack {
            Color.clear
            if isShown { figure }
        }
        .frame(width: size, height: size * Self.heightRatio)
        .onAppear {
            MascotArt.warm()
            if let host { presence?.claim(claimID, host: host) }
        }
        .onDisappear { if host != nil { presence?.release(claimID) } }
    }

    private var figure: some View {
        let shown = shownState
        let animated = animates && !reduceMotion && shown != .guard
        // One timeline for both poses of a crossfade (the outgoing pose has no timeline of its own),
        // at 30 fps, paused when he is still, off screen or the app is not active.
        let paused = !animated || !isVisible || scenePhase != .active
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { timeline in
            ZStack {
                MascotFigure(state: shown, found: found, animated: animated, date: timeline.date,
                             size: CGSize(width: size, height: size * Self.heightRatio))
                    .id(shown)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size * Self.heightRatio)
        .onScrollVisibilityChange { isVisible = $0 }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .themeAnimation(Theme.motion.mascotPoseCrossfade, value: shown)
        .contentShape(.rect)
        .simultaneousGesture(TapGesture().onEnded {
            bored = false
            taps += 1
        })
        .task(id: HumTimer(state: state, taps: taps)) {
            bored = false
            guard state == .idle else { return }
            try? await Task.sleep(for: Self.humDelay)
            if !Task.isCancelled { bored = true }
        }
        .accessibilityHidden(!Self.exposedForUITests)
        .accessibilityIdentifier("mascot")
    }

    /// Restarts the 15 s wait whenever the state changes or he is tapped.
    private struct HumTimer: Equatable {
        let state: MascotState
        let taps: Int
    }
}

/// One state, drawn at `date` from the time since it appeared. Frozen on its first key frame
/// when not `animated` (Reduce Motion, `guard`, or `animates: false`); the timeline is paused then.
private struct MascotFigure: View {
    let state: MascotState
    let found: Int
    let animated: Bool
    /// The shared timeline's date.
    let date: Date
    /// The artboard's size on screen; the canvas is bigger so props, the jump and the raised
    /// products can leave the artboard, as the prototype's `overflow: visible` lets them.
    let size: CGSize

    /// Extra canvas on each side, as a fraction of the artboard.
    private static let overflow: CGFloat = 0.25

    /// Each state starts its keyframes from 0 when it appears (the `done` jump plays once).
    @State private var start = Date.now
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let pose = animated
            ? MascotPose.at(state, time: date.timeIntervalSince(start))
            : MascotPose.at(state, time: 0, frozen: true)
        let margin = CGSize(width: size.width * Self.overflow, height: size.height * Self.overflow)
        // The parts resampled once for this size and screen, not on every frame.
        let art = MascotArt.shared.map { $0.scaled(pixelsPerUnit: size.height / $0.rig.artboard.height * displayScale) }
        return Canvas { [size, state, found] context, _ in
            guard let art else { return }
            Perf.countMascotRedraw()
            context.translateBy(x: margin.width, y: margin.height)
            MascotRenderer(art: art).draw(state, pose: pose, found: found, in: &context, size: size)
        }
        .frame(width: size.width + margin.width * 2, height: size.height + margin.height * 2)
        .frame(width: size.width, height: size.height)
    }
}

#Preview("States") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: Theme.spacing.l) {
            ForEach(MascotState.allCases, id: \.self) { state in
                VStack {
                    MascotView(state: state, size: 74, found: state == .reading ? 2 : 0)
                    Text(state.rawValue).themeText(.footnote)
                }
            }
        }
        .padding()
    }
}

#Preview("Sizes") {
    HStack(alignment: .bottom) {
        ForEach([74.0, 64, 56, 40, 30], id: \.self) { MascotView(state: .idle, size: $0) }
    }
}

#Preview("One mascot") {
    @Previewable @State var presence = MascotPresence()
    @Previewable @State var sheet = false
    VStack {
        Toggle("Sheet open", isOn: $sheet)
        HStack {
            MascotView(state: .idle, size: 64, host: .dock)
            if sheet { MascotView(state: .talk, size: 64, host: .sheet) }
            MascotView(state: .wave, size: 64, host: .dock) // same host, claimed last: only this one draws
        }
    }
    .padding()
    .environment(presence)
}
