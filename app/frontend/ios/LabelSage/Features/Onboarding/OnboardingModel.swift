import Foundation
import Observation
import LabelSageCore

/// The onboarding decision tree (`docs/logic/onboarding-tree.md`, prototype `OnboardSimple.dc.html`).
///
/// The path is computed from the answers so far, so a step appears only when an earlier answer
/// needs it. Two modes (product owner, 2026-10-27):
/// - `.firstRun` sets up only the owner ("you"), then the region and store. The region is
///   required: Skip never passes it.
/// - `.addPerson` adds one more person from Family: a name, whose preferences to start from (a
///   copy, never linked), the same per-person questions, then save.
///
/// Every allergen is a hard filter: it is saved as an allergy, and "may contain" is always on.
/// The app never asks "allergy or intolerance" (`Severity` stays in LabelSageCore for old data).
@Observable
final class OnboardingModel {
    // MARK: Types

    /// Every step in the tree, in the order the path can visit them.
    enum Step: String, CaseIterable, Sendable {
        case welcome, name, startFrom, goal, why, diet, religion, medical, allergens
        case avoid, source, body, phase, targets, region, store, depth, prefs, summary
    }

    enum Mode: Sendable, Equatable { case firstRun, addPerson }
    enum Goal: Sendable { case avoid, numbers }
    enum Why: String, CaseIterable, Sendable { case medical, allergy, diet, religion, dislike }
    enum TargetSource: Sendable { case know, help }
    enum Phase: String, CaseIterable, Sendable { case cut, bulk, maintain, whole, energy }
    enum Depth: Sendable { case start, more }

    /// Height, weight, age and activity for "Help me set them" (known issue 1). US units, typed in by
    /// the person; nothing is read from Apple Health yet.
    struct BodyStats: Equatable, Sendable {
        enum Sex: String, CaseIterable, Sendable { case female, male, unsaid }
        enum Activity: String, CaseIterable, Sendable { case low, light, moderate, high }

        var age: Int?
        var heightInches: Int?
        var weightPounds: Int?
        var sex: Sex = .unsaid
        var activity: Activity = .light

        static let ages = 13...100
        static let heights = 48...90
        static let weights = 70...600

        var isComplete: Bool {
            guard let age, let heightInches, let weightPounds else { return false }
            return Self.ages.contains(age) && Self.heights.contains(heightInches) && Self.weights.contains(weightPounds)
        }

        /// Daily protein and calories from the Mifflin-St Jeor equation, the activity factor and the
        /// goals: lose fat −20%, build muscle +10%, both at maintenance. Protein 1.6–2.0 g per kg.
        /// Rounded to the targets step's own steps (5 g, 100 kcal) and kept in its ranges.
        func targets(for phases: Set<Phase>) -> (protein: Int, kcal: Int)? {
            guard isComplete, let age, let heightInches, let weightPounds else { return nil }
            let kg = Double(weightPounds) * 0.453_592, cm = Double(heightInches) * 2.54
            let sexTerm: Double = switch sex { case .male: 5; case .female: -161; case .unsaid: -78 }
            let bmr = 10 * kg + 6.25 * cm - 5 * Double(age) + sexTerm
            let factor: Double = switch activity { case .low: 1.2; case .light: 1.375; case .moderate: 1.55; case .high: 1.725 }
            let cut = phases.contains(.cut), bulk = phases.contains(.bulk)
            let change = cut && bulk ? 1 : cut ? 0.8 : bulk ? 1.1 : 1
            let gramsPerKg = cut ? 2.0 : bulk ? 1.8 : 1.6
            let kcal = Int((bmr * factor * change / 100).rounded()) * 100
            let protein = Int((kg * gramsPerKg / 5).rounded()) * 5
            return (min(max(protein, 40), 400), min(max(kcal, 1_000), 5_000))
        }
    }

    /// One person's answers.
    struct Answers: Equatable, Sendable {
        var goals: Set<Goal> = []
        var why: Set<Why> = []
        /// vegan, vegetarian, keto, paleo (catalog `diets` keys).
        var diets: Set<String> = []
        /// halal, kosher, nobeef, and "other" for the free text.
        var religion: Set<String> = []
        var religionOther = ""
        /// celiac, heart, sugar (catalog `medical` keys), and "other" for the free text.
        var medical: Set<String> = []
        var medicalOther = ""
        /// Group ids without leaves ("peanut") and leaf ids ("almond", "mustard").
        var allergens: Set<String> = []
        /// "Anything else" catalog families, in the order they were ticked.
        var avoid: [String] = []
        var custom: [CustomChoice] = []
        /// Rule keys switched away from the default strength on the summary (D12).
        var flipped: Set<String> = []
        var source: TargetSource?
        var phases: Set<Phase> = []
        var body = BodyStats()
        var protein: Int?
        var kcal: Int?
    }

    /// One row or chip on a summary card.
    struct SummaryItem: Identifiable, Equatable {
        /// The rule key ("allergen:peanut", "avoid:seed", "custom:nightshades").
        var id: String
        var iconKey: String
        var title: String
        var detail: String
        var kind: KindBadge.Kind
        /// Avoid and Prefer not from the "Anything else" step flip; allergies and diets do not.
        var isFlippable: Bool
    }

    /// The custom-filter resolver card (spec `ResolverCard`).
    enum Resolver: Equatable {
        case matching(term: String)
        case ambiguous(term: String, choices: [String])
        case matched(Match)
    }

    /// A resolved custom filter: the keywords LabelSage will look for.
    struct Match: Equatable {
        var term: String
        var label: String
        var terms: [String]
        var confidence: String
        var note: String
        var off: Set<String> = []
        var kept: [String] { terms.filter { !off.contains($0) } }
    }

    /// "Start fresh" on the start-from step.
    static let freshStart = "fresh"

    // MARK: State

    let mode: Mode
    /// `.addPerson`: the people already saved, to copy preferences from and to keep names unique.
    let existing: [Person]
    private(set) var step: Step
    /// True after Continue or Skip, false after Back: the step transition's direction.
    private(set) var movedForward = true
    /// `.addPerson`: the new person's name.
    var name = ""
    /// `.addPerson`: the person id whose preferences were copied, or `freshStart`.
    private(set) var startFrom: String?
    var current = Answers()
    var region: Region?
    var store: Store?
    var depth: Depth?
    /// organic, nova4, store, local: ranking only, not part of the `Profile` yet.
    var prefs: Set<String> = []
    /// Set by Skip: region and store then lead straight to the summary.
    private(set) var isJumping = false
    /// The allergen whose related sheet is up ("peanut").
    var relatedFor: String?
    var openGroups: Set<String> = []
    var allergenQuery = ""
    var avoidQuery = ""
    var resolver: Resolver?

    /// First open: the owner only.
    init() {
        mode = .firstRun
        existing = []
        step = .welcome
    }

    /// "Add someone you shop for" in Family.
    init(addingTo existing: [Person]) {
        mode = .addPerson
        self.existing = existing
        step = .name
    }

    // MARK: Path

    /// The steps for the answers so far (onboarding-tree.md › The path, changed 2026-10-27).
    var path: [Step] {
        var p: [Step] = mode == .addPerson ? [.name, .startFrom] : [.welcome]
        p.append(.goal)
        if current.goals.contains(.avoid) {
            p.append(.why)
            if current.why.contains(.diet) { p.append(.diet) }
            if current.why.contains(.religion) { p.append(.religion) }
            if current.why.contains(.medical) { p.append(.medical) }
            if current.why.contains(.allergy) { p.append(.allergens) }
            p.append(.avoid)
        }
        if current.goals.contains(.numbers) {
            p.append(.source)
            if current.source == .help { p.append(.body) }
            p += [.phase, .targets]
        }
        if mode == .firstRun {
            p += [.region, .store]
            if !current.goals.isEmpty { p.append(.depth) }
            if depth == .more { p.append(.prefs) }
        }
        p.append(.summary)
        return p
    }

    var isAddingPerson: Bool { mode == .addPerson }

    /// The new person's name in `.addPerson`; nil for the owner ("you").
    var currentName: String? {
        guard mode == .addPerson else { return nil }
        let n = trimmedName
        return n.isEmpty ? nil : n
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Progress dots. First run: 0 your allergies, 1 where you shop. Add a person: 0 who, 1 their allergies.
    var section: Int {
        switch (mode, step) {
        case (.addPerson, .name), (.addPerson, .startFrom): 0
        case (.addPerson, _): 1
        case (.firstRun, .region), (.firstRun, .store), (.firstRun, .depth), (.firstRun, .prefs), (.firstRun, .summary): 1
        default: 0
        }
    }

    /// The names of the progress sections, for VoiceOver.
    var sectionNames: [String] {
        mode == .addPerson ? ["who you shop for", "their allergies"] : ["your allergies", "where you shop"]
    }

    // MARK: Validation

    /// Continue is enabled (onboarding-tree.md › Validation).
    var canContinue: Bool { missingAnswer == nil }

    /// What is missing, for the disabled Continue's VoiceOver hint; nil when the step is valid.
    var missingAnswer: String? {
        switch step {
        case .name:
            if trimmedName.isEmpty { return "Add a name" }
            return isNameTaken(trimmedName) ? "\(trimmedName) is already here. Use another name" : nil
        case .startFrom: return startFrom == nil ? "Pick one" : nil
        case .goal, .why, .medical, .phase: return isEmpty(step) ? "Pick at least one" : nil
        case .allergens: return allergenChoices.isEmpty ? "Pick at least one allergen" : nil
        case .source: return current.source == nil ? "Pick one" : nil
        case .body: return current.body.isComplete ? nil : "Add your age, height and weight"
        case .region: return Self.isValidZip(region?.zip) ? nil : "Set your city or ZIP code"
        case .store: return store == nil ? "Pick a store, or set it up later" : nil
        case .depth: return depth == nil ? "Pick one" : nil
        default: return nil
        }
    }

    private func isEmpty(_ step: Step) -> Bool {
        switch step {
        case .goal: current.goals.isEmpty
        case .why: current.why.isEmpty
        case .medical: current.medical.isEmpty
        case .phase: current.phases.isEmpty
        default: false
        }
    }

    /// A name someone in the household already has ("You" and "Me" are the owner).
    func isNameTaken(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return Self.isMe(n) || n == "you" || existing.contains { $0.name.lowercased() == n }
    }

    static func isValidZip(_ zip: String?) -> Bool {
        guard let zip else { return false }
        return zip.count == 5 && zip.allSatisfy(\.isASCII) && zip.allSatisfy(\.isNumber)
    }

    /// Skip shows on optional steps; never on welcome, the name, the start choice, goal, region or
    /// the summary. The store's "Set up later" is always there (D6).
    var canSkip: Bool {
        if step == .store { return true }
        let fixed: Set<Step> = [.welcome, .name, .startFrom, .goal, .region, .summary]
        return !fixed.contains(step) && !current.goals.isEmpty
    }

    // MARK: Navigation

    /// Get started, Continue.
    func next() {
        guard canContinue else { return }
        movedForward = true
        if step == .name { name = String(trimmedName.prefix(24)) }
        if isJumping, step == .region {
            step = store == nil ? .store : .summary
            return
        }
        if isJumping, step == .store {
            step = .summary
            return
        }
        // "Not in this list. Add it on the next step": the allergen search carries over.
        if step == .allergens, visibleGroups.isEmpty, current.goals.contains(.avoid) {
            avoidQuery = allergenQuery.trimmingCharacters(in: .whitespaces)
            allergenQuery = ""
        }
        let p = path
        if let i = p.firstIndex(of: step), i + 1 < p.count { step = p[i + 1] }
    }

    /// The previous step in the computed path; answers are kept. False on the first step (the
    /// add-person flow then closes).
    @discardableResult
    func back() -> Bool {
        movedForward = false
        isJumping = false
        let p = path
        guard let i = p.firstIndex(of: step), i > 0 else { return false }
        step = p[i - 1]
        return true
    }

    /// Skip and "Set up later": toward the summary, but never past the region.
    func skip() {
        guard canSkip else { return }
        movedForward = true
        resolver = nil
        if step == .store { store = nil }
        if mode == .firstRun, !Self.isValidZip(region?.zip) {
            isJumping = true
            step = .region
        } else {
            step = .summary
        }
    }

    /// Jumps to a step directly (previews and the DEBUG flow host).
    func show(_ step: Step) { self.step = step }

    // MARK: Start from

    /// Ticks "Start from Mia’s preferences" (a person id) or "Start fresh". The answers become a
    /// copy of that person's profile, to add on top or edit; the two profiles are never linked.
    func chooseStart(_ id: String) {
        guard id != startFrom else { return }
        startFrom = id
        if let person = existing.first(where: { $0.id == id }) {
            current = Self.answers(from: person.profile)
        } else {
            current = Answers()
        }
        openGroups = []
        allergenQuery = ""
        avoidQuery = ""
        resolver = nil
    }

    /// A saved profile as onboarding answers, so the steps show it ticked (the reverse of `profile`).
    static func answers(from p: Profile) -> Answers {
        var a = Answers()
        for c in p.allergens {
            if let leaves = c.leaves {
                a.allergens.formUnion(leaves)
            } else if let leaves = OnboardingCatalog.allergenGroups.first(where: { $0.id == c.id })?.leaves {
                a.allergens.formUnion(leaves)
            } else {
                a.allergens.insert(c.id)
            }
        }
        if !a.allergens.isEmpty { a.why.insert(.allergy) }
        a.medical = Set(p.medical)
        if !a.medical.isEmpty { a.why.insert(.medical) }
        a.diets = Set(p.diets.filter { ["vegan", "vegetarian", "keto", "paleo"].contains($0) })
        if !a.diets.isEmpty { a.why.insert(.diet) }
        a.religion = Set(p.diets.filter { ["halal", "kosher", "nobeef"].contains($0) })
        if !a.religion.isEmpty { a.why.insert(.religion) }
        a.avoid = p.avoid.map(\.id)
        a.custom = p.custom
        let strengths = p.avoid.map(\.strength) + p.custom.map(\.strength)
        if a.why.isEmpty, !strengths.isEmpty, strengths.allSatisfy({ $0 == .preferNot }) { a.why = [.dislike] }
        let base: Strength = a.why == [.dislike] ? .preferNot : .avoid
        for c in p.avoid where c.strength != base { a.flipped.insert("avoid:\(c.id)") }
        for c in p.custom where c.strength != base { a.flipped.insert("custom:\(c.label.lowercased())") }
        if !a.allergens.isEmpty || !a.medical.isEmpty || !p.diets.isEmpty || !p.avoid.isEmpty || !p.custom.isEmpty {
            a.goals.insert(.avoid)
        }
        if let goals = p.goals {
            a.goals.insert(.numbers)
            a.source = .know
            a.protein = goals.proteinG
            a.kcal = goals.kcal
        }
        return a
    }

    // MARK: Allergens

    /// Allergen groups a picked diet already covers (Q3): vegan hides milk, egg, fish.
    var coveredGroups: Set<String> {
        guard current.why.contains(.diet) else { return [] }
        return Set(current.diets.flatMap { OnboardingCatalog.dietCovers[$0] ?? [] })
    }

    /// "Already covered by your vegan diet: milk, egg, fish and shellfish." or nil.
    var coveredFootnote: String? {
        let covered = OnboardingCatalog.allergenGroups.filter { coveredGroups.contains($0.id) }
        guard !covered.isEmpty else { return nil }
        let diets = ["vegan", "vegetarian"].filter { current.diets.contains($0) && !(OnboardingCatalog.dietCovers[$0] ?? []).isEmpty }
        return "Already covered by your \(diets.joined(separator: " and ")) diet: \(covered.map { $0.label.lowercased() }.joined(separator: ", "))."
    }

    /// The groups shown: covered ones are hidden, and the search narrows them by name, leaf name
    /// or another name ("prawns" finds Fish and shellfish).
    var visibleGroups: [OnboardingCatalog.AllergenGroup] {
        let q = allergenQuery.trimmingCharacters(in: .whitespaces).lowercased()
        return OnboardingCatalog.allergenGroups.filter { g in
            guard !coveredGroups.contains(g.id) else { return false }
            guard !q.isEmpty else { return true }
            return g.label.lowercased().contains(q)
                || (g.leaves ?? []).contains { OnboardingCatalog.name($0).lowercased().contains(q) }
                || OnboardingCatalog.searchSynonyms.contains { $0.key.hasPrefix(q) && $0.value == g.id }
        }
    }

    /// Groups with leaves open in place; a search opens every match.
    func isOpen(_ group: OnboardingCatalog.AllergenGroup) -> Bool {
        group.leaves != nil && (openGroups.contains(group.id) || !allergenQuery.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// Ticks or unticks a single allergen card. Picking Peanut opens the related sheet
    /// (Tree nuts, Lupin), with nothing pre-ticked.
    func toggleAllergen(_ id: String) {
        if current.allergens.contains(id) {
            current.allergens.remove(id)
        } else {
            current.allergens.insert(id)
            if let related = OnboardingCatalog.related[id], related.contains(where: { !isPicked($0) }) {
                relatedFor = id
            }
        }
    }

    /// A whole group ("treenuts") or one allergen ("lupin") is picked.
    func isPicked(_ id: String) -> Bool {
        if let leaves = OnboardingCatalog.allergenGroups.first(where: { $0.id == id })?.leaves {
            return leaves.allSatisfy(current.allergens.contains)
        }
        return current.allergens.contains(id)
    }

    /// "Add selected" on the related sheet: a group adds all its leaves.
    func addRelated(_ ids: [String]) {
        for id in ids {
            if let leaves = OnboardingCatalog.allergenGroups.first(where: { $0.id == id })?.leaves {
                current.allergens.formUnion(leaves)
            } else {
                current.allergens.insert(id)
            }
        }
        relatedFor = nil
    }

    /// The picked leaves of a group, by leaf id.
    func leaves(of group: OnboardingCatalog.AllergenGroup) -> Set<String> {
        current.allergens.intersection(group.leaves ?? [])
    }

    func setLeaves(_ picked: Set<String>, of group: OnboardingCatalog.AllergenGroup) {
        current.allergens.subtract(group.leaves ?? [])
        current.allergens.formUnion(picked)
    }

    /// The answers as `AllergenChoice`s, in board order. A group with every leaf is the whole
    /// group; a subset keeps its leaves; each "Other" leaf is its own allergen. Every one is an
    /// allergy: a hard filter, "may contain" included (product owner, 2026-10-27).
    var allergenChoices: [AllergenChoice] { Self.allergenChoices(current, covered: coveredGroups) }

    static func allergenChoices(_ a: Answers, covered: Set<String>) -> [AllergenChoice] {
        var out: [AllergenChoice] = []
        for g in OnboardingCatalog.allergenGroups where !covered.contains(g.id) {
            guard let leaves = g.leaves else {
                if a.allergens.contains(g.id) { out.append(AllergenChoice(id: g.id, severity: .allergy)) }
                continue
            }
            let picked = leaves.filter(a.allergens.contains)
            if g.id == OnboardingCatalog.otherGroupId {
                out += picked.map { AllergenChoice(id: $0, severity: .allergy) }
            } else if picked.count == leaves.count {
                out.append(AllergenChoice(id: g.id, severity: .allergy))
            } else if !picked.isEmpty {
                out.append(AllergenChoice(id: g.id, severity: .allergy, leaves: picked))
            }
        }
        return out
    }

    // MARK: Anything else

    var onlyDislike: Bool { current.why == [.dislike] }

    func toggleAvoid(_ id: String) {
        if let i = current.avoid.firstIndex(of: id) { current.avoid.remove(at: i) } else { current.avoid.append(id) }
    }

    /// Catalog families whose name or other names contain the query, four at most.
    var avoidResults: [Catalog.Family] { Self.catalogSearch(avoidQuery) }

    static func catalogSearch(_ query: String) -> [Catalog.Family] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let hits = OnboardingCatalog.catalog.families.filter { f in
            f.kind == "ingredient" && (f.name.lowercased().contains(q) || f.terms.contains { $0.contains(q) })
        }
        return Array(hits.prefix(4))
    }

    /// "Make ‘…’ a custom filter" shows unless a family's name is exactly the query.
    var offersCustomFilter: Bool {
        let q = avoidQuery.trimmingCharacters(in: .whitespaces).lowercased()
        return !q.isEmpty && !avoidResults.contains { $0.name.lowercased() == q }
    }

    func startResolving() {
        let term = avoidQuery.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        resolver = .matching(term: term)
        avoidQuery = ""
    }

    /// Runs after the "Matching…" moment.
    func finishResolving() {
        guard case .matching(let term) = resolver else { return }
        resolver = Self.resolve(term)
    }

    /// Finds what a typed term means in the catalog: one family is a match with its names as
    /// keywords; several are a choice; none keeps the exact text (Low match).
    static func resolve(_ term: String) -> Resolver {
        let t = term.trimmingCharacters(in: .whitespaces).lowercased()
        let families = OnboardingCatalog.catalog.families.filter { $0.children == nil }
        let exact = families.filter { $0.name.lowercased() == t || $0.terms.contains(t) }
        if exact.count == 1, let f = exact.first { return .matched(match(term, family: f, confidence: "High match")) }
        let partial = families.filter { $0.name.lowercased().contains(t) || $0.terms.contains { $0.contains(t) } }
        var seen = Set<String>()
        let candidates = (exact + partial).filter { seen.insert($0.id).inserted }
        if candidates.count == 1, let f = candidates.first { return .matched(match(term, family: f, confidence: "Medium match")) }
        if candidates.count > 1 { return .ambiguous(term: term, choices: Array(candidates.prefix(3).map(\.id))) }
        return .matched(Match(term: term, label: term, terms: [t], confidence: "Low match",
                              note: "New ingredient. I’ll match it on labels and ask when unsure."))
    }

    private static func match(_ term: String, family f: Catalog.Family, confidence: String) -> Match {
        Match(term: term, label: f.name, terms: f.terms, confidence: confidence, note: f.note ?? "")
    }

    func pickResolverChoice(_ familyId: String) {
        guard case .ambiguous(let term, _) = resolver, let f = OnboardingCatalog.catalog.family(familyId) else { return }
        resolver = .matched(Self.match(term, family: f, confidence: "High match"))
    }

    func toggleResolverKeyword(_ keyword: String) {
        guard case .matched(var m) = resolver else { return }
        if m.off.contains(keyword) { m.off.remove(keyword) } else { m.off.insert(keyword) }
        resolver = .matched(m)
    }

    /// "Add it": a custom filter with the kept keywords.
    func confirmResolver() {
        guard case .matched(let m) = resolver, !m.kept.isEmpty else { return }
        // The same filter twice replaces the first: one rule per label.
        current.custom.removeAll { $0.label.lowercased() == m.label.lowercased() }
        current.custom.append(CustomChoice(label: m.label, terms: m.kept))
        resolver = nil
    }

    /// "Not right": back to the search with the term.
    func cancelResolver() {
        switch resolver {
        case .matching(let term), .ambiguous(let term, _): avoidQuery = term
        case .matched(let m): avoidQuery = m.term
        case nil: break
        }
        resolver = nil
    }

    func removeCustom(_ label: String) { current.custom.removeAll { $0.label == label } }

    // MARK: May contain and targets

    // "May contain" is always on: nothing that might hold an allergen is suggested (the engine
    // reads it for allergens and medical diets only). There is no switch for it any more.

    /// Prefilled from the goals (onboarding-tree.md › Targets).
    static func defaultTargets(_ phases: Set<Phase>) -> (protein: Int, kcal: Int) {
        switch (phases.contains(.cut), phases.contains(.bulk)) {
        case (true, true): (170, 2_200)
        case (true, false): (160, 1_900)
        case (false, true): (170, 2_800)
        default: phases.contains(.maintain) ? (140, 2_300) : (140, 2_100)
        }
    }

    /// From height, weight and age when the person asked for help, else the defaults for the goals.
    var suggestedTargets: (protein: Int, kcal: Int) {
        (current.source == .help ? current.body.targets(for: current.phases) : nil) ?? Self.defaultTargets(current.phases)
    }

    var protein: Int {
        get { current.protein ?? suggestedTargets.protein }
        set { current.protein = newValue }
    }

    var kcal: Int {
        get { current.kcal ?? suggestedTargets.kcal }
        set { current.kcal = newValue }
    }

    // MARK: Summary

    /// The name on the summary card: "You" for the owner, else the new person's name.
    var summaryName: String { currentName ?? "You" }

    /// The rows for one person's card.
    static func summaryItems(_ a: Answers) -> [SummaryItem] {
        var items: [SummaryItem] = []
        let avoids = a.goals.contains(.avoid)
        if avoids, a.why.contains(.allergy) {
            let covered = Set(a.why.contains(.diet) ? a.diets.flatMap { OnboardingCatalog.dietCovers[$0] ?? [] } : [])
            for c in allergenChoices(a, covered: covered) {
                var detail = "Allergy · “may contain” too"
                if let leaves = c.leaves { detail += " · " + leaves.map { OnboardingCatalog.name($0).lowercased() }.joined(separator: ", ") }
                items.append(SummaryItem(id: "allergen:\(c.id)", iconKey: c.id, title: OnboardingCatalog.name(c.id),
                                         detail: detail, kind: .avoid, isFlippable: false))
            }
        }
        if avoids, a.why.contains(.medical) {
            if a.medical.contains("celiac") {
                items.append(SummaryItem(id: "medical:celiac", iconKey: "celiac", title: "Gluten",
                                         detail: "Celiac · wheat, barley, rye, malt", kind: .avoid, isFlippable: false))
            }
            if a.medical.contains("heart") {
                items.append(SummaryItem(id: "medical:heart", iconKey: "heart", title: "Sodium under 1,500 mg a day",
                                         detail: "Heart health", kind: .avoid, isFlippable: false))
            }
            if a.medical.contains("sugar") {
                items.append(SummaryItem(id: "medical:sugar", iconKey: "bloodsugar", title: "Added sugar under 25 g a day",
                                         detail: "Blood sugar", kind: .avoid, isFlippable: false))
            }
            let other = a.medicalOther.trimmingCharacters(in: .whitespaces)
            if a.medical.contains("other"), !other.isEmpty {
                items.append(SummaryItem(id: "medical:other", iconKey: "medical", title: other,
                                         detail: "Medical diet · you described it", kind: .avoid, isFlippable: false))
            }
        }
        if avoids {
            for d in dietIds(a) {
                let name = OnboardingCatalog.catalog.diets[d]?.name ?? d
                items.append(SummaryItem(id: "diet:\(d)", iconKey: d, title: name, detail: "Diet or belief", kind: .diet, isFlippable: false))
            }
            let other = a.religionOther.trimmingCharacters(in: .whitespaces)
            if a.why.contains(.religion), a.religion.contains("other"), !other.isEmpty {
                items.append(SummaryItem(id: "religion:other", iconKey: "religion", title: other,
                                         detail: "You described it", kind: .diet, isFlippable: false))
            }
            for id in a.avoid {
                guard let f = OnboardingCatalog.catalog.family(id) else { continue }
                let key = "avoid:\(id)"
                items.append(SummaryItem(id: key, iconKey: f.icon, title: f.name,
                                         detail: "Also catches " + f.terms.prefix(4).joined(separator: ", "),
                                         kind: strength(a, key) == .avoid ? .avoid : .preferNot, isFlippable: true))
            }
            for c in a.custom where !c.terms.isEmpty {
                let key = "custom:\(c.label.lowercased())"
                items.append(SummaryItem(id: key, iconKey: c.label, title: c.label,
                                         detail: "Also catches " + c.terms.prefix(4).joined(separator: ", "),
                                         kind: strength(a, key) == .avoid ? .avoid : .preferNot, isFlippable: true))
            }
        }
        if a.goals.contains(.numbers) {
            let d = defaultTargets(a.phases)
            let protein = a.protein ?? d.protein, kcal = a.kcal ?? d.kcal
            items.append(SummaryItem(id: "goal:targets", iconKey: "protein",
                                     title: "\(protein) g protein in \(kcal.formatted()) kcal",
                                     detail: "Shown as % of your goal", kind: .goal, isFlippable: false))
        }
        return items
    }

    /// "3 to avoid · 1 other" (spec 01 summary card).
    static func summaryLine(_ items: [SummaryItem]) -> String {
        let avoid = items.filter { $0.kind == .avoid }.count
        let other = items.count - avoid
        guard !items.isEmpty else { return "Nothing set yet" }
        var parts: [String] = []
        if avoid > 0 { parts.append("\(avoid) to avoid") }
        if other > 0 { parts.append("\(other) other") }
        return parts.joined(separator: " · ")
    }

    /// Flips a summary rule between Avoid and Prefer not (D12).
    func flip(_ key: String) {
        if current.flipped.contains(key) { current.flipped.remove(key) } else { current.flipped.insert(key) }
    }

    /// Avoid by default; Prefer not when the only reason is "I just don’t like some foods".
    /// A summary flip reverses it.
    static func strength(_ a: Answers, _ key: String) -> Strength {
        let base: Strength = a.why == [.dislike] ? .preferNot : .avoid
        guard a.flipped.contains(key) else { return base }
        return base == .avoid ? .preferNot : .avoid
    }

    private static func dietIds(_ a: Answers) -> [String] {
        let diets = a.why.contains(.diet) ? ["vegan", "vegetarian", "keto", "paleo"].filter(a.diets.contains) : []
        let religion = a.why.contains(.religion) ? ["halal", "kosher", "nobeef"].filter(a.religion.contains) : []
        return diets + religion
    }

    // MARK: Output

    /// One person's answers as a `LabelSageCore.Profile` (onboarding-tree.md › Output). Answers
    /// from a branch that was unticked later are left out.
    static func profile(_ a: Answers) -> Profile {
        var p = Profile()
        if a.goals.contains(.avoid) {
            if a.why.contains(.allergy) {
                let covered = Set(a.why.contains(.diet) ? a.diets.flatMap { OnboardingCatalog.dietCovers[$0] ?? [] } : [])
                p.allergens = allergenChoices(a, covered: covered)
            }
            p.mayContain = true
            if a.why.contains(.medical) { p.medical = ["celiac", "heart", "sugar"].filter(a.medical.contains) }
            p.diets = dietIds(a)
            p.avoid = a.avoid.map { AvoidChoice(id: $0, strength: strength(a, "avoid:\($0)")) }
            p.custom = a.custom.map {
                CustomChoice(label: $0.label, terms: $0.terms, strength: strength(a, "custom:\($0.label.lowercased())"))
            }
            // The free text keeps no terms: the chat agent proposes them later, with a confirm.
            let medicalOther = a.medicalOther.trimmingCharacters(in: .whitespaces)
            if a.why.contains(.medical), a.medical.contains("other"), !medicalOther.isEmpty {
                p.custom.append(CustomChoice(label: medicalOther, terms: []))
            }
            let religionOther = a.religionOther.trimmingCharacters(in: .whitespaces)
            if a.why.contains(.religion), a.religion.contains("other"), !religionOther.isEmpty {
                p.custom.append(CustomChoice(label: religionOther, terms: []))
            }
        }
        if a.goals.contains(.numbers) {
            let d = defaultTargets(a.phases)
            p.goals = Goals(proteinG: a.protein ?? d.protein, kcal: a.kcal ?? d.kcal)
        }
        return p
    }

    /// First run: the household to save, the owner only. nil until the region is set: the region
    /// is required (D6). Everyone else is added later from Family, one person at a time.
    func makeHousehold() -> Household? {
        guard mode == .firstRun, let region, Self.isValidZip(region.zip) else { return nil }
        let owner = Person(id: "you", name: "You", isOwner: true, profile: Self.profile(current))
        return Household(people: [owner], region: region, store: store)
    }

    /// Add a person: the new person with their own profile (a copy, never linked). nil without a
    /// name or with a name already in the household.
    func makePerson(id: String = "person-\(UUID().uuidString)") -> Person? {
        guard mode == .addPerson, let name = currentName, !isNameTaken(name) else { return nil }
        return Person(id: id, name: name, isOwner: false, profile: Self.profile(current))
    }

    /// The household "Try it" on the summary checks: the owner, or the new person alone.
    var tryItHousehold: Household? {
        switch mode {
        case .firstRun: makeHousehold()
        case .addPerson: makePerson(id: "new").map { Household(people: [$0]) }
        }
    }

    /// The "Me" quick pick, typed or tapped.
    static func isMe(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "me"
    }

    /// "Mia’s", or "your" for the owner.
    static func possessive(_ person: Person) -> String {
        person.isOwner ? "your" : "\(person.name)\u{2019}s"
    }

    // MARK: Lines

    /// LabelSage's line for the step: the screen title (spec 01 › Steps, prototype `LWS`).
    var line: String {
        let who = currentName
        switch step {
        case .welcome: return "I check the ingredients for everyone you shop for. Hidden names too."
        case .name: return "Who else do you shop for? Add their name."
        case .startFrom:
            return "Where should \(who.map { "\($0)\u{2019}s" } ?? "their") profile start? You can change anything next."
        case .goal: return who.map { "What should I check for \($0)?" } ?? "What should I check for?"
        case .why: return who.map { "Why does \($0) avoid some foods? Pick all that fit." } ?? "Why do you avoid some foods? Pick all that fit."
        case .diet: return who.map { "Any diet for \($0)?" } ?? "Any diet I should check for?"
        case .religion: return "Halal, kosher or other? I\u{2019}ll catch hidden gelatin too."
        case .medical: return who.map { "Which medical diet for \($0)?" } ?? "Which medical diet?"
        case .allergens: return who.map { "What does \($0) avoid?" } ?? "What do you avoid?"
        case .avoid: return who.map { "Anything else \($0) avoids? I\u{2019}ll catch it under other names too." }
            ?? "Anything else you avoid? I\u{2019}ll catch it under other names too."
        case .source: return "Where do your targets come from?"
        case .body: return "A few numbers, and I\u{2019}ll suggest your targets."
        case .phase: return "What are you working toward right now?"
        case .targets:
            return current.source == .help && current.body.isComplete
                ? "Here are targets from your numbers. Change them any time."
                : "Here are your daily targets. Change them if your coach set others."
        case .region: return "Where are you? Products differ by area."
        case .store: return "Where do you shop? I\u{2019}ll find other options there."
        case .depth: return "Allergies are set. Fine-tune now, or start?"
        case .prefs: return "Anything you\u{2019}d rather skip? I\u{2019}ll show it lower, never hide it."
        case .summary: return who.map { "Here\u{2019}s what I\u{2019}ll watch for \($0)." } ?? "Here\u{2019}s what I\u{2019}ll watch for."
        }
    }

    /// LabelSage's pose for the step (spec 01 › Steps).
    var pose: MascotState {
        switch step {
        case .welcome: .wave
        case .name, .why, .diet, .religion, .medical, .phase, .prefs: .listen
        case .goal, .allergens, .avoid, .region, .store: .point
        case .startFrom, .source, .body: .thinking
        case .targets, .depth: .talk
        case .summary: .done
        }
    }

    /// The primary button's label.
    var primaryTitle: String {
        switch step {
        case .welcome: "Get started"
        case .summary: mode == .addPerson ? "Save \(currentName ?? "")" : "Check my first product"
        default: "Continue"
        }
    }
}
