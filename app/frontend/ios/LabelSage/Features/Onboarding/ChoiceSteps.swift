import SwiftUI

/// One answer on a choice step: `IconView` key, title, optional detail.
struct ChoiceOption: Identifiable {
    let id: String
    let icon: String
    let title: String
    var detail: String?
}

/// Full-width `OptionCard`s, single or multiple choice.
struct OptionCardList: View {
    let options: [ChoiceOption]
    let mode: OptionCard.Mode
    let isOn: (String) -> Bool
    let tap: (String) -> Void

    var body: some View {
        VStack(spacing: Theme.spacing.m) {
            ForEach(options) { o in
                OptionCard(iconKey: o.icon, title: o.title, detail: o.detail, mode: mode, isOn: isOn(o.id)) { tap(o.id) }
            }
        }
    }
}

/// `OptionTile`s in two columns; one column at accessibility sizes (spec 01 › Responsive).
struct OptionTileGrid: View {
    let options: [ChoiceOption]
    let isOn: (String) -> Bool
    let tap: (String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.spacing.m),
                            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
        LazyVGrid(columns: columns, spacing: Theme.spacing.m) {
            ForEach(options) { o in
                OptionTile(iconKey: o.icon, title: o.title, detail: o.detail, isOn: isOn(o.id)) { tap(o.id) }
            }
        }
    }
}

/// A one-line text field in an ink-outlined row, for "Something else" and "Other".
struct OtherTextField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: Theme.spacing.s) {
            Image(systemName: "plus").foregroundStyle(Theme.color.ink)
            TextField(prompt, text: $text)
                .themeText(.body)
                .submitLabel(.done)
                .onChange(of: text) { _, new in if new.count > 60 { text = String(new.prefix(60)) } }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.color.surface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.color.ink, lineWidth: 2))
        .accessibilityLabel("Describe it")
    }
}

/// Toggles a member of a set (tick or untick a multiple-choice answer).
extension Set {
    mutating func toggle(_ member: Element) {
        if contains(member) { remove(member) } else { insert(member) }
    }
}

// MARK: - Steps

/// Step 2: Just me or My family.
struct HouseholdStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OptionCardList(options: [
            ChoiceOption(id: "me", icon: "me", title: "Just me", detail: "Just my allergies and diets"),
            ChoiceOption(id: "family", icon: "family", title: "My family", detail: "Everyone at home, one at a time"),
        ], mode: .single) {
            ($0 == "me" ? .justMe : .family) == model.household
        } tap: {
            model.household = $0 == "me" ? .justMe : .family
        }
    }
}

/// Step 4: Allergies and ingredients, Macros and calories (checklist).
struct GoalStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OptionCardList(options: [
            ChoiceOption(id: "avoid", icon: "notfor", title: "Allergies and ingredients", detail: "Allergies, diets and anything you avoid"),
            ChoiceOption(id: "numbers", icon: "macros", title: "Macros and calories", detail: "Protein and calories for a goal"),
        ], mode: .multi) {
            model.current.goals.contains($0 == "avoid" ? .avoid : .numbers)
        } tap: {
            model.current.goals.toggle($0 == "avoid" ? .avoid : .numbers)
        }
    }
}

/// Step 5: why this person avoids foods (checklist).
struct WhyStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: Theme.spacing.m) {
            OptionCardList(options: [
                ChoiceOption(id: "medical", icon: "medical", title: "Medical diet", detail: "Celiac, heart health, blood sugar and more"),
                ChoiceOption(id: "allergy", icon: "allergy", title: "Allergy or intolerance", detail: "I’ll ask which ones"),
                ChoiceOption(id: "diet", icon: "vegan", title: "Diet choice", detail: "Vegan, vegetarian, keto…"),
                ChoiceOption(id: "religion", icon: "religion", title: "Religion or culture", detail: "Halal, kosher, no beef"),
                ChoiceOption(id: "dislike", icon: "dislike", title: "I just don’t like some foods", detail: "Shown lower, never hidden"),
            ], mode: .multi) { id in
                OnboardingModel.Why(rawValue: id).map(model.current.why.contains) ?? false
            } tap: { id in
                if let why = OnboardingModel.Why(rawValue: id) { model.current.why.toggle(why) }
            }
            OnboardingFootnote(systemImage: "info.circle",
                               text: "Allergies and medical diets are always avoided. Dislikes only move products down.")
        }
    }
}

/// Step 8: diets, as tiles.
struct DietStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OptionTileGrid(options: [
            ChoiceOption(id: "vegan", icon: "vegan", title: "Vegan", detail: "No meat, fish, dairy, eggs, honey"),
            ChoiceOption(id: "vegetarian", icon: "vegetarian", title: "Vegetarian", detail: "No meat or fish"),
            ChoiceOption(id: "keto", icon: "keto", title: "Keto", detail: "Net carbs under 20 g a day"),
            ChoiceOption(id: "paleo", icon: "paleo", title: "Paleo or whole food", detail: "No grains, legumes, refined sugar"),
        ]) { model.current.diets.contains($0) } tap: { model.current.diets.toggle($0) }
    }
}

/// Step 9: halal, kosher, no beef, or something typed.
struct ReligionStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: Theme.spacing.m) {
            OptionTileGrid(options: [
                ChoiceOption(id: "halal", icon: "halal", title: "Halal", detail: "No pork, alcohol; gelatin checked"),
                ChoiceOption(id: "kosher", icon: "kosher", title: "Kosher", detail: "Certified, meat and dairy kept apart"),
                ChoiceOption(id: "nobeef", icon: "nobeef", title: "No beef", detail: "Beef, beef tallow, beef gelatin"),
                ChoiceOption(id: "other", icon: "add", title: "Other", detail: "Type it below"),
            ]) { model.current.religion.contains($0) } tap: { model.current.religion.toggle($0) }
            if model.current.religion.contains("other") {
                OtherTextField(prompt: "e.g. Jain, no pork gelatin, vegetarian on Fridays", text: $model.current.religionOther)
            }
        }
    }
}

/// Step 10: the medical diet.
struct MedicalStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: Theme.spacing.m) {
            OptionTileGrid(options: [
                ChoiceOption(id: "celiac", icon: "celiac", title: "Celiac or gluten-free", detail: "Adds gluten with all its hidden names"),
                ChoiceOption(id: "heart", icon: "heart", title: "Heart health", detail: "Sodium under 1,500 mg a day"),
                ChoiceOption(id: "sugar", icon: "bloodsugar", title: "Blood sugar", detail: "Added sugar under 25 g a day"),
                ChoiceOption(id: "other", icon: "add", title: "Something else", detail: "Type it below"),
            ]) { model.current.medical.contains($0) } tap: { model.current.medical.toggle($0) }
            if model.current.medical.contains("other") {
                OtherTextField(prompt: "e.g. low FODMAP, kidney diet", text: $model.current.medicalOther)
            }
        }
    }
}

/// Step 13a: where the targets come from.
struct SourceStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: Theme.spacing.m) {
            OptionCardList(options: [
                ChoiceOption(id: "know", icon: "macros", title: "I know my numbers", detail: "From me or my coach"),
                ChoiceOption(id: "help", icon: "health", title: "Help me set them", detail: "Uses height, weight and age from Apple Health"),
            ], mode: .single) {
                model.current.source == ($0 == "know" ? .know : .help)
            } tap: {
                model.current.source = $0 == "know" ? .know : .help
            }
            OnboardingFootnote(systemImage: "info.circle", text: "Apple Health is only requested if you choose “Help me set them”.")
        }
    }
}

/// Step 13b: goals right now (checklist).
struct PhaseStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OptionCardList(options: [
            ChoiceOption(id: "cut", icon: "weight", title: "Lose fat", detail: "Eat a little less, keep muscle"),
            ChoiceOption(id: "bulk", icon: "protein", title: "Build muscle", detail: "More protein and calories"),
            ChoiceOption(id: "maintain", icon: "calories", title: "Maintain weight", detail: "Hold where I am"),
            ChoiceOption(id: "whole", icon: "organic", title: "Eat more whole foods", detail: "Less ultra-processed"),
            ChoiceOption(id: "energy", icon: "bloodsugar", title: "Steadier energy", detail: "Less added sugar between meals"),
        ], mode: .multi) { id in
            OnboardingModel.Phase(rawValue: id).map(model.current.phases.contains) ?? false
        } tap: { id in
            if let phase = OnboardingModel.Phase(rawValue: id) { model.current.phases.toggle(phase) }
        }
    }
}

/// Step 13c: daily targets with native steppers (±5 g, ±100 kcal).
struct TargetsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: Theme.spacing.s) {
            VStack(spacing: 0) {
                Stepper(value: $model.protein, in: 40...400, step: 5) {
                    row("Protein", hint: "About \(model.protein / 4) g per meal", value: "\(model.protein) g")
                }
                Divider().overlay(Theme.color.hairline)
                Stepper(value: $model.kcal, in: 1_000...5_000, step: 100) {
                    row("Calories", hint: "Daily total", value: model.kcal.formatted())
                }
            }
            .padding(.horizontal, Theme.spacing.l)
            .padding(.vertical, Theme.spacing.xs)
            .background(RoundedRectangle(cornerRadius: Theme.radius.tile, style: .continuous).fill(Theme.color.surface))
            OnboardingFootnote(systemImage: "info.circle", text: "Products show grams and % of your own target, not a generic score.")
        }
    }

    private func row(_ title: String, hint: String, value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).themeText(.body)
                Text(hint).themeText(.footnote).foregroundStyle(Theme.color.muted)
            }
            Spacer()
            Text(value).themeText(.number)
        }
        .foregroundStyle(Theme.color.ink)
        .frame(minHeight: 60)
    }
}

/// Step 17: start now or fine-tune.
struct DepthStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OptionCardList(options: [
            ChoiceOption(id: "start", icon: "ok", title: "Start now", detail: "Show my summary; I’ll learn as you shop"),
            ChoiceOption(id: "more", icon: "options", title: "Fine-tune more", detail: "Budget and preferences · about 1 min"),
        ], mode: .single) {
            model.depth == ($0 == "start" ? .start : .more)
        } tap: {
            model.depth = $0 == "start" ? .start : .more
        }
    }
}

/// Step 18: ranking preferences, as tiles.
struct PrefsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OptionTileGrid(options: [
            ChoiceOption(id: "organic", icon: "organic", title: "Prefer organic"),
            ChoiceOption(id: "nova4", icon: "ultraprocessed", title: "Avoid ultra-processed", detail: "NOVA 4 shown lower"),
            ChoiceOption(id: "store", icon: "ask", title: "Prefer store brands", detail: "Cheaper equivalents first"),
            ChoiceOption(id: "local", icon: "local", title: "Prefer local"),
        ]) { model.prefs.contains($0) } tap: { model.prefs.toggle($0) }
    }
}

// MARK: - Previews

private func stepPreview(_ step: OnboardingModel.Step, _ setup: (OnboardingModel) -> Void = { _ in }) -> some View {
    let model = OnboardingModel()
    setup(model)
    model.show(step)
    return OnboardingFlow(model: model, showsLaunch: false) { _ in }
}

#Preview("Household") { stepPreview(.household) }
#Preview("Goal") { stepPreview(.goal) { $0.current.goals = [.avoid] } }
#Preview("Why") { stepPreview(.why) { $0.household = .family; $0.firstName = "Mia"; $0.current.goals = [.avoid]; $0.current.why = [.allergy] } }
#Preview("Diet") { stepPreview(.diet) { $0.current.goals = [.avoid]; $0.current.why = [.diet] } }
#Preview("Religion, other") { stepPreview(.religion) { $0.current.goals = [.avoid]; $0.current.why = [.religion]; $0.current.religion = ["halal", "other"] } }
#Preview("Medical") { stepPreview(.medical) { $0.current.goals = [.avoid]; $0.current.why = [.medical]; $0.current.medical = ["celiac"] } }
#Preview("Source") { stepPreview(.source) { $0.current.goals = [.numbers] } }
#Preview("Phase") { stepPreview(.phase) { $0.current.goals = [.numbers]; $0.current.phases = [.cut] } }
#Preview("Targets") { stepPreview(.targets) { $0.current.goals = [.numbers]; $0.current.phases = [.cut] } }
#Preview("Depth") { stepPreview(.depth) { $0.current.goals = [.avoid] } }
#Preview("Prefs") { stepPreview(.prefs) { $0.current.goals = [.avoid]; $0.depth = .more } }
