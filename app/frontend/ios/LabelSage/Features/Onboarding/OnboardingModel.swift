import Foundation
import Observation
import LabelSageCore

/// The onboarding decision tree (`docs/logic/onboarding-tree.md`, prototype `OnboardSimple.dc.html`).
///
/// The path is computed from the answers so far, so a step appears only when an earlier answer
/// needs it. With "My family" the per-person steps run once for each person; region and store are
/// asked once for the household, and the region is required: Skip never passes it.
@Observable
final class OnboardingModel {
    // MARK: Types

    /// Every step in the tree, in the order the path can visit them.
    enum Step: String, CaseIterable, Sendable {
        case welcome, household, firstProfile, goal, why, diet, religion, medical, allergens, severity
        case avoid, strict, source, phase, targets, nextPerson, region, store, depth, prefs, summary
    }

    enum HouseholdKind: Sendable { case justMe, family }
    enum Goal: Sendable { case avoid, numbers }
    enum Why: String, CaseIterable, Sendable { case medical, allergy, diet, religion, dislike }
    enum TargetSource: Sendable { case know, help }
    enum Phase: String, CaseIterable, Sendable { case cut, bulk, maintain, whole, energy }
    enum Depth: Sendable { case start, more }

    /// One person's answers. Cleared when the loop moves to the next person.
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
        /// By allergen choice id; missing means allergy (D3).
        var severity: [String: Severity] = [:]
        /// "Anything else" catalog families, in the order they were ticked.
        var avoid: [String] = []
        var custom: [CustomChoice] = []
        /// Rule keys switched away from the default strength on the summary (D12).
        var flipped: Set<String> = []
        /// nil follows the default ("On because of your answers").
        var mayContain: Bool?
        /// "Same allergies for anyone else?" names: they get a copy of this profile.
        var sameFor: [String] = []
        var source: TargetSource?
        var phases: Set<Phase> = []
        var protein: Int?
        var kcal: Int?
    }

    /// A person whose questions are done.
    struct DonePerson: Equatable, Sendable {
        var name: String
        var answers: Answers
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

    // MARK: State

    private(set) var step: Step = .welcome
    /// True after Continue or Skip, false after Back: the step transition's direction.
    private(set) var movedForward = true
    var household: HouseholdKind?
    var firstName = ""
    var team: [String] = []
    /// Whose turn it is: 0 is `firstName`, then `team` in order.
    private(set) var personIndex = 0
    var current = Answers()
    private(set) var done: [DonePerson] = []
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

    init() {}

    // MARK: Path

    /// The steps for the answers so far (onboarding-tree.md › The path).
    var path: [Step] {
        var p: [Step] = [.welcome, .household]
        if household == .family { p.append(.firstProfile) }
        p.append(.goal)
        if current.goals.contains(.avoid) {
            p.append(.why)
            if current.why.contains(.diet) { p.append(.diet) }
            if current.why.contains(.religion) { p.append(.religion) }
            if current.why.contains(.medical) { p.append(.medical) }
            if current.why.contains(.allergy) { p += [.allergens, .severity] }
            p.append(.avoid)
            if !onlyDislike { p.append(.strict) }
        }
        if current.goals.contains(.numbers) { p += [.source, .phase, .targets] }
        if hasNextPerson { p.append(.nextPerson) } else { p += [.region, .store] }
        if !current.goals.isEmpty { p.append(.depth) }
        if depth == .more { p.append(.prefs) }
        p.append(.summary)
        return p
    }

    private var index: Int { path.firstIndex(of: step) ?? 0 }

    var isFamily: Bool { household == .family }
    var hasNextPerson: Bool { isFamily && personIndex < team.count }

    /// The person whose questions are on screen; nil for "Just me".
    var currentName: String? {
        guard isFamily else { return nil }
        let name = personIndex == 0 ? firstName.trimmingCharacters(in: .whitespaces) : team[personIndex - 1]
        return name.isEmpty ? nil : name
    }

    var nextPersonName: String? { hasNextPerson ? team[personIndex] : nil }

    /// Progress dots: 0 who you shop for, 1 their allergies, 2 where you shop.
    var section: Int {
        switch step {
        case .welcome, .household, .firstProfile, .nextPerson: 0
        case .region, .store, .depth, .prefs, .summary: 2
        default: 1
        }
    }

    // MARK: Validation

    /// Continue is enabled (onboarding-tree.md › Validation).
    var canContinue: Bool { missingAnswer == nil }

    /// What is missing, for the disabled Continue's VoiceOver hint; nil when the step is valid.
    var missingAnswer: String? {
        switch step {
        case .household: household == nil ? "Pick one" : nil
        case .firstProfile: firstName.trimmingCharacters(in: .whitespaces).isEmpty ? "Add a name" : nil
        case .goal, .why, .medical, .phase: isEmpty(step) ? "Pick at least one" : nil
        case .allergens: allergenChoices.isEmpty ? "Pick at least one allergen" : nil
        case .source: current.source == nil ? "Pick one" : nil
        case .region: Self.isValidZip(region?.zip) ? nil : "Set your city or ZIP code"
        case .store: store == nil ? "Pick a store, or set it up later" : nil
        case .depth: depth == nil ? "Pick one" : nil
        default: nil
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

    static func isValidZip(_ zip: String?) -> Bool {
        guard let zip else { return false }
        return zip.count == 5 && zip.allSatisfy(\.isASCII) && zip.allSatisfy(\.isNumber)
    }

    /// Skip shows on optional steps; never on welcome, household, goal, region, the person
    /// hand-over or the summary. The store's "Set up later" is always there (D6).
    var canSkip: Bool {
        if step == .store { return true }
        let fixed: Set<Step> = [.welcome, .household, .goal, .region, .nextPerson, .summary]
        return !fixed.contains(step) && !current.goals.isEmpty
    }

    // MARK: Navigation

    /// Get started, Continue, "Start Leo’s questions".
    func next() {
        guard canContinue else { return }
        movedForward = true
        if step == .nextPerson {
            startNextPerson()
            return
        }
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

    /// The previous step in the computed path; answers are kept.
    func back() {
        movedForward = false
        isJumping = false
        let p = path
        if let i = p.firstIndex(of: step), i > 0 { step = p[i - 1] }
    }

    /// Skip and "Set up later": toward the summary, but never past the region, and never past
    /// someone whose questions are still to come.
    func skip() {
        guard canSkip else { return }
        movedForward = true
        resolver = nil
        if step == .store { store = nil }
        let p = path
        if let i = p.firstIndex(of: step), p[(i + 1)...].contains(.nextPerson) {
            step = .nextPerson
        } else if !Self.isValidZip(region?.zip) {
            isJumping = true
            step = .region
        } else {
            step = .summary
        }
    }

    /// Jumps to a step directly (previews and the DEBUG flow host).
    func show(_ step: Step) { self.step = step }

    /// Snapshots this person's answers and starts the next person's questions at `goal`.
    private func startNextPerson() {
        guard hasNextPerson else { return }
        done.append(DonePerson(name: currentName ?? "", answers: current))
        current = Answers()
        personIndex += 1
        openGroups = []
        allergenQuery = ""
        avoidQuery = ""
        step = .goal
    }

    /// "Leo has the same allergies as Mia": Leo gets a copy and skips the questions.
    func nextPersonSharesAllergies() {
        guard let name = nextPersonName else { return }
        current.sameFor.append(name)
        team.remove(at: personIndex)
        movedForward = true
        step = hasNextPerson ? .nextPerson : .region
    }

    // MARK: First profile

    /// Adds someone else at home. Ignores blanks, duplicates and the first person's name.
    func addTeamMember(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !team.contains(n), n != firstName.trimmingCharacters(in: .whitespaces) else { return }
        team.append(n)
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
    /// group; a subset keeps its leaves; each "Other" leaf is its own allergen.
    var allergenChoices: [AllergenChoice] { Self.allergenChoices(current, covered: coveredGroups) }

    static func allergenChoices(_ a: Answers, covered: Set<String>) -> [AllergenChoice] {
        var out: [AllergenChoice] = []
        for g in OnboardingCatalog.allergenGroups where !covered.contains(g.id) {
            let sev = { (id: String) in a.severity[id] ?? .allergy }
            guard let leaves = g.leaves else {
                if a.allergens.contains(g.id) { out.append(AllergenChoice(id: g.id, severity: sev(g.id))) }
                continue
            }
            let picked = leaves.filter(a.allergens.contains)
            if g.id == OnboardingCatalog.otherGroupId {
                out += picked.map { AllergenChoice(id: $0, severity: sev($0)) }
            } else if picked.count == leaves.count {
                out.append(AllergenChoice(id: g.id, severity: sev(g.id)))
            } else if !picked.isEmpty {
                out.append(AllergenChoice(id: g.id, severity: sev(g.id), leaves: picked))
            }
        }
        return out
    }

    func severity(of id: String) -> Severity { current.severity[id] ?? .allergy }
    func setSeverity(_ severity: Severity, for id: String) { current.severity[id] = severity }

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

    /// On when any allergen is an allergy or celiac is picked.
    var mayContainDefault: Bool { Self.mayContainDefault(current) }

    static func mayContainDefault(_ a: Answers) -> Bool {
        let allergy = a.why.contains(.allergy) && allergenChoices(a, covered: []).contains { $0.severity == .allergy }
        return allergy || (a.why.contains(.medical) && a.medical.contains("celiac"))
    }

    var mayContain: Bool {
        get { current.mayContain ?? mayContainDefault }
        set { current.mayContain = newValue }
    }

    /// Prefilled from the goals (onboarding-tree.md › Targets).
    static func defaultTargets(_ phases: Set<Phase>) -> (protein: Int, kcal: Int) {
        switch (phases.contains(.cut), phases.contains(.bulk)) {
        case (true, true): (170, 2_200)
        case (true, false): (160, 1_900)
        case (false, true): (170, 2_800)
        default: phases.contains(.maintain) ? (140, 2_300) : (140, 2_100)
        }
    }

    var protein: Int {
        get { current.protein ?? Self.defaultTargets(current.phases).protein }
        set { current.protein = newValue }
    }

    var kcal: Int {
        get { current.kcal ?? Self.defaultTargets(current.phases).kcal }
        set { current.kcal = newValue }
    }

    // MARK: Summary

    /// Everyone answered so far, the current person last.
    var people: [DonePerson] { done + [DonePerson(name: currentName ?? "", answers: current)] }

    /// The rows for one person's card.
    static func summaryItems(_ a: Answers) -> [SummaryItem] {
        var items: [SummaryItem] = []
        let avoids = a.goals.contains(.avoid)
        if avoids, a.why.contains(.allergy) {
            let may = a.mayContain ?? mayContainDefault(a)
            let covered = Set(a.why.contains(.diet) ? a.diets.flatMap { OnboardingCatalog.dietCovers[$0] ?? [] } : [])
            for c in allergenChoices(a, covered: covered) {
                var detail = c.severity == .intolerance ? "Intolerance · in the ingredients only"
                    : "Allergy" + (may ? " · “may contain” too" : "")
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
    func flip(_ key: String, person: Int) {
        func toggle(_ a: inout Answers) {
            if a.flipped.contains(key) { a.flipped.remove(key) } else { a.flipped.insert(key) }
        }
        if person < done.count { toggle(&done[person].answers) } else { toggle(&current) }
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
            p.mayContain = a.why == [.dislike] ? false : (a.mayContain ?? mayContainDefault(a))
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

    /// The household to save. nil until the region is set: the region is required (D6).
    ///
    /// Each person gets their own profile; "same allergies" names get a copy of it. One owner at
    /// most (Q-ONB-1): "Just me", or in a family the first person named "Me". A name already used
    /// is not added twice.
    func makeHousehold() -> Household? {
        guard let region, Self.isValidZip(region.zip) else { return nil }
        var people: [Person] = []
        var usedNames = Set<String>()
        for (personSlot, person) in self.people.enumerated() {
            let profile = Self.profile(person.answers)
            let names = [person.name] + person.answers.sameFor
            for (nameSlot, raw) in names.enumerated() {
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let hasOwner = people.contains(where: \.isOwner)
                let isOwner = !hasOwner && (isFamily ? Self.isMe(name) : personSlot == 0 && nameSlot == 0)
                let isNew = usedNames.insert(name.lowercased()).inserted
                guard isOwner || (!name.isEmpty && isNew && !Self.isMe(name)) else { continue }
                let shown = isOwner ? "You" : name
                let id = isOwner ? "you" : "person-\(people.count)"
                people.append(Person(id: id, name: shown, isOwner: isOwner, profile: profile))
            }
        }
        return Household(people: people, region: region, store: store)
    }

    /// The "Me" quick pick, typed or tapped.
    static func isMe(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "me"
    }

    /// "Same allergies for anyone else?": a name that gets a copy of this person's profile. A name
    /// that still has its own questions to come, or is already set, is not taken.
    func addSameFor(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = ([firstName] + team + done.flatMap { [$0.name] + $0.answers.sameFor } + current.sameFor)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard !n.isEmpty, !taken.contains(n.lowercased()) else { return }
        current.sameFor.append(n)
    }

    // MARK: Lines

    /// LabelSage's line for the step: the screen title (spec 01 › Steps, prototype `LWS`).
    var line: String {
        let who = currentName
        switch step {
        case .welcome: return "I check the ingredients for everyone you shop for. Hidden names too."
        case .household: return "Who do you shop for?"
        case .firstProfile:
            return team.isEmpty ? "What should I call them? Add everyone at home."
                : "Heads up: I’ll ask a few questions for each person, one at a time."
        case .goal:
            if personIndex > 0, let who { return "What should I check for \(who)?" }
            return "What should I check for?"
        case .why: return who.map { "Why does \($0) avoid some foods? Pick all that fit." } ?? "Why do you avoid some foods? Pick all that fit."
        case .diet: return who.map { "Any diet for \($0)?" } ?? "Any diet I should check for?"
        case .religion: return "Halal, kosher or other? I’ll catch hidden gelatin too."
        case .medical: return who.map { "Which medical diet for \($0)?" } ?? "Which medical diet?"
        case .allergens: return who.map { "What does \($0) avoid?" } ?? "What do you avoid?"
        case .severity: return who.map { "For \($0): allergy or intolerance? Pick one for each." } ?? "Allergy or intolerance? Pick one for each."
        case .avoid: return who.map { "Anything else \($0) avoids? I’ll catch it under other names too." }
            ?? "Anything else you avoid? I’ll catch it under other names too."
        case .strict: return who.map { "‘May contain’ labels for \($0)?" } ?? "‘May contain’ labels?"
        case .source: return "Where do your targets come from?"
        case .phase: return "What are you working toward right now?"
        case .targets: return "Here are your daily targets. Change them if your coach set others."
        case .nextPerson:
            let next = nextPersonName ?? ""
            return "\(who ?? "Their")’s allergies are set. Now \(next): same questions, \(next)’s answers."
        case .region: return "Where are you? Products differ by area."
        case .store: return "Where do you shop? I’ll find other options there."
        case .depth: return "Allergies are set. Fine-tune now, or start?"
        case .prefs: return "Anything you’d rather skip? I’ll show it lower, never hide it."
        case .summary:
            if !done.isEmpty { return "Here’s what I’ll watch for your family." }
            return who.map { "Here’s what I’ll watch for \($0)." } ?? "Here’s what I’ll watch for."
        }
    }

    /// LabelSage's pose for the step (spec 01 › Steps).
    var pose: MascotState {
        switch step {
        case .welcome: .wave
        case .household, .why, .diet, .religion, .medical, .phase, .prefs: .listen
        case .firstProfile: team.isEmpty ? .listen : .talk
        case .goal, .allergens, .avoid, .region, .store: .point
        case .severity, .strict, .source: .thinking
        case .targets, .nextPerson, .depth: .talk
        case .summary: .done
        }
    }

    /// The primary button's label.
    var primaryTitle: String {
        switch step {
        case .welcome: "Get started"
        case .nextPerson: "Start \(nextPersonName ?? "")’s questions"
        case .summary: "Check my first product"
        default: "Continue"
        }
    }
}
