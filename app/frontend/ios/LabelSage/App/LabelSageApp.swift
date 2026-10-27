import SwiftUI
import SwiftData
import TipKit

@main
struct LabelSageApp: App {
    private let container: ModelContainer
    @State private var model: AppModel
    @State private var presence = MascotPresence()
    private let productSource = AppServices.productSource
    private let verdictService = AppServices.verdictService
    private let explanationService = AppServices.explanationService

    init() {
        Perf.beginPending("launch.firstFrame")
        // The mascot's PNGs decode off the main thread while the store opens.
        MascotArt.warm()
        #if DEBUG
        // `-demoHousehold` seeds an in-memory store, so the demo never overwrites a real household.
        let demo = AppModel.wantsDemoHousehold
        #else
        let demo = false
        #endif
        let loading = Perf.begin("launch.container")
        let (container, fellBack) = Self.makeContainer(inMemory: demo)
        #if DEBUG
        // `-resetHousehold` wipes the stored household before it loads, so onboarding shows.
        if AppModel.wantsHouseholdReset && !demo { AppModel.resetHousehold(in: container.mainContext) }
        #endif
        let model = AppModel(context: container.mainContext, storeFellBack: fellBack)
        #if DEBUG
        if AppModel.wantsHouseholdDump { model.dumpStoredHousehold("launch") }
        #endif
        if demo && model.household == nil {
            do { try model.seedDemoHousehold() } catch { Log.data.failure("Demo household failed to seed", error) }
        }
        Perf.end(loading)
        self.container = container
        _model = State(initialValue: model)
        Self.configureTips()
    }

    /// Key set by "Show tips again" in Family; the tips reset at the next launch.
    static let resetTipsKey = "tips.resetOnLaunch"

    /// TipKit for the chat explainers. "Show tips again" can only reset the store before `configure`.
    // shortcut: tips come back at the next launch, not at once; TipKit has no reset after configure.
    private static func configureTips() {
        if UserDefaults.standard.bool(forKey: resetTipsKey) {
            try? Tips.resetDatastore()
            UserDefaults.standard.set(false, forKey: resetTipsKey)
        }
        do { try Tips.configure([.displayFrequency(.immediate)]) } catch { Log.data.failure("TipKit configure failed", error) }
    }

    var body: some Scene {
        WindowGroup {
            content
                .environment(model)
                .environment(presence)
                .environment(\.productSource, productSource)
                .environment(\.verdictService, verdictService)
                .environment(\.explanationService, explanationService)
                .modelContainer(container)
        }
    }

    @ViewBuilder private var content: some View {
        // Launch arguments (debug builds only): `-gallery` the design-system gallery,
        // `-verdictDebug` a fixture product through the engine.
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-gallery") {
            DesignGallery()
        } else if ProcessInfo.processInfo.arguments.contains("-verdictDebug") {
            VerdictDebugView()
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }

    /// SwiftData store on this iPhone only (no CloudKit). Falls back to memory so the app still opens
    /// if the store cannot be created (`fellBack`); the root then shows a storage problem, not onboarding.
    private static func makeContainer(inMemory: Bool) -> (ModelContainer, fellBack: Bool) {
        do {
            return (try SchemaV1.makeContainer(inMemory: inMemory), false)
        } catch {
            Log.data.failure("SwiftData store failed, using memory", error, level: .fault)
            do {
                return (try SchemaV1.makeContainer(inMemory: true), true)
            } catch {
                fatalError("SwiftData cannot create even an in-memory store: \(error)")
            }
        }
    }
}

