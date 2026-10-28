import SwiftUI
import LabelSageCore

/// A product and the engine's verdict for the household, as shown in the thread.
struct ProductAnswer: Identifiable, Equatable {
    var id: String { product.id }
    let product: Product
    /// From `VerdictService` only.
    let verdict: HouseholdVerdict
}

/// A change to one person's rules, shown as a change card. Nothing is saved until Confirm (D14).
struct ChangeProposal: Equatable {
    enum State: Hashable { case proposed, saved, cancelled, undone }

    let personID: String
    /// "Mia", or "you" for the owner.
    let personName: String
    /// The catalog family ("sesame"), or nil for a custom item matched by its own words.
    let familyID: String?
    /// "sesame", as shown on the chip.
    let label: String
    /// An allergen takes Allergy or Intolerance; anything else goes in the person's Avoid list.
    let isAllergen: Bool
    var severity: Severity
    var state: State = .proposed
    /// What the person avoids now, for the card's line.
    let currentItems: [String]
}

/// One entry in the thread. LabelSage's `line` goes to the dock while it is the latest answer, and
/// stays in the thread as plain text once a newer one replaces it (D9).
struct ChatMessage: Identifiable, Equatable {
    enum Kind: Equatable {
        /// The person's message.
        case user(String)
        /// One product with its verdict.
        case product(ProductAnswer)
        /// "Which one?": up to three products for an ambiguous name.
        case choices([ProductAnswer])
        /// Other options: the product they replace (if any) and up to three cards.
        case options(anchor: Product?, [ProductAnswer])
        /// A change card.
        case change(ChangeProposal)
        /// Each person's preferences, read-only and live, from the "Change the preferences" tile.
        case preferences
        /// "Leo isn't in your family yet" with a Family button.
        case familyLink
        /// A line with no card.
        case text
    }

    let id = UUID()
    var kind: Kind
    var line: String?

    /// LabelSage's answer, not the person's message.
    var isAnswer: Bool { if case .user = kind { false } else { true } }
}

/// One chat: its title for the history menu, its messages and the context the agent keeps
/// (`chat-agent.md` › Context the agent keeps per chat). A new chat starts empty.
struct ChatThread: Identifiable {
    let id = UUID()
    /// When the chat began, for the date in the history menu.
    let started = Date()
    var title: String?
    var messages: [ChatMessage] = []
    /// Up to three products, newest last.
    var lastProducts: [Product] = []
    /// The first product of this chat, for "go back to the first one".
    var firstProduct: Product?
}

/// The chat agent: reads each message with `IntentRouter`, acts in plain Swift (ProductSource,
/// VerdictService, the change card) and writes LabelSage's line. Code decides, LabelSage explains:
/// every flag comes from `VerdictService`; `ExplanationService` may only reword a reason line.
@Observable
final class ChatModel {
    /// What the chat asks its host to do.
    struct Actions {
        var openCamera: () -> Void = {}
        var openProduct: (Product) -> Void = { _ in }
        var compare: (Product, Product) -> Void = { _, _ in }
        var openFamily: () -> Void = {}
        /// Saves the household; throws when the store fails (nothing changes then).
        var updateHousehold: (Household) throws -> Void = { _ in }
    }

    private(set) var household: Household {
        didSet { if household != oldValue { peopleLine = ChatScreen.peopleLine(household) } }
    }
    /// "Mia: peanut, tree nuts · You: seed oils", the subtitle; made again only when the household changes.
    private(set) var peopleLine: String
    /// The open chat.
    private(set) var thread = ChatThread()
    /// Past chats, newest first.
    // shortcut: in memory only, lost at quit; move to SwiftData with the T13 shell if the team wants history kept.
    private(set) var history: [ChatThread] = []
    /// LabelSage's line in the dock.
    private(set) var dockLine: String
    private(set) var pose: MascotState = .talk
    /// True while a message is being answered: the thinking row shows and he reads.
    private(set) var isWorking = false
    var toast: ToastMessage?

    @ObservationIgnored var actions: Actions
    @ObservationIgnored var goTos: [Product]
    @ObservationIgnored private let source: any ProductSource
    @ObservationIgnored private let verdictService: VerdictService
    @ObservationIgnored private let explanationService: ExplanationService
    @ObservationIgnored private var work: Task<Void, Never>?
    /// The last typed message, as written: the product finder's request.
    @ObservationIgnored private var lastRequest: String?
    /// The household before the last saved change, for Undo.
    @ObservationIgnored private var beforeLastSave: (household: Household, messageID: UUID)?

    static let returningLine = "Check a product, or ask me about one."

    init(household: Household, goTos: [Product] = [], source: any ProductSource, verdictService: VerdictService,
         explanationService: ExplanationService, actions: Actions = Actions()) {
        self.household = household
        self.peopleLine = ChatScreen.peopleLine(household)
        self.goTos = goTos
        self.source = source
        self.verdictService = verdictService
        self.explanationService = explanationService
        self.actions = actions
        self.dockLine = Self.returningLine
        ChatAI.prewarm()
    }

    private var catalog: Catalog { verdictService.engine.catalog }
    /// "you and Mia".
    var namesLine: String { household.people.map(\.displayName).formatted(.list(type: .and)) }
    var title: String { thread.title ?? "New chat" }

    // MARK: household and history

    /// The host saved a new household (Family, onboarding): later checks use it.
    func householdChanged(_ new: Household) {
        household = new
    }

    /// Keeps the open chat in history and starts an empty one.
    func newChat() {
        work?.cancel()
        isWorking = false
        if !thread.messages.isEmpty { history.insert(thread, at: 0) }
        thread = ChatThread()
        setLine(Self.returningLine, pose: .talk, announce: false)
    }

    /// The composer's Stop while a check runs: drops the answer still working.
    func stop() {
        work?.cancel()
        isWorking = false
        setLine("Stopped. Ask me again any time.", pose: .idle, announce: true)
    }

    /// Restores a past chat and its context.
    func open(_ past: ChatThread) {
        work?.cancel()
        isWorking = false
        guard let index = history.firstIndex(where: { $0.id == past.id }) else { return }
        let restored = history.remove(at: index)
        if !thread.messages.isEmpty { history.insert(thread, at: 0) }
        thread = restored
        let line = restored.messages.last(where: { $0.line != nil })?.line ?? Self.returningLine
        setLine(line, pose: .talk, announce: false)
    }

    // MARK: sending

    /// Sends a typed message: the user bubble, then the answer.
    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        append(.init(kind: .user(trimmed)))
        if thread.title == nil { thread.title = Self.title(for: trimmed) }
        let routed = IntentRouter.read(trimmed, names: household.people.map(\.name))
        lastRequest = trimmed
        let answering = Perf.begin("chat.answer")
        run {
            var intent = routed
            // The router missed (small talk that isn't a greeting): the on-device model reads it.
            if IntentRouter.isMiss(routed, text: trimmed),
               let read = await ModelIntentReader.read(trimmed, household: self.household) {
                guard !Task.isCancelled else { return }
                intent = read
            }
            await self.handle(intent)
            self.lastRequest = nil
            Perf.end(answering)
        }
    }

    /// The answer to `intent`, for previews and the send path.
    func handle(_ intent: ChatIntent) async {
        switch intent {
        case .check(let name): await check(name: name)
        case .ingredient(let phrase): explainIngredient(phrase)
        case .otherOptions(let query, let without): await otherOptions(query: query, without: without)
        case .compare: compareLast()
        case .changeAllergies(let person, let item, let severity): proposeChange(person: person, item: item, severity: severity)
        case .pivot(let pivot): await handle(pivot)
        case .smallTalk(let vent):
            if vent {
                reply(.text, "Every label, every time. I’ll take that part.", pose: .listen)
            } else {
                reply(.text, "I check products for \(namesLine). Scan one, or ask me about one.", pose: .talk)
            }
        }
    }

    /// A product the camera checked: its card lands in the thread (spec 02, "the result returns here").
    func showChecked(_ product: Product) {
        run { await self.show(product) }
    }

    /// The photo button: on-device OCR, then the same check as the camera's ingredients mode.
    func checkPhoto(_ image: UIImage) {
        append(.init(kind: .user("Ingredients photo")))
        if thread.title == nil { thread.title = "Ingredients photo" }
        run {
            let lines = await TextRecognizer.lines(in: image)
            guard let text = IngredientsText.extract(from: lines) else {
                self.reply(.text, "I couldn’t read that. Try a sharper photo of the ingredients.", pose: .thinking)
                return
            }
            let product = Product(name: ScanModel.photoName, ingredientsText: text)
            guard LabelParser.parse(product, catalog: self.catalog).hasList else {
                self.reply(.text, "I couldn’t read that. Try a sharper photo of the ingredients.", pose: .thinking)
                return
            }
            await self.show(product)
        }
    }

    /// The "Change the preferences" tile: what LabelSage checks for each person, then "tell me what to change".
    func showPreferences() {
        if thread.title == nil { thread.title = "Preferences" }
        reply(.preferences, "Tell me what to change, like “add sesame for \(exampleName)”.", pose: .listen)
    }

    /// A name for examples: the first person who isn't the owner, else "me".
    private var exampleName: String { household.people.first(where: { !$0.isOwner })?.name ?? "me" }

    /// The thread's opening line: about preferences when the chat started there, else about products.
    var openingLine: String {
        if case .preferences = thread.messages.first?.kind {
            return "Here’s what I check for each person. Tap a name to see the details."
        }
        return "Point the camera at a barcode, or ask me about any product."
    }

    /// The composer's placeholder: what the person can say next, from the latest answer (known issue 7).
    var composerPlaceholder: String { Self.placeholder(after: thread.messages.last(where: \.isAnswer)?.kind, exampleName: exampleName) }

    /// "Like “add sesame for Mia”…" after the preferences, "Ask about this product…" after a product.
    static func placeholder(after kind: ChatMessage.Kind?, exampleName: String) -> String {
        switch kind {
        case nil: return "Ask \(Brand.mascot) about a product\u{2026}"
        case .preferences: return "Like \u{201C}add sesame for \(exampleName)\u{201D}\u{2026}"
        case .change(let proposal) where proposal.state == .proposed: return "Confirm above, or change something else\u{2026}"
        case .change: return "Change something else\u{2026}"
        case .product: return "Ask about this product, or find better\u{2026}"
        case .choices: return "Pick one above, or name it exactly\u{2026}"
        case .options: return "Ask about one of these\u{2026}"
        case .familyLink: return "Ask about someone in your family\u{2026}"
        case .text, .user: return "Message \(Brand.mascot)\u{2026}"
        }
    }

    /// Runs one answer at a time; a new message cancels the one still working.
    private func run(_ body: @escaping @MainActor () async -> Void) {
        work?.cancel()
        isWorking = true
        pose = .reading
        work = Task {
            await body()
            if !Task.isCancelled { self.isWorking = false }
        }
    }

    // MARK: check and ask

    private func check(name: String?) async {
        guard let name else {
            reply(.text, "Point the camera at the barcode and I’ll check it.", pose: .point)
            actions.openCamera()
            return
        }
        do {
            let searching = Perf.begin("chat.search")
            defer { Perf.end(searching) }
            var found = try await source.search(name, region: household.region, store: household.store, limit: 3)
            if found.isEmpty { found = try await looseSearch(name) }
            guard !Task.isCancelled else { return }
            switch found.count {
            case 0:
                reply(.text, "I don’t know that one yet. Scan the barcode and I’ll check it.", pose: .thinking)
            case 1:
                await show(found[0])
            default:
                let answers = found.prefix(3).map(answer)
                reply(.choices(answers), "Which one?", pose: .thinking)
            }
        } catch {
            failed(error)
        }
    }

    /// When the whole name finds nothing: products that match the most single words.
    private func looseSearch(_ name: String) async throws -> [Product] {
        var counts: [String: (product: Product, hits: Int)] = [:]
        for word in name.split(separator: " ") where word.count >= 4 {
            for product in try await source.search(String(word), region: household.region, store: household.store, limit: 10) {
                counts[product.id, default: (product, 0)].hits += 1
            }
        }
        guard let best = counts.values.map(\.hits).max() else { return [] }
        return counts.values.filter { $0.hits == best }.map(\.product).sorted { $0.name < $1.name }
    }

    private func answer(_ product: Product) -> ProductAnswer {
        ProductAnswer(product: product, verdict: verdictService.check(product, for: household).verdict)
    }

    /// One product card and the reason for the person it matters most to.
    func show(_ product: Product, focus person: String? = nil) async {
        let result = verdictService.check(product, for: household)
        remember(product)
        let line = await reasonLine(result.verdict, product: product, focus: person)
        guard !Task.isCancelled else { return }
        reply(.product(ProductAnswer(product: product, verdict: result.verdict)), line, pose: result.pose)
    }

    /// The worst person's reason (or the focused person's), reworded by the model when it passes the
    /// check. All OK: the person line ("OK for you and Mia.").
    private func reasonLine(_ verdict: HouseholdVerdict, product: Product, focus: String?) async -> String {
        let person = focus.flatMap { name in verdict.people.first { $0.name.lowercased() == name.lowercased() } }
            ?? verdict.decidingPerson
        guard let person else { return verdict.line }
        if person.level == .ok && focus == nil { return verdict.line + "." }
        let explaining = Perf.begin("chat.explain")
        defer { Perf.end(explaining) }
        return await explanationService.explain(person, product: product).text
    }

    private func remember(_ product: Product) {
        if thread.firstProduct == nil {
            thread.firstProduct = product
            // History title: the first product ("Creamy Peanut Butter check").
            thread.title = "\(product.name) check"
        }
        thread.lastProducts.removeAll { $0.id == product.id }
        thread.lastProducts.append(product)
        if thread.lastProducts.count > 3 { thread.lastProducts.removeFirst() }
    }

    // MARK: ingredient

    /// "What is tahini?": the catalog says what it counts as; the household says who avoids it.
    private func explainIngredient(_ phrase: String) {
        guard let (family, term) = Self.family(in: phrase, catalog: catalog) else {
            reply(.text, "I don’t know that ingredient yet. Photo the label and I’ll read it.", pose: .thinking)
            return
        }
        let name = family.name.lowercased()
        let shown = term.prefix(1).uppercased() + term.dropFirst()
        var first: String
        if let isA = family.isA {
            first = "\(shown) is \(isA)."
        } else if term == name {
            first = "\(shown):"
        } else {
            first = "\(shown) counts as \(name)."
        }
        let avoiders = household.people.filter { avoids($0, familyID: family.id) }.map(\.displayName)
        let second: String
        if avoiders.isEmpty {
            second = "Nobody here avoids it."
        } else {
            let verb = avoiders == ["you"] || avoiders.count > 1 ? "avoid" : "avoids"
            second = "\(avoiders.formatted(.list(type: .and)).capitalizedFirst) \(verb) it."
        }
        reply(.text, "\(first) \(second)", pose: .talk)
    }

    /// The catalog family whose term (or name) appears in `phrase`, longest term first.
    static func family(in phrase: String, catalog: Catalog) -> (Catalog.Family, String)? {
        let padded = " " + phrase.lowercased().split { !($0.isLetter || $0.isNumber) }.joined(separator: " ") + " "
        var best: (Catalog.Family, String)?
        for family in catalog.families {
            for term in family.terms + [family.name.lowercased(), family.id] where padded.contains(" \(term) ") {
                if term.count > (best?.1.count ?? 0) { best = (family, term) }
            }
        }
        // "sesame seeds" is the term, but "sesame" is the plain word people use.
        if best == nil, phrase.hasSuffix("s") { return family(in: String(phrase.dropLast()), catalog: catalog) }
        return best
    }

    /// Whether one of `person`'s rules covers this family or a parent of it.
    private func avoids(_ person: Person, familyID: String) -> Bool {
        var chain = [familyID]
        var current = catalog.family(familyID)
        while let parent = current?.parent { chain.append(parent); current = catalog.family(parent) }
        let rules = verdictService.engine.rules(for: person.profile).rules
        return rules.contains { chain.contains($0.familyId) }
    }

    // MARK: other options

    private func otherOptions(query: String?, without: String?) async {
        let anchor = query == nil ? thread.lastProducts.last : nil
        do {
            let candidates: [Product]
            if query != nil, let request = lastRequest,
               let found = await ProductFinder.find(request, source: source) {
                // The model called findProducts; the engine below still decides what fits.
                guard !Task.isCancelled else { return }
                candidates = found.products
            } else if let query {
                candidates = try await source.search(query, region: household.region, store: household.store, limit: 10)
            } else if let anchor {
                candidates = try await source.options(like: anchor, region: household.region, store: household.store, limit: 10)
            } else {
                reply(.text, "Tell me what you’re looking for, like “kettle chips without seed oils”.", pose: .talk)
                return
            }
            guard !Task.isCancelled else { return }
            let left = without.flatMap { Self.family(in: $0, catalog: catalog)?.0 }
            let kept = candidates.filter { product in
                product.id != anchor?.id && product.ingredientsText != nil
                    && !(left.map { Self.contains($0, in: product) } ?? false)
            }
            let checked: [ProductAnswer] = kept.map(answer).filter { $0.verdict.overall <= Level.checkFirst }
            let answers = checked.sorted { $0.verdict.overall < $1.verdict.overall }.prefix(3)
            guard !answers.isEmpty else {
                let who = household.people.count == 1 ? namesLine : household.people.filter { !$0.isOwner }.map(\.displayName).formatted(.list(type: .and))
                reply(.text, "Nothing here fits \(who.isEmpty ? namesLine : who) yet. Want me to check something else?", pose: .thinking)
                return
            }
            let ok = answers.filter { $0.verdict.overall == .ok }.count
            let line = ok == answers.count
                ? "Found \(answers.count). All OK for \(namesLine)."
                : "Found \(answers.count). \(ok) OK for \(namesLine), the rest check first."
            reply(.options(anchor: anchor, Array(answers)), line, pose: .done)
        } catch {
            failed(error)
        }
    }

    /// Whether the product's ingredient list names a term of `family` (for "without seed oils").
    private static func contains(_ family: Catalog.Family, in product: Product) -> Bool {
        let words = (product.ingredientsText ?? "").lowercased().split { !($0.isLetter || $0.isNumber) }
        let text = " " + words.joined(separator: " ") + " "
        return family.terms.contains { text.contains(" \($0) ") }
    }

    // MARK: compare

    private func compareLast() {
        let recent = thread.lastProducts
        guard recent.count >= 2 else {
            reply(.text, "Check two products first, then I compare them.", pose: .talk)
            return
        }
        compare(recent[recent.count - 2], recent[recent.count - 1])
    }

    /// "Compare both" on an options card, or the compare intent.
    func compare(_ a: Product, _ b: Product) {
        reply(.text, "Here they are side by side. Differences first.", pose: .compare)
        actions.compare(a, b)
    }

    // MARK: change allergies

    /// Builds the change card. An inferred change ("Mia reacted to hummus") is a proposal, never a save.
    /// Always a hard filter: an allergen is avoided with its "may contain" lines, even when the person
    /// says intolerance (product owner, 2026-10-27), so `severity` is not used.
    private func proposeChange(person name: String?, item: String, severity: Severity?) {
        let people = household.people
        let person: Person?
        switch name {
        case "you": person = people.first(where: \.isOwner)
        case let name?: person = people.first { $0.name.lowercased() == name.lowercased() }
        case nil: person = people.first(where: { !$0.isOwner }) ?? people.first
        }
        guard let person else {
            let shown = (name ?? "").capitalized
            reply(.familyLink, "\(shown) isn’t in your family yet. Add \(shown) in Family first.", pose: .talk)
            return
        }
        let found = Self.family(in: item, catalog: catalog)?.0
        let label = found?.name.lowercased() ?? item
        let proposal = ChangeProposal(personID: person.id, personName: person.displayName, familyID: found?.id,
                                      label: label, isAllergen: found?.kind == "allergen",
                                      severity: .allergy, currentItems: Self.items(for: person, catalog: catalog))
        let whose = person.isOwner ? "your" : "\(person.name)’s"
        if thread.firstProduct == nil { thread.title = person.isOwner ? "Your allergies" : "\(person.name)’s allergies" }
        let list = proposal.isAllergen ? "allergies" : "list"
        reply(.change(proposal), "Add \(label) to \(whose) \(list)? Nothing changes until you confirm.", pose: .listen)
    }

    func cancelChange(_ messageID: UUID) {
        updateProposal(messageID) { $0.state = .cancelled }
        reply(.text, "No changes made.", pose: .idle)
    }

    /// Saves the change through the host, then re-checks that person's go-tos.
    func confirmChange(_ messageID: UUID) {
        guard let proposal = proposal(messageID), proposal.state == .proposed,
              let index = household.people.firstIndex(where: { $0.id == proposal.personID }) else { return }
        let before = household
        var updated = household
        Self.apply(proposal, to: &updated.people[index].profile)
        do {
            try actions.updateHousehold(updated)
        } catch {
            reply(.text, "I couldn’t save that. Nothing changed.", pose: .thinking)
            return
        }
        household = updated
        beforeLastSave = (before, messageID)
        updateProposal(messageID) { $0.state = .saved }

        let person = updated.people[index]
        toast = ToastMessage(text: Self.savedToast(proposal, mayContain: person.profile.mayContain),
                             actionTitle: "Undo", action: { [weak self] in self?.undo() })
        reply(.text, recheckGoTos(person: person, proposal: proposal), pose: .done)
    }

    /// "Done. I re-checked Mia’s go-tos: none contains sesame." From the go-tos the host passed in.
    private func recheckGoTos(person: Person, proposal: ChangeProposal) -> String {
        let whose = person.isOwner ? "your" : "\(person.name)’s"
        guard !goTos.isEmpty else {
            // shortcut: go-tos live in Family (T12); until the shell passes them, there is nothing to re-check.
            return "Done. From now on, \(proposal.label) is flagged for \(person.displayName)."
        }
        let hits = goTos.filter { product in
            let verdict = verdictService.check(product, for: household).verdict
            guard let pv = verdict.people.first(where: { $0.id == person.id }) else { return false }
            return pv.findings.contains { finding in
                finding.level != .ok && (finding.rule?.familyId == proposal.familyID
                    || finding.ownerFamilyId == proposal.familyID
                    || finding.rule?.familyId == "custom:\(proposal.label.lowercased())")
            }
        }
        if hits.isEmpty { return "Done. I re-checked \(whose) go-tos: none contains \(proposal.label)." }
        let names = hits.map(\.name).formatted(.list(type: .and))
        return "Done. I re-checked \(whose) go-tos: \(names) \(hits.count == 1 ? "contains" : "contain") \(proposal.label)."
    }

    /// Undo from the toast or "undo": puts the household back as it was.
    func undo() {
        guard let (before, messageID) = beforeLastSave else {
            reply(.text, "Nothing to undo yet.", pose: .talk)
            return
        }
        do {
            try actions.updateHousehold(before)
        } catch {
            reply(.text, "I couldn’t undo that. Check Family.", pose: .thinking)
            return
        }
        household = before
        beforeLastSave = nil
        updateProposal(messageID) { $0.state = .undone }
        reply(.text, "Undone. Nothing else changed.", pose: .idle)
    }

    static func apply(_ proposal: ChangeProposal, to profile: inout Profile) {
        guard let familyID = proposal.familyID else {
            if !profile.custom.contains(where: { $0.label.lowercased() == proposal.label.lowercased() }) {
                profile.custom.append(CustomChoice(label: proposal.label, terms: [proposal.label]))
            }
            return
        }
        if proposal.isAllergen {
            if let i = profile.allergens.firstIndex(where: { $0.id == familyID }) {
                profile.allergens[i].severity = .allergy
            } else {
                profile.allergens.append(AllergenChoice(id: familyID, severity: .allergy))
            }
            profile.mayContain = true
        } else if !profile.avoid.contains(where: { $0.id == familyID }) {
            profile.avoid.append(AvoidChoice(id: familyID))
        }
    }

    /// "Saved: Mia avoids sesame, “may contain” too."
    static func savedToast(_ p: ChangeProposal, mayContain: Bool) -> String {
        let who = p.personName == "you" ? "you avoid" : "\(p.personName) avoids"
        guard p.isAllergen, mayContain else { return "Saved: \(who) \(p.label)." }
        return "Saved: \(who) \(p.label), “may contain” too."
    }

    /// What a person avoids, as short words: "peanut, tree nuts".
    static func items(for person: Person, catalog: Catalog) -> [String] {
        let p = person.profile
        let ids = p.allergens.map(\.id) + p.avoid.filter { $0.strength == .avoid }.map(\.id)
        return ids.map { (catalog.family($0)?.name ?? $0).lowercased() } + p.custom.map { $0.label.lowercased() }
            + p.diets.map { (catalog.diets[$0]?.name ?? $0).lowercased() }
    }

    private func proposal(_ id: UUID) -> ChangeProposal? {
        guard let message = thread.messages.first(where: { $0.id == id }), case .change(let p) = message.kind else { return nil }
        return p
    }

    private func updateProposal(_ id: UUID, _ change: (inout ChangeProposal) -> Void) {
        guard let i = thread.messages.firstIndex(where: { $0.id == id }), case .change(var p) = thread.messages[i].kind else { return }
        change(&p)
        thread.messages[i].kind = .change(p)
    }

    // MARK: pivots

    private func handle(_ pivot: ChatIntent.Pivot) async {
        switch pivot {
        case .undo:
            undo()
        case .checkAnother:
            reply(.text, "Point the camera at the next one.", pose: .point)
            actions.openCamera()
        case .firstProduct:
            guard let first = thread.firstProduct else {
                reply(.text, "No product in this chat yet. Check one first.", pose: .talk)
                return
            }
            await show(first)
        case .severity:
            // Always a hard filter: an intolerance is avoided like an allergy.
            reply(.text, "I always avoid it fully, “may contain” too, even for an intolerance.", pose: .listen)
        case .person(let name):
            let inHousehold = household.people.contains { $0.name.lowercased() == name.lowercased() || ($0.isOwner && name.lowercased() == "you") }
            if inHousehold, let last = thread.lastProducts.last {
                await show(last, focus: name)
            } else if inHousehold {
                reply(.text, "Check a product and I’ll tell you about \(name).", pose: .talk)
            } else {
                // Not a person here: maybe a product ("what about hummus?").
                await check(name: name.lowercased())
            }
        }
    }

    // MARK: replies

    private func failed(_ error: any Error) {
        switch ProductSourceError(error) {
        case .cancelled: return
        case .offline: reply(.text, "You’re offline. Products you checked before still work.", pose: .thinking)
        case .notFound: reply(.text, "I don’t know that one yet. Scan the barcode and I’ll check it.", pose: .thinking)
        }
    }

    private func append(_ message: ChatMessage) {
        withAnimation(.easeOut(duration: 0.22)) { thread.messages.append(message) }
    }

    /// Adds the answer to the thread and says its line in the dock.
    private func reply(_ kind: ChatMessage.Kind, _ line: String, pose: MascotState) {
        append(ChatMessage(kind: kind, line: line))
        setLine(line, pose: pose, announce: true)
    }

    private func setLine(_ line: String, pose: MascotState, announce: Bool) {
        withAnimation(.easeInOut(duration: 0.18)) {
            dockLine = line
            self.pose = pose
        }
        if announce { AccessibilityNotification.Announcement(line).post() }
    }

    /// History title: the topic in a few words ("Mia’s allergies"), else the first words.
    static func title(for text: String) -> String {
        let words = text.split(separator: " ").prefix(4).joined(separator: " ")
        return words.count < text.count ? words + "…" : words
    }
}

extension String {
    /// "you and Mia" → "You and Mia".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
