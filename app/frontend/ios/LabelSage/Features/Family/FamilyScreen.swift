import SwiftUI
import LabelSageCore

/// "Preferences & settings" (was "Family"; product owner, 2026-10-27): everything LabelSage knows
/// about the household in one scroll (spec 06, board 50). Person cards, add a person, macros,
/// go-tos (checked again on every open) and settings. Until a second person exists, a card at the
/// top asks to "Add someone you shop for"; it starts the add-a-person questions.
/// A `List` (`.insetGrouped`) so item rows get native `.swipeActions` (native-components.md).
/// Push it inside the app's `NavigationStack`; the system back button reads "‹ Chat".
struct FamilyScreen: View {
    /// The saved household. Region and store come from it.
    let household: Household
    /// Saves a changed household (`AppModel.save`). A throw keeps the old state and shows a toast.
    let onSave: (Household) throws -> Void
    var goTos: [Product] = []
    /// Stores near a region, for the Store setting and after a region change.
    let stores: (Region) async throws -> [Store]
    var verdictService: VerdictService = AppServices.verdictService
    /// `AppModel.needsProfileRecheck`: the stored profiles were unreadable; ask for them again.
    var needsProfileRecheck = false
    /// Runs the add-a-person questions (name, start from, the per-person steps) and returns here.
    var onAddPerson: () -> Void = {}
    /// "Add an allergy by telling LabelSage": the shell opens the chat with "Add an allergy for Mia".
    var onEditPerson: (Person) -> Void = { _ in }
    var onOpenProduct: (Product) -> Void = { _ in }
    var onShowTipsAgain: () -> Void = {}

    @State private var draft: Household
    /// Bumped whenever `draft` is replaced: the go-to re-check keys on it instead of comparing the
    /// whole household on every body run.
    @State private var draftRevision = 0
    /// The protein value while the stepper is in use; saved when the person stops.
    @State private var editingProtein: Int?
    /// Switched-off items by person id: kept on the card, left out of what the engine sees.
    // shortcut: session only, because `Profile` has no "off" field (Q-T12-1); persist once the model has one.
    @State private var parked: [String: [ParkedChoice]] = [:]
    @State private var openPersonId: String?
    @State private var pendingRemoval: Removal?
    @State private var verdicts: [String: HouseholdVerdict]?
    @State private var toast: ToastMessage?
    @State private var firstVisit: Bool
    @State private var language = "en"
    @AppStorage("family.seen") private var seenBefore = false
    // shortcut: device preferences, nothing reads them yet; move into the data layer when a screen uses units.
    @AppStorage("settings.units") private var units = "us"
    // shortcut: placeholder switch, no HealthKit request (no entitlement in project.yml yet).
    @AppStorage("settings.appleHealth") private var appleHealth = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(household: Household, onSave: @escaping (Household) throws -> Void, goTos: [Product] = [],
         stores: @escaping (Region) async throws -> [Store], verdictService: VerdictService = AppServices.verdictService,
         needsProfileRecheck: Bool = false, openPersonId: String? = nil,
         onAddPerson: @escaping () -> Void = {}, onEditPerson: @escaping (Person) -> Void = { _ in },
         onOpenProduct: @escaping (Product) -> Void = { _ in }, onShowTipsAgain: @escaping () -> Void = {}) {
        self.household = household
        self.onSave = onSave
        self.goTos = goTos
        self.stores = stores
        self.verdictService = verdictService
        self.needsProfileRecheck = needsProfileRecheck
        self.onAddPerson = onAddPerson
        self.onEditPerson = onEditPerson
        self.onOpenProduct = onOpenProduct
        self.onShowTipsAgain = onShowTipsAgain
        _draft = State(initialValue: household)
        _openPersonId = State(initialValue: openPersonId)
        _firstVisit = State(initialValue: !UserDefaults.standard.bool(forKey: "family.seen"))
    }

    private var catalog: Catalog { verdictService.engine.catalog }
    private var people: [Person] { draft.people.sorted { $0.isOwner && !$1.isOwner } }
    private var owner: Person? { draft.people.first(where: \.isOwner) }

    var body: some View {
        List {
            titleSection
            if needsProfileRecheck { recheckBanner }
            if showsAddPrompt { addPromptSection }
            ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                personSection(person, index: index)
            }
            if !showsAddPrompt { addPersonSection }
            if owner != nil { macrosSection }
            goTosSection
            settingsSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.screenTint.family)
        .tint(Theme.color.brandGreenDeep)
        .navigationTitle(Self.title)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            // The board's 34 pt title sits in the content next to the mascot; the bar stays empty.
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
        }
        .toast($toast)
        .alert(pendingRemoval?.question ?? "", isPresented: Binding(get: { pendingRemoval != nil },
                                                                     set: { if !$0 { pendingRemoval = nil } }),
               presenting: pendingRemoval) { removal in
            Button("Remove", role: .destructive) { remove(removal) }
            Button("Keep", role: .cancel) {}
        }
        .onChange(of: household) { _, new in
            draft = new
            draftRevision += 1
        }
        .task(id: RecheckKey(revision: draftRevision, ids: goTos.map(\.id))) { recheckGoTos() }
        .onAppear { seenBefore = true }
    }

    // MARK: Title

    static let title = "Preferences & settings"

    /// The "Add someone you shop for" card stays until the household has a second person.
    private var showsAddPrompt: Bool { !needsProfileRecheck && draft.people.count < 2 }

    private var addPromptSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.spacing.m) {
                HStack(alignment: .top, spacing: Theme.spacing.m) {
                    IconView(key: "family", size: 40, decorative: true)
                    VStack(alignment: .leading, spacing: Theme.spacing.xxs) {
                        Text("Add someone you shop for").themeText(.cardTitle).accessibilityAddTraits(.isHeader)
                        Text("Each person gets their own allergies and diet. Start from yours and change what differs.")
                            .themeText(.callout)
                            .foregroundStyle(Theme.color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                PrimaryButton(title: "Add someone", systemImage: "person.badge.plus", showsChevron: false, action: onAddPerson)
                    .accessibilityIdentifier("family.addSomeone")
            }
            .foregroundStyle(Theme.color.ink)
            .padding(.vertical, Theme.spacing.s)
        }
        .listRowBackground(Theme.color.surface)
    }

    private var titleSection: some View {
        Section {
            HStack(alignment: .top, spacing: Theme.spacing.m) {
                VStack(alignment: .leading, spacing: Theme.spacing.xxs) {
                    Text(Self.title).themeText(.screenTitle).accessibilityAddTraits(.isHeader)
                    Text(FamilyLogic.headerLine(draft.people)).themeText(.callout).foregroundStyle(Theme.color.mutedGreen)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                MascotView(state: mascotPose, size: 56, host: .page)
            }
            .foregroundStyle(Theme.color.ink)
            .listRowInsets(EdgeInsets(top: 0, leading: Theme.spacing.xxs, bottom: 0, trailing: Theme.spacing.xxs))
            .listRowBackground(Color.clear)
        }
    }

    /// Spec 06: `sit` the first time, then `idle`; the prototype listens while a card is open.
    private var mascotPose: MascotState {
        openPersonId != nil ? .listen : (firstVisit ? .sit : .idle)
    }

    private var recheckBanner: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.spacing.s) {
                Label("I couldn\u{2019}t read your family\u{2019}s allergies.", systemImage: "exclamationmark.triangle.fill")
                    .themeText(.bodyStrong)
                Text("Add each person again before your next check.").themeText(.callout)
                // Explicit colors: a tinted `.borderedProminent` took the ink foreground set below
                // and drew ink on ink (contrast audit 2026-10-27).
                Button(action: onAddPerson) {
                    Text("Add a person")
                        .themeText(.callout).fontWeight(.semibold)
                        .foregroundStyle(Theme.color.surface)
                        .padding(.horizontal, Theme.spacing.l)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(Theme.color.ink))
                        .contentShape(.capsule)
                }
                .buttonStyle(.pressable)
            }
            .foregroundStyle(Theme.color.ink)
            .padding(.vertical, Theme.spacing.xs)
            .listRowBackground(Theme.verdict.checkFirst.wash)
        }
    }

    // MARK: People

    @ViewBuilder
    private func personSection(_ person: Person, index: Int) -> some View {
        let items = FamilyLogic.items(for: person.profile, parked: parked[person.id] ?? [], catalog: catalog)
        Section {
            if openPersonId == person.id {
                openHeader(person, index: index, items: items)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) { removePersonAction(person) }
                if items.isEmpty {
                    Text("Nothing to avoid yet. Add allergies any time.")
                        .themeText(.callout).foregroundStyle(Theme.color.mutedGreen)
                }
                ForEach(items) { item in
                    itemRow(item, person: person)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { pendingRemoval = .item(item, person) } label: { Label("Remove", systemImage: "trash") }
                                .tint(Theme.verdict.notFor.color)
                        }
                }
                addByChatRow(person)
            } else {
                PersonCard(name: person.name, isOwner: person.isOwner, index: index,
                           items: .constant(personItems(items)), isOpen: openBinding(person))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) { removePersonAction(person) }
            }
        }
        .listRowBackground(Theme.color.surface)
    }

    @ViewBuilder
    private func removePersonAction(_ person: Person) -> some View {
        // Spec 06: the owner can't be removed.
        if !person.isOwner {
            Button { pendingRemoval = .person(person) } label: { Label("Remove", systemImage: "trash") }
                .tint(Theme.verdict.notFor.color)
        }
    }

    private func openBinding(_ person: Person) -> Binding<Bool> {
        Binding(get: { openPersonId == person.id }, set: { open in
            withAnimation(Theme.motion.reduceMotionAware(Theme.motion.groupCardOpen, reduceMotion: reduceMotion)) {
                openPersonId = open ? person.id : nil
            }
        })
    }

    private func personItems(_ items: [FamilyItem]) -> [PersonItem] {
        items.map { PersonItem(id: $0.id, iconKey: $0.iconKey, title: $0.title, detail: $0.detail, kind: $0.kind, isOn: $0.isOn) }
    }

    /// The open card's header: same avatar, name and summary as `PersonCard`, with Done.
    private func openHeader(_ person: Person, index: Int, items: [FamilyItem]) -> some View {
        let tints = Theme.screenTint.avatarTints
        let title = PersonSummary.title(name: person.name, isOwner: person.isOwner)
        let summary = PersonSummary.line(personItems(items))
        return HStack(spacing: Theme.spacing.m) {
            Text(PersonSummary.initial(person.name))
                .font(.custom("Outfit", fixedSize: 20).weight(.bold))
                .frame(width: 48, height: 48)
                .background(Circle().fill(tints[index % tints.count]))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).themeText(.personName).lineLimit(1)
                Text(summary).themeText(.caption).foregroundStyle(Theme.color.mutedGreen)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title). \(summary).")
            Button("Done") { openBinding(person).wrappedValue = false }
                .themeText(.callout)
                .fontWeight(.semibold)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(Theme.color.ink)
                .accessibilityLabel("Done editing \(person.name)")
        }
        .foregroundStyle(Theme.color.ink)
        .padding(.vertical, Theme.spacing.xxs)
    }

    private func itemRow(_ item: FamilyItem, person: Person) -> some View {
        // Spec 06, AX sizes: badges move under the item name.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.spacing.xs))
            : AnyLayout(HStackLayout(spacing: Theme.spacing.s))
        return HStack(spacing: Theme.spacing.s) {
            IconView(key: item.iconKey, size: 32, decorative: true)
            layout {
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title).themeText(.bodyStrong)
                    if !item.detail.isEmpty {
                        Text(item.detail).themeText(.footnote).foregroundStyle(Theme.color.mutedGreen)
                    }
                }
                .strikethrough(!item.isOn)
                .frame(maxWidth: .infinity, alignment: .leading)
                badge(item, person: person).opacity(item.isOn ? 1 : 0.4)
            }
            Toggle(item.title, isOn: Binding(get: { item.isOn }, set: { setOn($0, item: item, person: person) }))
                .labelsHidden()
                .tint(Theme.color.brandGreen)
        }
        .foregroundStyle(Theme.color.ink)
        .frame(minHeight: 60)
    }

    @ViewBuilder
    private func badge(_ item: FamilyItem, person: Person) -> some View {
        if item.choice.isFlippable {
            KindBadge(ruleName: item.title, kind: Binding(get: { item.kind }, set: { _ in flip(item, person: person) }))
        } else {
            // Allergies and medical diets are always Avoid: the badge is static (spec 06 accessibility).
            // shortcut: KindBadge still draws its chevron for Avoid; add a static variant in DesignSystem later.
            KindBadge(ruleName: item.title, kind: .constant(item.kind))
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.kind == .avoid ? "\(item.title): always avoided" : "\(item.title): \(item.kind.title)")
        }
    }

    private func addByChatRow(_ person: Person) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing.xs) {
            Button { onEditPerson(person) } label: {
                Label("Add an allergy by telling \(Brand.mascot)", systemImage: "plus")
                    .themeText(.bodyStrong)
                    .foregroundStyle(Theme.color.brandGreenDeep)
                    .frame(maxWidth: .infinity, minHeight: Theme.size.minTap, alignment: .leading)
            }
            .buttonStyle(.pressable)
            Text("Avoid hides it. Prefer not only shows it lower. Tap to switch.")
                .themeText(.footnote)
                .foregroundStyle(Theme.color.mutedGreen)
        }
        .padding(.bottom, Theme.spacing.xs)
    }

    private var addPersonSection: some View {
        Section {
            // Custom: a dashed card has no system equivalent (native-components.md, "Add a person").
            Button(action: onAddPerson) {
                Label("Add a person", systemImage: "plus")
                    .themeText(.bodyStrong)
                    .foregroundStyle(Theme.color.brandGreenDeep)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radius.card, style: .continuous)
                            .strokeBorder(Theme.color.ink.opacity(0.18), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    )
                    .contentShape(.rect)
            }
            .buttonStyle(.pressable)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } footer: {
            footnote("Every product is checked for everyone here.")
        }
    }

    // MARK: Macros

    private var macrosSection: some View {
        Section {
            Stepper(value: proteinBinding, in: 5...60, step: 5) {
                HStack(spacing: Theme.spacing.m) {
                    IconView(key: "macros", size: 28, decorative: true)
                    LabeledContent("Protein per meal") {
                        Text("\(proteinBinding.wrappedValue) g").monospacedDigit().foregroundStyle(Theme.color.ink)
                    }
                }
                .themeText(.body)
                .foregroundStyle(Theme.color.ink)
            } onEditingChanged: { editing in
                if !editing { saveProtein() }
            }
            // VoiceOver's adjust does not report editing: save once the value rests.
            .task(id: editingProtein) {
                guard editingProtein != nil else { return }
                try? await Task.sleep(for: .milliseconds(800))
                if !Task.isCancelled { saveProtein() }
            }
        } header: {
            SectionHeader("Macros and calories").textCase(nil)
        }
    }

    /// The owner's protein target. Information only; it never changes a flag.
    private var proteinBinding: Binding<Int> {
        Binding(get: { editingProtein ?? owner?.profile.goals?.proteinG ?? 25 }, set: { editingProtein = $0 })
    }

    /// Saves the stepper's value once, when the person stops tapping (not on every step).
    private func saveProtein() {
        guard let value = editingProtein else { return }
        editingProtein = nil
        guard let index = draft.people.firstIndex(where: \.isOwner),
              value != draft.people[index].profile.goals?.proteinG ?? 25 else { return }
        var new = draft
        var goals = new.people[index].profile.goals ?? Goals()
        goals.proteinG = value
        new.people[index].profile.goals = goals
        commit(new)
    }

    // MARK: Go-tos

    private var goTosSection: some View {
        Section {
            if goTos.isEmpty {
                Text("No go-tos yet. Save a product you buy often and I\u{2019}ll check it again every time.")
                    .themeText(.callout).foregroundStyle(Theme.color.mutedGreen)
            }
            ForEach(goTos) { product in
                goToRow(product).listRowInsets(EdgeInsets())
            }
        } header: {
            HStack(spacing: Theme.spacing.s) {
                IconView(key: "gotos", size: 24, decorative: true)
                SectionHeader("Go-tos")
                if !goTos.isEmpty {
                    Text(goTos.count == 1 ? "1 product" : "\(goTos.count) products")
                        .themeText(.callout).foregroundStyle(Theme.color.mutedGreen)
                }
            }
            .textCase(nil)
        } footer: {
            footnote("Checked again every time, in case the ingredients changed.")
        }
    }

    @ViewBuilder
    private func goToRow(_ product: Product) -> some View {
        if let verdict = verdicts?[product.id] {
            let note = FamilyLogic.goToNote(verdict, catalog: catalog)
            ProductRow(product: product, level: verdict.overall, names: verdict.people.map(\.name),
                       notes: note.map { [ProductRow.Note(level: $0.level, text: $0.text)] } ?? [],
                       style: .compact) { onOpenProduct(product) }
        } else if needsProfileRecheck || draft.people.isEmpty {
            // No verdict runs on a guess: without readable profiles every go-to is Can't confirm.
            ProductRow(product: product, level: .cantConfirm, style: .compact) { onOpenProduct(product) }
        } else {
            HStack(spacing: Theme.spacing.s) {
                ProgressView().controlSize(.mini)
                Text(product.name).themeText(.body).lineLimit(1)
            }
            .padding(Theme.spacing.m)
            .accessibilityLabel("Checking \(product.name)")
        }
    }

    private struct RecheckKey: Equatable {
        var revision: Int
        var ids: [String]
    }

    /// Spec 06: go-tos are checked again on every open and after every change.
    private func recheckGoTos() {
        guard !needsProfileRecheck, !draft.people.isEmpty else { verdicts = nil; return }
        var out: [String: HouseholdVerdict] = [:]
        for product in goTos { out[product.id] = verdictService.check(product, for: draft).verdict }
        verdicts = out
    }

    // MARK: Settings

    private var settingsSection: some View {
        Section {
            NavigationLink {
                FamilyRegionView(region: draft.region, store: draft.store, stores: stores, onSave: saveRegion, onPickStore: pickStore)
            } label: {
                settingLabel("Region", systemImage: "location", value: FamilyLogic.regionLine(draft.region))
            }
            NavigationLink {
                if let region = draft.region {
                    FamilyStoreView(region: region, selectedId: draft.store?.id, stores: stores, onPick: pickStore)
                } else {
                    FamilyRegionView(region: nil, store: nil, stores: stores, onSave: saveRegion, onPickStore: pickStore)
                }
            } label: {
                settingLabel("Store", systemImage: "storefront", value: draft.store?.name)
            }
            // shortcut: English (US) only for the MVP (voice-and-strings.md); more languages come with the String Catalog.
            Picker(selection: $language) {
                Text("English").tag("en")
            } label: {
                Label("Language", systemImage: "globe")
            }
            .pickerStyle(.navigationLink)
            Picker(selection: $units) {
                Text("US").tag("us")
                Text("Metric").tag("metric")
            } label: {
                Label("Units", systemImage: "tag")
            }
            .pickerStyle(.navigationLink)
            Toggle(isOn: $appleHealth) {
                Label("Apple Health", systemImage: "heart.text.square")
            }
            .tint(Theme.color.brandGreen)
            Button {
                onShowTipsAgain()
                toast = ToastMessage(text: "Tips will show again.")
            } label: {
                Label("Show tips again", systemImage: "lightbulb")
            }
        } header: {
            SectionHeader("Settings").textCase(nil)
        } footer: {
            Label("Runs on your iPhone. Your data stays here.", systemImage: "lock.shield")
                .themeText(.footnote)
                .foregroundStyle(Theme.color.mutedGreen)
        }
        .themeText(.body)
        .foregroundStyle(Theme.color.ink)
    }

    private func settingLabel(_ title: String, systemImage: String, value: String?) -> some View {
        LabeledContent {
            Text(value ?? "Not set").lineLimit(1)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text).themeText(.footnote).foregroundStyle(Theme.color.mutedGreen)
    }

    // MARK: Changes

    /// Saves through `onSave`; on failure keeps the old state and says so.
    @discardableResult
    private func commit(_ new: Household) -> Bool {
        do {
            try onSave(new)
            draft = new
            draftRevision += 1
            return true
        } catch {
            toast = ToastMessage(text: "Couldn\u{2019}t save that. Try again.")
            return false
        }
    }

    private func setOn(_ on: Bool, item: FamilyItem, person: Person) {
        guard let index = draft.people.firstIndex(where: { $0.id == person.id }) else { return }
        var new = draft
        if on {
            guard let stored = parked[person.id]?.first(where: { $0.choice.key == item.id }) else { return }
            FamilyLogic.insert(stored.choice, into: &new.people[index].profile, at: stored.position)
            if commit(new) { parked[person.id]?.removeAll { $0.choice.key == item.id } }
        } else {
            guard let stored = FamilyLogic.remove(item.id, from: &new.people[index].profile) else { return }
            if commit(new) { parked[person.id, default: []].append(stored) }
        }
    }

    private func flip(_ item: FamilyItem, person: Person) {
        if !item.isOn, let i = parked[person.id]?.firstIndex(where: { $0.choice.key == item.id }) {
            parked[person.id]?[i].choice = item.choice.flipped
            return
        }
        guard let index = draft.people.firstIndex(where: { $0.id == person.id }) else { return }
        var new = draft
        FamilyLogic.flip(item.id, in: &new.people[index].profile)
        commit(new)
    }

    private func remove(_ removal: Removal) {
        switch removal {
        case .item(let item, let person):
            guard item.isOn else { parked[person.id]?.removeAll { $0.choice.key == item.id }; return }
            guard let index = draft.people.firstIndex(where: { $0.id == person.id }) else { return }
            var new = draft
            FamilyLogic.remove(item.id, from: &new.people[index].profile)
            commit(new)
        case .person(let person):
            guard !person.isOwner else { return }
            var new = draft
            new.people.removeAll { $0.id == person.id }
            if commit(new) {
                parked[person.id] = nil
                if openPersonId == person.id { openPersonId = nil }
            }
        }
    }

    private func saveRegion(_ region: Region, store: Store?) -> Bool {
        var new = draft
        new.region = region
        new.store = store
        return commit(new)
    }

    private func pickStore(_ store: Store) -> Bool {
        var new = draft
        new.store = store
        return commit(new)
    }

    private enum Removal {
        case item(FamilyItem, Person)
        case person(Person)

        var question: String {
            switch self {
            case .item(let item, let person): FamilyLogic.removeQuestion(item, person: person)
            case .person(let person): "Remove \(person.name) from your family?"
            }
        }
    }
}
