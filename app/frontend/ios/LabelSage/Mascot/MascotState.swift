import Foundation

/// The 13 poses LabelSage plays (`docs/mascot.md` › The 13 states, board `80-mascot-states.png`).
/// Each one loops, except `done` (a jump once, then hops) and `guard` (still).
nonisolated enum MascotState: String, CaseIterable, Sendable {
    /// Home and empty states: breathes, shifts weight, glances, blinks. Becomes `hum` after 15 s without a tap.
    case idle
    /// After 15 s of nothing: strolls in place, notes float up.
    case hum
    /// Reading ingredients: the magnifier moves from one eye to the other.
    case reading
    /// A find, the end of onboarding: jumps once, then hops from leg to leg with sparkles.
    case done
    /// A choice is needed, Check first, Can't confirm: taps the chin, the "?" bobs.
    case thinking
    /// A bubble is on screen: mouth opens and closes, one hand gestures.
    case talk
    /// Hello, welcome back, end of the tour.
    case wave
    /// Directs to the options or a button below.
    case point
    /// While the person chooses or types: looks down, nods.
    case listen
    /// Compare works out which product fits: one in each hand.
    case compare
    /// Learning someone's allergies: sits on books, turns a page.
    case sit
    /// Product not found: glasses, red nose, mustache. Never on Not for.
    case disguise
    /// Not for: still and serious, brows down, flat mouth.
    case `guard`
}
