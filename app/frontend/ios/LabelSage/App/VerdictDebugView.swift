#if DEBUG
import SwiftUI
import SwiftData
import LabelSageCore

/// Debug only (`-verdictDebug`): pick a fixture product, look it up through `ProductSource`, run it
/// through the engine for the household, and show the line with `VerdictBanner`. The T6 "done" check.
struct VerdictDebugView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.productSource) private var source
    @Environment(\.verdictService) private var verdicts
    @Environment(\.explanationService) private var explanations

    @State private var products: [Product] = (try? SampleData.products()) ?? []
    @State private var selectedId: String?
    @State private var result: VerdictResult?
    @State private var reason = ""
    @State private var failure: ProductSourceError?

    /// Fails closed like the app: an unreadable stored household shows nothing.
    private var household: Household? { model.needsProfileRecheck ? nil : model.household ?? (try? SampleData.household()) }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Product", selection: $selectedId) {
                    Text("Pick one").tag(String?.none)
                    ForEach(products) { Text($0.name).tag(Optional($0.id)) }
                }
                Section {
                    if let result {
                        VerdictBanner(level: result.verdict.overall, title: result.verdict.line, reason: reason)
                        LabeledContent("Pose", value: result.pose.rawValue)
                    } else if let failure {
                        Text(failure == .offline ? "Offline" : "Not found")
                    } else if selectedId != nil {
                        ProgressView()
                    }
                }
            }
            .navigationTitle("Verdict debug")
        }
        .task(id: selectedId) { await run() }
        .onAppear { if selectedId == nil { selectedId = products.first?.id } }
    }

    private func run() async {
        result = nil
        failure = nil
        guard let barcode = products.first(where: { $0.id == selectedId })?.barcode, let household else { return }
        do throws(ProductSourceError) {
            let product = try await model.lookup(barcode: barcode, region: household.region, in: source)
            guard !Task.isCancelled else { return }
            let checked = verdicts.check(product, for: household)
            result = checked
            let worst = checked.verdict.people.max { $0.level < $1.level }
            reason = worst?.reason ?? ""
            if let worst {
                let explanation = await explanations.explain(worst, product: product)
                guard !Task.isCancelled else { return }
                reason = explanation.text
            }
        } catch {
            guard error != .cancelled, !Task.isCancelled else { return }
            failure = error
        }
    }
}

#Preview("Verdict debug - demo household") {
    VerdictDebugView()
        .environment(AppModel.preview)
        .environment(\.productSource, FixtureProductSource(delayMilliseconds: 0...0))
}

extension AppModel {
    /// An in-memory model seeded with the demo household, for previews.
    static let preview: AppModel = {
        do {
            let model = AppModel(context: try SchemaV1.makeContainer(inMemory: true).mainContext)
            try model.seedDemoHousehold()
            return model
        } catch {
            fatalError("Preview store failed: \(error)")  // previews only; a broken preview should say why
        }
    }()
}
#endif
