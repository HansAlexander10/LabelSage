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

    /// `ProductRow` name, row and card: prototype `ProductRow.dc.html` `font-size: 16px; font-weight: 600`.
    static let productRowName = Theme.TypeStyle(size: 16, weight: .semibold, relativeTo: .headline)
    /// `ProductRow` compact name: prototype `font-size: 15px; font-weight: 600`.
    static let productLineName = Theme.TypeStyle(size: 15, weight: .semibold, relativeTo: .subheadline)
    /// `ProductRow` price: prototype `font-size: 15px; font-weight: 600; tabular-nums`.
    static let price = Theme.TypeStyle(size: 15, weight: .semibold, relativeTo: .subheadline, isTabularNumber: true)
    /// Finding chips on product rows and cards: prototype `height: 24px; font-size: 13px`.
    static let noteChip = Theme.TypeStyle(size: 13, weight: .regular, relativeTo: .footnote)
    /// User chat bubble: prototype `Chat.dc.html` `font-size: 17px; line-height: 1.3`.
    static let userBubble = Theme.TypeStyle(size: 17, weight: .regular, lineHeightMultiplier: 1.3, relativeTo: .body)
    /// LabelSage's bubble: prototype `font-size: 16px; line-height: 1.35`.
    static let mascotBubble = Theme.TypeStyle(size: 16, weight: .regular, lineHeightMultiplier: 1.35, relativeTo: .callout)
    /// `PersonCard` name: prototype `Profile.dc.html` `font-size: 20px; font-weight: 700`.
    static let personName = Theme.TypeStyle(size: 20, weight: .bold, relativeTo: .title3)
}
