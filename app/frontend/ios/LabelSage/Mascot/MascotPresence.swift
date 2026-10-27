import Foundation
import Observation

/// A place that can show the one LabelSage on screen (`docs/mascot.md` › Hard rules, D9).
nonisolated enum MascotHost: Hashable, Sendable {
    /// The chat dock above the composer.
    case dock
    /// A sheet, such as the product sheet or the welcome sheet.
    case sheet
    /// A tip or coach mark.
    case tip
    /// The heading of a pushed page (Family).
    case page
}

/// Enforces one mascot per screen. A host claims him when it appears and releases him when it
/// goes away; only the latest claim shows him, and every other `MascotView` with a host renders
/// nothing. When the latest host releases him, he goes back to the host that held him before
/// (the sheet closes, the dock has him again). Put one in the environment at the app root.
///
/// Each `MascotView` claims with its own `owner` token, so two sheets stacked (Compare over the
/// product sheet) are two claims: only the top one draws him, and closing it gives him back to
/// the sheet below instead of to nobody.
@Observable
final class MascotPresence {
    private struct Claim: Equatable {
        let host: MascotHost
        let owner: UUID?
    }

    /// Claims in order; the last one holds the mascot.
    private var entries: [Claim] = []

    /// The hosts in claim order.
    var claims: [MascotHost] { entries.map(\.host) }

    /// The host that shows the mascot now, or nil when nobody claimed him.
    var holder: MascotHost? { entries.last?.host }

    /// `host` takes the mascot. Claiming again moves it back to the top.
    func claim(_ host: MascotHost, owner: UUID? = nil) {
        let claim = Claim(host: host, owner: owner)
        entries.removeAll { $0 == claim }
        entries.append(claim)
    }

    /// `host` gives the mascot back; the previous holder, if any, shows him again.
    func release(_ host: MascotHost, owner: UUID? = nil) {
        entries.removeAll { $0 == Claim(host: host, owner: owner) }
    }

    /// Whether a `MascotView` in `host` (with `owner`) draws the mascot.
    func shows(_ host: MascotHost, owner: UUID? = nil) -> Bool { entries.last == Claim(host: host, owner: owner) }
}
