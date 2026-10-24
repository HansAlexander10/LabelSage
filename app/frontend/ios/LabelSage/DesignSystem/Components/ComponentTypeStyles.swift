import SwiftUI

/// Component text sizes the boards and `OnboardSimple.dc.html` use that tokens.json has no style
/// for (logged in `open-questions.md`, "Component type sizes"). Kept here, next to the components
/// that use them, rather than in `Theme+Type.swift`, until the designer adds them to tokens.json.
nonisolated extension Theme.TypeStyle {
    /// `OptionCard` and `GroupCard` title: prototype `font-size: 19px; font-weight: 600`.
    static let optionTitle = Theme.TypeStyle(size: 19, weight: .semibold, relativeTo: .headline)
    /// `OptionTile` title: prototype `font-size: 18px; font-weight: 700`.
    static let tileTitle = Theme.TypeStyle(size: 18, weight: .bold, relativeTo: .headline)
    /// `KindBadge` label: prototype `font-size: 14px; font-weight: 600`.
    static let badge = Theme.TypeStyle(size: 14, weight: .semibold, relativeTo: .subheadline)
}
