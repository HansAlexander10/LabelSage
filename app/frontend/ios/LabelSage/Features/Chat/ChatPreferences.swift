import SwiftUI
import LabelSageCore

/// "Change the preferences" in the chat: what LabelSage checks for each person, read-only. The cards
/// read the live household, so a change confirmed in the chat shows here at once. Nothing is picked
/// here; the person tells LabelSage what to change (product owner, 2026-10-27).
struct PreferencesCard: View {
    let people: [Person]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.s) {
            ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                PersonPreferences(person: person, index: index)
            }
        }
    }
}

/// One person's preferences, like the onboarding summary card: avatar, name and count; closed shows
/// the chips, open shows one row per item with its detail.
private struct PersonPreferences: View {
    let person: Person
    let index: Int
    @State private var isOpen = false

    private var items: [FamilyItem] {
        FamilyLogic.items(for: person.profile, parked: [], catalog: VerdictService.bundledCatalog)
    }

    var body: some View {
        let items = items
        let summary = PersonSummary.line(items.map {
            PersonItem(id: $0.id, iconKey: $0.iconKey, title: $0.title, detail: $0.detail, kind: $0.kind)
        })
        let tints = Theme.screenTint.avatarTints
        VStack(alignment: .leading, spacing: Theme.spacing.m) {
            Button {
                isOpen.toggle()
            } label: {
                HStack(spacing: Theme.spacing.m) {
                    Text(PersonSummary.initial(person.name))
                        .font(.custom("Outfit", fixedSize: 20).weight(.bold))
                        .foregroundStyle(Theme.color.ink)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(tints[index % tints.count]))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(PersonSummary.title(name: person.name, isOwner: person.isOwner))
                            .themeText(.personName)
                            .foregroundStyle(Theme.color.ink)
                        Text(summary)
                            .themeText(.caption)
                            .foregroundStyle(Theme.color.mutedGreen)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.color.muted)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(PersonSummary.title(name: person.name, isOwner: person.isOwner)). \(summary)")
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
            .accessibilityHint(isOpen ? "Hides the details" : "Shows the details")

            if items.isEmpty {
                Text("Nothing to avoid yet. Tell me what to add.")
                    .themeText(.callout)
                    .foregroundStyle(Theme.color.mutedGreen)
            } else if isOpen {
                VStack(alignment: .leading, spacing: Theme.spacing.s) {
                    ForEach(items) { row($0) }
                }
            } else {
                ChipFlow(spacing: Theme.spacing.xs) {
                    ForEach(items) { item in
                        Chip(kind: chipKind(item.kind), iconKey: item.iconKey, text: item.title)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCardBackground(cornerRadius: Theme.radius.card, isSelected: false)
        .themeAnimation(Theme.motion.groupCardOpen, value: isOpen)
    }

    private func row(_ item: FamilyItem) -> some View {
        HStack(alignment: .center, spacing: Theme.spacing.m) {
            IconView(key: item.iconKey, size: 32, decorative: true)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .themeText(.bodyStrong)
                    .foregroundStyle(Theme.color.ink)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .themeText(.footnote)
                        .foregroundStyle(Theme.color.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.kind.title)
                .themeText(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.color.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private func chipKind(_ kind: KindBadge.Kind) -> Chip.Kind {
        switch kind {
        case .avoid: .avoid
        case .preferNot: .preferNot
        case .diet, .goal: .dietGoal
        }
    }
}
