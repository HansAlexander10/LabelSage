import SwiftUI
import LabelSageCore

/// The app shell (T13, flows board `70-flows-ai-first.png`). Root: a storage problem, else Family to
/// re-enter unreadable profiles, else onboarding when there is no household, else chat home (D1).
///
/// Chat home owns the navigation: Family and product pages push on its stack (`Router.path`); the
/// product sheet, Compare with and Compare are `Router` sheets; the camera is a full-screen cover
/// whose own product sheet belongs to `ScanScreen`.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.productSource) private var productSource
    @Environment(\.verdictService) private var verdictService
    @Environment(\.explanationService) private var explanationService

    /// The scan state for the open camera; a new one each time the camera opens.
    @State private var scan: ScanModel?
    /// The last product the camera checked; chat home adds its card to the thread.
    @State private var checked: Product?
    /// Text for the chat composer (Family's "Add an allergy for Mia", "Type a name").
    @State private var prefill: String?
    /// A sheet to show once the camera is gone (Compare from the camera's product sheet).
    @State private var sheetAfterCamera: Router.Sheet?
    /// Open the camera once the sheet over chat home is gone (a cover can't present over a closing sheet).
    @State private var cameraAfterSheet = false
    /// "Add someone you shop for" in Family: the add-a-person questions as a full-screen cover.
    @State private var addingPerson = false
    /// `-screen onboarding`: onboarding even with a household.
    @State private var forceOnboarding = false
    @State private var saveFailed = false

    var body: some View {
        Group {
            if model.storageProblem {
                StorageProblemView { model.load() }
            } else if model.needsProfileRecheck {
                // Never checks products until the profiles are entered again: no go-tos, no chat.
                NavigationStack { family(Household(people: [])) }
            } else if let household = model.household, !forceOnboarding {
                home(household)
            } else {
                onboarding(showsLaunch: !forceOnboarding)
            }
        }
        .fullScreenCover(isPresented: $addingPerson) { addPersonFlow }
        .alert("Couldn’t save", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your answers are still here. Try again.")
        }
        .task { applyLaunchScreen() }
        .onAppear { Perf.endPending("launch.firstFrame") }
    }

    // MARK: Onboarding

    private func onboarding(showsLaunch: Bool) -> some View {
        OnboardingFlow(showsLaunch: showsLaunch,
                       tryItProduct: try? SampleData.products().first,
                       loadStores: { try await productSource.stores(near: $0) },
                       onFinish: finishOnboarding)
    }

    /// "Add someone you shop for": one person with their own profile, appended to the saved
    /// household. Without a readable household (profile re-check) it is the first-run onboarding.
    @ViewBuilder private var addPersonFlow: some View {
        if let household = model.household {
            OnboardingFlow(model: OnboardingModel(addingTo: household.people), showsLaunch: false,
                           tryItProduct: try? SampleData.products().first,
                           onSavePerson: { person in
                               var changed = household
                               changed.people.append(person)
                               do {
                                   try model.save(changed)
                                   addingPerson = false
                               } catch {
                                   saveFailed = true
                               }
                           },
                           onCancel: { addingPerson = false },
                           onFinish: { _ in })
        } else {
            onboarding(showsLaunch: false)
        }
    }

    /// Saves the household (first run: the owner, region and store), then chat home shows.
    private func finishOnboarding(_ household: Household) {
        do {
            try model.save(household)
            addingPerson = false
            forceOnboarding = false
            #if DEBUG
            // `-onboardingScriptThenFamily`: after the scripted save, chat home for a moment, then Family.
            if ProcessInfo.processInfo.arguments.contains("-onboardingScriptThenFamily") {
                Task {
                    try? await Task.sleep(for: .seconds(8))
                    model.router.push(.family)
                }
            }
            #endif
        } catch {
            saveFailed = true
        }
    }

    // MARK: Chat home

    private func home(_ household: Household) -> some View {
        @Bindable var router = model.router
        return ChatScreen(household: household,
                          goTos: model.goTos,
                          checked: checked,
                          prefill: $prefill,
                          path: $router.path,
                          destination: { AnyView(page($0, household)) },
                          source: productSource,
                          verdictService: verdictService,
                          explanationService: explanationService,
                          onOpenCamera: openCamera,
                          onOpenProduct: openProductSheet,
                          onCompare: { left, right in
                              model.remember([left, right])
                              router.present(.compare(leftId: left.id, rightId: right.id))
                          },
                          onOpenFamily: { router.push(.family) },
                          onUpdateHousehold: { try model.save($0) })
            .sheet(item: $router.sheet, onDismiss: {
                if cameraAfterSheet {
                    cameraAfterSheet = false
                    model.router.openCamera()
                }
            }) { layer in
                ModalLayerView(layer: layer) { sheetContent($0, household) }
            }
            .fullScreenCover(item: $router.cover, onDismiss: {
                scan = nil
                if let sheet = sheetAfterCamera {
                    sheetAfterCamera = nil
                    model.router.present(sheet)
                }
            }) { _ in
                if let scan { cameraScreen(scan) }
            }
    }

    /// Pages pushed on chat home's stack.
    private func page(_ route: Router.Route, _ household: Household) -> some View {
        pageContent(route, household)
            .onAppear { Perf.endPending("sheet.open") }
    }

    @ViewBuilder private func pageContent(_ route: Router.Route, _ household: Household) -> some View {
        switch route {
        case .family:
            family(household)
        case .product(let id):
            if let product = model.product(id: id) {
                // A memo hit after the first check: RootView's body runs on every app-state change.
                ProductPage(product: product, verdict: verdictService.check(product, for: household).verdict,
                            household: household, presentation: .page, isGoTo: model.isGoTo(product),
                            actions: productActions(product))
            } else {
                missingProduct
            }
        }
    }

    private func family(_ household: Household) -> some View {
        let recheck = model.needsProfileRecheck
        return FamilyScreen(household: household,
                            onSave: { changed in
                                // A re-check starts empty: saving nobody would pass for a profile.
                                if recheck && changed.people.isEmpty { throw CocoaError(.validationMissingMandatoryProperty) }
                                try model.save(changed)
                            },
                            goTos: recheck ? [] : model.goTos,
                            stores: { try await productSource.stores(near: $0) },
                            verdictService: verdictService,
                            needsProfileRecheck: recheck,
                            onAddPerson: { addingPerson = true },
                            onEditPerson: { person in
                                prefill = "Add an allergy for \(person.isOwner ? "me" : person.name)"
                                model.router.path.removeAll()
                            },
                            onOpenProduct: { product in
                                model.remember([product])
                                model.router.push(.product(id: product.id))
                            },
                            onShowTipsAgain: {
                                UserDefaults.standard.set(true, forKey: LabelSageApp.resetTipsKey)
                                UserDefaults.standard.set(false, forKey: "chat.tourDone")
                                UserDefaults.standard.set(false, forKey: "chat.startTipDone")
                            })
    }

    // MARK: Sheets

    private func openProductSheet(_ product: Product) {
        model.remember([product])
        model.router.present(.product(id: product.id))
    }

    @ViewBuilder private func sheetContent(_ sheet: Router.Sheet, _ household: Household) -> some View {
        switch sheet {
        case .product(let id):
            if let product = model.product(id: id) {
                // A memo hit after the first check (see `page`).
                ProductPage(product: product, verdict: verdictService.check(product, for: household).verdict,
                            household: household, presentation: .sheet, isGoTo: model.isGoTo(product),
                            actions: productActions(product))
            } else {
                missingProduct
            }
        case .compareWith(let baseId):
            if let base = model.product(id: baseId) {
                CompareWithScreen(base: base, source: productSource, verdictService: verdictService,
                                  household: household, region: household.region, recent: checkedBefore,
                                  onPick: { right in
                                      model.remember([right])
                                      // Same sheet, new content: Compare with becomes Compare.
                                      model.router.replaceTop(with: .compare(leftId: base.id, rightId: right.id))
                                  },
                                  onClose: { model.router.dismissTop() })
            } else {
                missingProduct
            }
        case .compare(let leftId, let rightId):
            if let left = model.product(id: leftId), let right = model.product(id: rightId) {
                CompareScreen(left: left, right: right, household: household, verdictService: verdictService,
                              presentation: .sheet, isGoTo: model.isGoTo,
                              onSaveGoTo: { model.setGoTo($0, true) },
                              onUndoSave: { model.setGoTo($0, false) },
                              onOpen: openProductSheet,
                              onClose: { model.router.dismissTop() })
            } else {
                missingProduct
            }
        }
    }

    /// The product page's actions from chat home (a sheet, or a page pushed from Family).
    private func productActions(_ product: Product) -> ProductPage.Actions {
        var actions = ProductPage.Actions()
        actions.compare = { option in
            model.remember([option])
            model.router.present(.compare(leftId: product.id, rightId: option.id))
        }
        actions.seeAllOptions = { model.router.present(.compareWith(baseId: product.id)) }
        actions.setGoTo = { model.setGoTo(product, $0) }
        actions.viewGoTos = {
            model.router.sheet = nil
            model.router.path = [.family]
        }
        actions.ask = { question in
            model.router.sheet = nil
            model.router.path.removeAll()
            prefill = question ?? ""
        }
        actions.checkAnother = openCamera
        actions.photoIngredients = openCamera
        return actions
    }

    private var missingProduct: some View {
        ContentUnavailableView("Product not found", systemImage: "questionmark.square.dashed",
                               description: Text("Check it again with the camera."))
    }

    // MARK: Camera

    private func openCamera() {
        guard let household = model.household else { return }
        scan = ScanModel(source: productSource, verdictService: verdictService, household: household,
                         region: household.region, checkedBefore: checkedBefore)
        if model.router.sheet != nil {
            cameraAfterSheet = true
            model.router.sheet = nil
        } else {
            model.router.openCamera()
        }
    }

    /// The offline list and Compare with's recent products: products looked up this session.
    // shortcut: session only; the SwiftData `CheckRecord` history is not written yet.
    private var checkedBefore: [Product] {
        model.products.values.sorted { $0.name < $1.name }
    }

    private func cameraScreen(_ scan: ScanModel) -> some View {
        ScanScreen(model: scan,
                   onClose: { model.router.closeCamera() },
                   onTypeName: {
                       model.router.closeCamera()
                       prefill = ""
                   },
                   onResult: { product in
                       model.remember([product])
                       checked = product
                   },
                   onAsk: { _ in
                       model.router.closeCamera()
                       prefill = ""
                   },
                   onReport: { report in
                       // shortcut: logged only; reports are not stored on the iPhone yet.
                       Log.lookup.notice("Report: \(report.reason.rawValue, privacy: .public) barcode \(report.barcode ?? "none", privacy: .private(mask: .hash))")
                   },
                   isGoTo: model.isGoTo,
                   onSetGoTo: model.setGoTo,
                   onCompare: { product, option in
                       model.remember([product, option])
                       sheetAfterCamera = .compare(leftId: product.id, rightId: option.id)
                       model.router.closeCamera()
                   },
                   onCompareWith: { product in
                       sheetAfterCamera = .compareWith(baseId: product.id)
                       model.router.closeCamera()
                   })
    }

    // MARK: Launch arguments

    /// `-screen <name>` opens one screen for screenshots (debug builds): onboarding, chat, scan,
    /// product, compareWith, compare, family. Products are the board's fixtures.
    private func applyLaunchScreen() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        // `-onboardingScript addPerson`: Family, then "Add someone you shop for", played by the script.
        // Waits for chat home's first-launch sheet and tip to settle, which would block the cover.
        if OnboardingScript.requested == "addPerson", model.household != nil {
            UserDefaults.standard.set(true, forKey: "chat.welcomeShown")
            UserDefaults.standard.set(true, forKey: "chat.startTipDone")
            Task {
                try? await Task.sleep(for: .seconds(3))
                model.router.push(.family)
                try? await Task.sleep(for: .seconds(1.5))
                addingPerson = true
            }
        }
        guard let index = args.firstIndex(of: "-screen"), args.indices.contains(index + 1) else { return }
        let products = (try? SampleData.products()) ?? []
        model.remember(products)
        let chips = products.first { $0.barcode == "0000000000017" }
        let oliveOilChips = products.first { $0.barcode == "0000000000024" }
        switch args[index + 1] {
        case "onboarding": forceOnboarding = true
        case "chat": break
        case "scan": openCamera()
        case "product": if let chips { openProductSheet(chips) }
        case "compareWith": if let chips { model.router.present(.compareWith(baseId: chips.id)) }
        case "compare":
            if let chips, let oliveOilChips {
                model.router.present(.compare(leftId: chips.id, rightId: oliveOilChips.id))
            }
        case "family": model.router.push(.family)
        default: Log.data.notice("Unknown -screen \(args[index + 1], privacy: .public)")
        }
        #endif
    }
}

/// One `Router` sheet and the sheet it presents, recursively (Compare over the product sheet).
private struct ModalLayerView<Content: View>: View {
    @Bindable var layer: Router.ModalLayer
    let content: (Router.Sheet) -> Content

    var body: some View {
        content(layer.sheet)
            .onAppear { Perf.endPending("sheet.open") }
            .sheet(item: $layer.child) { child in
                ModalLayerView(layer: child, content: content)
            }
    }
}

/// The store could not be opened or read. Not a fresh install: onboarding here could save over a
/// household that is still on the iPhone, so nothing is checked until it reads again.
private struct StorageProblemView: View {
    let onTryAgain: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Can’t open your saved profiles", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("\(Brand.app) won’t check products until it can read them. Your data stays on this iPhone.")
        } actions: {
            Button("Try again", action: onTryAgain)
                .buttonStyle(.glass)
        }
        .background(Theme.screenTint.chat.ignoresSafeArea())
    }
}

#Preview("Storage problem") {
    StorageProblemView {}
}
