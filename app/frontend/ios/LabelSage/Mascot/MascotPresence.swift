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

/// Enforces one mascot per screen. Each `MascotView` with a host claims him under its own id
/// when it appears and releases him when it goes away; only the latest claim shows him, and every
/// other claimant renders nothing. Ids, not hosts, identify claims, so two views in the same host
/// cannot both draw. When the latest claimant releases him, he goes back to the one before (the
/// sheet closes, the dock has him again). Put one in the environment at the app root.
@Observable
final class MascotPresence {
    /// One view's claim on the mascot.
    struct Claim: Equatable, Sendable {
        let id: UUID
        let host: MascotHost
    }

    /// Claims in order; the last one holds the mascot.
    private(set) var claims: [Claim] = []

    /// The host that shows the mascot now, or nil when nobody claimed him.
    var holder: MascotHost? { claims.last?.host }

    /// The view `id` in `host` takes the mascot. Claiming again moves it back to the top.
    func claim(_ id: UUID, host: MascotHost) {
        claims.removeAll { $0.id == id }
        claims.append(Claim(id: id, host: host))
    }

    /// The view `id` gives the mascot back; the previous claimant, if any, shows him again.
    func release(_ id: UUID) {
        claims.removeAll { $0.id == id }
    }

    /// Whether the view `id` draws the mascot.
    func shows(_ id: UUID) -> Bool { claims.last?.id == id }
}
