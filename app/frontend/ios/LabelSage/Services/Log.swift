import Foundation
import OSLog
import Synchronization

/// One `Logger` per category, one subsystem (`spike-core-ai-dspy-and-logging-2026-10-23.md` › Logging plan).
/// Log enums, counts and durations. Names, allergies and barcodes are always `.private`; barcodes use
/// `.private(mask: .hash)` so one product can be followed across events. Never log prompt or model text.
nonisolated enum Log {
    static let subsystem = "app.labelsage.ios"

    static let lookup = Logger(subsystem: subsystem, category: "lookup")
    static let verdict = Logger(subsystem: subsystem, category: "verdict")
    static let model = Logger(subsystem: subsystem, category: "model")
    static let data = Logger(subsystem: subsystem, category: "data")
    /// Timings only (`Perf`): interval names and milliseconds, never names, allergies or barcodes.
    static let perf = Logger(subsystem: subsystem, category: "perf")
}

nonisolated extension Logger {
    /// Logs a failed `event` (a fixed string) with the error's domain and code public and its
    /// description private: a SwiftData or decoding description can quote stored values.
    func failure(_ event: String, _ error: any Error, level: OSLogType = .error) {
        let ns = error as NSError
        log(level: level, "\(event, privacy: .public): \(ns.domain, privacy: .public) \(ns.code, privacy: .public) \(String(describing: error), privacy: .private)")
    }
}

/// Signposted intervals for Instruments (always on, they are cheap), plus a millisecond log line per
/// interval and a once-a-second mascot redraw count when the app runs with `-perfLog`
/// (`docs/app-engineering/spikes/spike-ui-performance-2026-10-27.md`).
///
/// Intervals: `launch.firstFrame` (with `launch.container` and `launch.mascotArt` inside),
/// `verdict.check`, `lookup`, `scan.toSheet`, `chat.answer` (with `chat.search` and `chat.explain`)
/// and `sheet.open`.
nonisolated enum Perf {
    static let signposter = OSSignposter(logger: Log.perf)
    /// `-perfLog`: also log each interval's milliseconds to the `perf` category.
    static let isLogging = ProcessInfo.processInfo.arguments.contains("-perfLog")

    /// An interval that has begun.
    struct Interval: Sendable {
        let name: StaticString
        let state: OSSignpostIntervalState
        let start: ContinuousClock.Instant
    }

    static func begin(_ name: StaticString) -> Interval {
        Interval(name: name, state: signposter.beginInterval(name, id: signposter.makeSignpostID()), start: .now)
    }

    static func end(_ interval: Interval) {
        signposter.endInterval(interval.name, interval.state)
        guard isLogging else { return }
        let ms = Double((ContinuousClock.now - interval.start) / .microseconds(1)) / 1000
        Log.perf.info("\(String(describing: interval.name), privacy: .public) \(String(format: "%.1f", ms), privacy: .public) ms")
    }

    static func measure<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let interval = begin(name)
        defer { end(interval) }
        return try body()
    }

    static func measure<T>(_ name: StaticString, _ body: () async throws -> T) async rethrows -> T {
        let interval = begin(name)
        defer { end(interval) }
        return try await body()
    }

    // MARK: Intervals that end in another place (a view's first appear)

    private static let pending = Mutex<[String: Interval]>([:])

    /// Begins `name` now; `endPending(name)` ends it, such as in the destination's `onAppear`.
    /// A second begin before the end replaces the first.
    static func beginPending(_ name: StaticString) {
        let interval = begin(name)
        pending.withLock { $0[String(describing: name)] = interval }
    }

    /// Ends `name` if it is pending; otherwise does nothing.
    static func endPending(_ name: StaticString) {
        if let interval = pending.withLock({ $0.removeValue(forKey: String(describing: name)) }) { end(interval) }
    }

    // MARK: Mascot redraws

    private static let redraws = Mutex<(count: Int, since: ContinuousClock.Instant)>((0, .now))

    /// One mascot frame drawn. With `-perfLog`, logs the count once a second.
    static func countMascotRedraw() {
        guard isLogging else { return }
        let now = ContinuousClock.now
        let done: Int? = redraws.withLock { state in
            state.count += 1
            guard now - state.since >= .seconds(1) else { return nil }
            defer { state = (0, now) }
            return state.count
        }
        if let done { Log.perf.info("mascot.redraws \(done, privacy: .public) per s") }
    }
}
