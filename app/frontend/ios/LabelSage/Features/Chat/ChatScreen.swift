import SwiftUI
import PhotosUI
import TipKit
import LabelSageCore

/// Chat home (spec 02, board 10): the start screen, the thread, LabelSage in the dock and the composer.
/// Self-contained: the app shell passes the household, the services and what each action does.
///
/// The camera, the product sheet, Compare and Family belong to the host; this screen calls out for
/// them. A product the camera checked comes back through `checked` and lands in the thread.
struct ChatScreen: View {
    /// A product checked outside the chat (the camera). Setting it adds its card to the thread.
    var checked: Product?
    /// Text the host puts in the composer ("Add an allergy for Mia" from Family); cleared once used.
    @Binding var prefill: String?
    /// Chat home's navigation path (Family, a product page), owned by the host's `Router`.
    @Binding var path: [Router.Route]
    /// The page for a pushed route.
    private let destination: (Router.Route) -> AnyView

    @State private var model: ChatModel
    private let household: Household
    private let goTos: [Product]
    private let actions: ChatModel.Actions

    /// The composer's text, read by `ChatComposer` only, so typing does not re-render the thread.
    @State private var draft = ChatDraft()
    @FocusState private var composerFocused: Bool
    @State private var photoItem: PhotosPickerItem?
    @State private var showWelcome = false
    @State private var dockTipShown = false
    @AppStorage("chat.welcomeShown") private var welcomeShown = false
    /// "Start here" in the dock, with the hero ringed (board 10 `first`), until Got it or Skip.
    @AppStorage("chat.startTipDone") private var startTipDone = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let dockTip = DockTip()

    /// - Parameters:
    ///   - household: who the checks are for; the screen re-reads it when it changes.
    ///   - goTos: saved products, re-checked after a confirmed change.
    ///   - checked: a product the camera just checked.
    ///   - onUpdateHousehold: saves a confirmed change (and its Undo); throw when the store fails.
    init(household: Household,
         goTos: [Product] = [],
         checked: Product? = nil,
         prefill: Binding<String?> = .constant(nil),
         path: Binding<[Router.Route]> = .constant([]),
         destination: @escaping (Router.Route) -> AnyView = { _ in AnyView(EmptyView()) },
         source: any ProductSource = AppServices.productSource,
         verdictService: VerdictService = AppServices.verdictService,
         explanationService: ExplanationService = AppServices.explanationService,
         onOpenCamera: @escaping () -> Void,
         onOpenProduct: @escaping (Product) -> Void,
         onCompare: @escaping (Product, Product) -> Void,
         onOpenFamily: @escaping () -> Void,
         onUpdateHousehold: @escaping (Household) throws -> Void) {
        let actions = ChatModel.Actions(openCamera: onOpenCamera, openProduct: onOpenProduct, compare: onCompare,
                                        openFamily: onOpenFamily, updateHousehold: onUpdateHousehold)
        self.household = household
        self.goTos = goTos
        self.checked = checked
        _prefill = prefill
        _path = path
        self.destination = destination
        self.actions = actions
        _model = State(initialValue: ChatModel(household: household, goTos: goTos, source: source,
                                               verdictService: verdictService, explanationService: explanationService,
                                               actions: actions))
    }

    /// For previews: a model already holding a thread.
    init(model: ChatModel) {
        self.household = model.household
        self.goTos = model.goTos
        self.actions = model.actions
        _prefill = .constant(nil)
        _path = .constant([])
        self.destination = { _ in AnyView(EmptyView()) }
        _model = State(initialValue: model)
    }

    /// The first person who isn't the owner ("Mia"), for the coach mark; "you" when alone.
    private var otherName: String {
        model.household.people.first(where: { !$0.isOwner })?.name ?? "you"
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if model.thread.messages.isEmpty {
                    // The tour starts once the welcome sheet is gone.
                    ChatStartView(namesLine: model.namesLine, ringsHero: startTipShown,
                                  onOpenCamera: { model.actions.openCamera() }, onTile: tile)
                } else {
                    thread
                }
            }
            .defaultScrollAnchor(model.thread.messages.isEmpty ? .top : .bottom)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.screenTint.chat.ignoresSafeArea())
            .safeAreaBar(edge: .bottom) { bottomBar }
            // The title names the back button on pushed pages; the bar shows the board's header instead.
            .navigationTitle(model.title)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                // Board 10: avatar, then the title and people line left-aligned, the menu on the title.
                ToolbarItem(placement: .topBarLeading) { avatar }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .principal) { header }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New chat", systemImage: "square.and.pencil") {
                        draft.text = ""
                        model.newChat()
                    }
                    .accessibilityIdentifier("chat.newChat")
                }
            }
            .navigationDestination(for: Router.Route.self, destination: destination)
        }
        .toast($model.toast)
        .sheet(isPresented: $showWelcome) {
            ChatWelcomeSheet(onShowMe: { showWelcome = false }, onSkip: { showWelcome = false; skipTour() })
        }
        .onChange(of: household) { _, new in model.householdChanged(new) }
        .onChange(of: goTos) { _, new in model.goTos = new }
        .onChange(of: checked?.id, initial: true) { _, _ in
            if let checked { model.showChecked(checked) }
        }
        .onChange(of: prefill, initial: true) { _, new in
            guard let new else { return }
            draft.text = new
            composerFocused = true
            prefill = nil
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                model.checkPhoto(image)
            }
        }
        .task {
            if !welcomeShown {
                welcomeShown = true
                showWelcome = true
            }
            for await shouldShow in dockTip.shouldDisplayUpdates {
                dockTipShown = shouldShow
            }
        }
    }

    // MARK: thread

    private var thread: some View {
        // Once per render, not once per row: the message whose line is in the dock.
        let latestLineID = model.thread.messages.last(where: { $0.line != nil })?.id
        // Board 10 thread: 8 pt gaps, a "Today" pill, then his opening line. "Checking…" is in the dock.
        return LazyVStack(alignment: .leading, spacing: Theme.spacing.s) {
            Text("Today")
                .themeText(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.color.muted)
                .padding(.vertical, 3)
                .padding(.horizontal, 10)
                .background(Theme.color.surface.opacity(0.7), in: .capsule)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            olderLine("Point the camera at a barcode, or ask me about any product.")
            ForEach(model.thread.messages) { message in
                messageView(message, isLatest: message.id == latestLineID)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, Theme.spacing.screenGutter)
        .padding(.vertical, Theme.spacing.l)
    }

    @ViewBuilder private func messageView(_ message: ChatMessage, isLatest: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing.s) {
            switch message.kind {
            case .user(let text):
                Bubble(speaker: .user, text: text)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            case .product(let answer):
                ProductResultCard(answer: answer) { model.actions.openProduct(answer.product) }
            case .choices(let answers):
                ChoicesCard(answers: answers) { product in model.showChecked(product) }
            case .options(let anchor, let answers):
                OptionsResultCard(anchor: anchor, answers: answers,
                                  onOpen: { model.actions.openProduct($0) },
                                  onCompare: { model.compare($0, $1) },
                                  onMore: { model.send("Find other options") },
                                  onCheckAnother: { model.actions.openCamera() })
            case .change(let proposal):
                ChangeCard(proposal: proposal,
                           onSeverity: { model.setSeverity($0, for: message.id) },
                           onCancel: { model.cancelChange(message.id) },
                           onConfirm: { model.confirmChange(message.id) })
            case .personPicker:
                PersonPickerCard(people: model.household.people) { person in
                    draft.text = person.isOwner ? "I’m allergic to " : "\(person.name) is allergic to "
                    composerFocused = true
                }
            case .familyLink:
                chatButton("Open Family", systemImage: "person.2") { model.actions.openFamily() }
            case .text:
                EmptyView()
            }
            // Older lines stay in the thread as plain text; the latest is in the dock (D9).
            if let line = message.line, !isLatest {
                olderLine(line)
            }
        }
    }

    /// One of his earlier lines, left in the thread as plain text (board 10: 17 pt ink, 86% wide).
    private func olderLine(_ line: String) -> some View {
        Text(line)
            .themeText(.body)
            .foregroundStyle(Theme.color.ink)
            .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in width * 0.86 }
    }

    // MARK: dock and composer

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.s) {
            dock
            composer
        }
        .padding(.horizontal, Theme.spacing.l)
        .padding(.bottom, Theme.spacing.s)
    }

    /// "Start here" waits for the welcome sheet and shows only on the empty chat.
    private var startTipShown: Bool {
        !startTipDone && !showWelcome && model.thread.messages.isEmpty
    }

    /// What the dock says, in the board's order: working, "Start here", the inline tip, his latest line.
    private var dockLine: (text: String, detail: String?, hasGotIt: Bool) {
        if model.isWorking { return ("Checking the ingredients\u{2026}", "For \(model.namesLine)", false) }
        if startTipShown {
            return ("Start here. Point the camera at a barcode and I\u{2019}ll check it for \(otherName).", nil, true)
        }
        if dockTipShown && model.thread.messages.isEmpty { return (DockTip.line(forName: otherName), nil, true) }
        // Under a guard verdict the bubble carries the disclaimer (board 10 dock `guard`).
        return (model.dockLine, model.pose == .guard ? "Check the package. Not medical advice." : nil, false)
    }

    private var dockPose: MascotState {
        if composerFocused && !draft.isEmpty { return .listen }
        if model.isWorking { return .reading }
        return startTipShown ? .point : model.pose
    }

    private var dock: some View {
        let line = dockLine
        // Board 10: an 84 pt mascot at the leading edge; the bubble fills the rest of the row.
        return HStack(alignment: .bottom, spacing: Theme.spacing.xs) {
            MascotView(state: dockPose, size: Theme.size.mascotChatDock, host: .dock)
            // Keyboard up: the dock collapses to the mascot so the thread stays visible.
            if !composerFocused {
                VStack(alignment: .leading, spacing: Theme.spacing.s) {
                    Bubble(speaker: .mascot, text: line.text, detail: line.detail,
                           isGuard: model.pose == .guard && !model.isWorking)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 3)
                        .contentTransition(.opacity)
                    if line.hasGotIt {
                        Button("Got it", action: gotIt)
                            .themeText(.chip)
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .tint(Theme.color.brandGreenDeep)
                            .frame(minHeight: Theme.size.minTap)
                            .padding(.leading, Theme.spacing.s)
                    }
                }
                .padding(.bottom, Theme.spacing.s)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.18), value: line.text)
        .animation(.easeOut(duration: 0.2), value: composerFocused)
    }

    private var composer: some View {
        ChatComposer(draft: draft, focused: $composerFocused, photoItem: $photoItem,
                     placeholder: model.thread.messages.isEmpty ? "Ask \(Brand.mascot)\u{2026}" : "Message \(Brand.mascot)\u{2026}",
                     isWorking: model.isWorking,
                     onCamera: { model.actions.openCamera() }, onSend: send, onStop: { model.stop() })
    }

    private func send() {
        let message = draft.text
        draft.text = ""
        model.send(message)
    }

    // MARK: header

    /// Board 10: a 40 pt green circle with the owner's initials, outside the bar's glass.
    private var avatar: some View {
        Button(action: model.actions.openFamily) {
            Text(ChatScreen.initials(model.household))
                .themeText(.chip)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Theme.color.brandGreen, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Family and allergies")
    }

    /// The title (with the history menu) over the people line, left-aligned next to the avatar.
    private var header: some View {
        Menu { historyMenu } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Theme.spacing.xxs) {
                    Text(model.title)
                        .themeText(.chatHeaderTitle)
                        .foregroundStyle(Theme.color.ink)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.color.muted)
                        .accessibilityHidden(true)
                }
                Text(model.peopleLine)
                    .themeText(.footnote)
                    .foregroundStyle(Theme.color.muted)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("\(model.title). \(model.peopleLine)")
        .accessibilityHint("Shows your chats")
    }

    /// Board 10 history: New chat first, then the recent chats with their dates; this chat checked.
    @ViewBuilder private var historyMenu: some View {
        Button("New chat", systemImage: "plus") {
            draft.text = ""
            model.newChat()
        }
        Section("Recent") {
            if !model.thread.messages.isEmpty {
                Button { } label: {
                    Label(model.title, systemImage: "checkmark")
                    Text(model.thread.started.formatted(.relative(presentation: .named)))
                }
            }
            if model.history.isEmpty && model.thread.messages.isEmpty {
                Text("No past chats yet")
            }
            ForEach(model.history) { past in
                Button { model.open(past) } label: {
                    Text(past.title ?? "Chat")
                    Text(past.started.formatted(.relative(presentation: .named)))
                }
            }
        }
    }

    /// "Mia: peanut, tree nuts · You: seed oils": each person's top two items.
    static func peopleLine(_ household: Household) -> String {
        let catalog = VerdictService.bundledCatalog
        let people = household.people.filter { !$0.isOwner } + household.people.filter(\.isOwner)
        return people.compactMap { person in
            let items = ChatModel.items(for: person, catalog: catalog).prefix(2)
            guard !items.isEmpty else { return nil }
            return "\(person.isOwner ? "You" : person.name): \(items.joined(separator: ", "))"
        }
        .joined(separator: " · ")
    }

    /// The owner's initials ("AZ").
    static func initials(_ household: Household) -> String {
        let name = household.people.first(where: \.isOwner)?.name ?? household.people.first?.name ?? ""
        return String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }

    // MARK: tiles and tour

    private func tile(_ tile: ChatStartView.Tile) {
        switch tile {
        case .ask:
            draft.text = "Is it OK for \(otherName == "you" ? "me" : otherName): "
            composerFocused = true
        case .options:
            draft.text = "Find other options for "
            composerFocused = true
        case .allergies:
            model.showPersonPicker()
        }
    }

    /// "Got it" on "Start here" hands over to the inline tip; on the inline tip it ends the tour.
    private func gotIt() {
        if startTipShown {
            startTipDone = true
            DockTip.tourDone = true
        } else {
            dockTip.invalidate(reason: .actionPerformed)
        }
    }

    private func skipTour() {
        startTipDone = true
        DockTip.tourDone = true
        dockTip.invalidate(reason: .tipClosed)
    }
}

/// The photo button, the text field and send. It owns the reads of the draft's text, so a keystroke
/// re-renders this row only.
private struct ChatComposer: View {
    @Bindable var draft: ChatDraft
    var focused: FocusState<Bool>.Binding
    @Binding var photoItem: PhotosPickerItem?
    /// "Ask LabelSage…" on the start view, "Message LabelSage…" in a thread (board 10).
    let placeholder: String
    /// While a check runs, the right button is Stop.
    let isWorking: Bool
    let onCamera: () -> Void
    let onSend: () -> Void
    let onStop: () -> Void

    private enum Action { case camera, send, stop }

    var body: some View {
        let empty = draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let action: Action = isWorking ? .stop : (empty ? .camera : .send)
        return GlassEffectContainer(spacing: Theme.spacing.s) {
            HStack(alignment: .bottom, spacing: Theme.spacing.s) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Theme.color.ink)
                        .frame(width: 54, height: 54)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Upload a photo of the ingredients")

                // Board 10: the field is glass (radius 22) in the same container as the two buttons.
                TextField(placeholder, text: $draft.text, axis: .vertical)
                    .themeText(.body)
                    .lineLimit(1...5)
                    .focused(focused)
                    .submitLabel(.send)
                    .onSubmit(onSend)
                    .padding(.horizontal, Theme.spacing.l)
                    .padding(.vertical, 15)
                    .frame(minHeight: 54)
                    .glassEffect(.regular, in: .rect(cornerRadius: Theme.radius.searchField, style: .continuous))
                    .accessibilityLabel("Message \(Brand.mascot)")
                    .accessibilityIdentifier("chat.composer")

                // The camera until you type (glass); Send and Stop are solid green (board 10 `solid`).
                Button {
                    switch action {
                    case .camera: onCamera()
                    case .send: onSend()
                    case .stop: onStop()
                    }
                } label: {
                    Image(systemName: action == .camera ? "barcode.viewfinder" : action == .send ? "arrow.up" : "stop.fill")
                        .font(.system(size: action == .stop ? 14 : 20, weight: .semibold))
                        .foregroundStyle(action == .camera ? Theme.color.ink : Color.white)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(action == .camera ? Theme.color.surface : Theme.color.brandGreen)
                .accessibilityLabel(action == .camera ? "Open the camera" : action == .send ? "Send" : "Stop")
                .accessibilityIdentifier(action == .camera ? "chat.camera" : action == .send ? "chat.send" : "chat.stop")
            }
        }
    }
}

/// The composer's text. The screen reads only `isEmpty` (for the dock's pose), which changes at the
/// first and the last character, not on every keystroke.
@Observable
final class ChatDraft {
    var text = "" {
        didSet { if isEmpty != text.isEmpty { isEmpty = text.isEmpty } }
    }
    private(set) var isEmpty = true
}

/// The empty chat: title, who LabelSage checks for, the "Check a product" hero and three tiles.
struct ChatStartView: View {
    enum Tile: CaseIterable { case ask, options, allergies }

    let namesLine: String
    /// "Start here" is on: the hero gets the board's 3 pt ink ring.
    var ringsHero = false
    let onOpenCamera: () -> Void
    let onTile: (Tile) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Board 10 start: 12 pt gaps; title 32, line 15 muted; the grid gap is 10.
        VStack(alignment: .leading, spacing: Theme.spacing.m) {
            Text("What do you need today?")
                .themeText(.chatTitle)
                .foregroundStyle(Theme.color.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Theme.spacing.xs)
            Text("I check the ingredients for \(namesLine).")
                .themeText(.callout)
                .foregroundStyle(Theme.color.muted)
            hero
            let columns = Array(repeating: GridItem(.flexible(), spacing: 10),
                                count: dynamicTypeSize.isAccessibilitySize ? 1 : 3)
            LazyVGrid(columns: columns, spacing: 10) {
                tile("ask", "Ask about a product", .ask)
                tile("options", "Find other options", .options)
                tile("family", "Change allergies", .allergies)
            }
        }
        .padding(.horizontal, Theme.spacing.screenGutter)
        .padding(.top, Theme.spacing.s)
        .padding(.bottom, Theme.spacing.xl)
    }

    private var hero: some View {
        // Board 10 hero: padding 18, a 56 pt icon centered with the text, the button 14 below.
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                IconView(key: "check", size: 56, decorative: true)
                VStack(alignment: .leading, spacing: Theme.spacing.xxs) {
                    Text("Check a product")
                        .themeText(.sectionTitle)
                        .foregroundStyle(Theme.color.ink)
                    Text("Scan the barcode or photo the ingredients")
                        .themeText(.callout)
                        .foregroundStyle(Theme.color.muted)
                }
            }
            PrimaryButton(title: "Open the camera", systemImage: "barcode.viewfinder", showsChevron: false,
                          action: onOpenCamera)
                .accessibilityIdentifier("chat.openCamera")
        }
        .padding(Theme.spacing.cardPaddingH)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCardBackground(cornerRadius: Theme.radius.card, isSelected: false)
        .overlay {
            if ringsHero {
                RoundedRectangle(cornerRadius: Theme.radius.card, style: .continuous)
                    .stroke(Theme.color.ink, lineWidth: 3)
                    .accessibilityHidden(true)
            }
        }
    }

    private func tile(_ icon: String, _ title: String, _ tile: Tile) -> some View {
        Button { onTile(tile) } label: {
            // Board 10 `tileStyle`: icon 40, label 15/600, min height 112, radius 22, padding 14 by 8.
            VStack(spacing: Theme.spacing.s) {
                IconView(key: icon, size: 40, decorative: true)
                Text(title)
                    .themeText(.chip)
                    .foregroundStyle(Theme.color.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, Theme.spacing.s)
            .frame(maxWidth: .infinity, minHeight: 112)
            .themeCardBackground(cornerRadius: Theme.radius.tile, isSelected: false)
        }
        .buttonStyle(.pressable)
    }
}
