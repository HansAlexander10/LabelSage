#if DEBUG
import SwiftUI
import LabelSageCore

/// Sample inputs for the Family previews: the demo household (Alex and Mia) and the board's go-tos.
enum FamilyPreviewData {
    static var household: Household { (try? SampleData.household()) ?? Household(people: []) }

    /// Board 50: kettle chips, Greek yogurt, peanut butter.
    static var goTos: [Product] {
        let all = (try? SampleData.products()) ?? []
        return ["0000000000024", "0000000000079", "0000000000062"].compactMap { code in all.first { $0.barcode == code } }
    }

    static func stores(_ region: Region) async throws -> [Store] {
        [Store(id: "wfm", name: "Whole Foods Market", distanceMiles: 1.2),
         Store(id: "heb", name: "H-E-B", distanceMiles: 2.4),
         Store(id: "tj", name: "Trader Joe\u{2019}s", distanceMiles: 3.1)]
    }

    static func screen(_ household: Household = household, goTos: [Product] = goTos, open: String? = nil,
                       recheck: Bool = false) -> some View {
        NavigationStack {
            FamilyScreen(household: household, onSave: { _ in }, goTos: goTos, stores: stores,
                         needsProfileRecheck: recheck, openPersonId: open)
        }
    }
}

#Preview("Family - Mia open (board 50)") { FamilyPreviewData.screen(open: "mia") }

#Preview("Family - all closed") { FamilyPreviewData.screen() }

#Preview("Family - one person, no go-tos") {
    var one = FamilyPreviewData.household
    one.people.removeAll { !$0.isOwner }
    return FamilyPreviewData.screen(one, goTos: [])
}

#Preview("Family - person with nothing set") {
    var household = FamilyPreviewData.household
    household.people.append(Person(id: "sam", name: "Sam"))
    return FamilyPreviewData.screen(household, open: "sam")
}

#Preview("Family - needs re-check") {
    FamilyPreviewData.screen(Household(people: []), recheck: true)
}

#Preview("Family - save fails") {
    NavigationStack {
        FamilyScreen(household: FamilyPreviewData.household,
                     onSave: { _ in throw CocoaError(.fileWriteUnknown) },
                     goTos: FamilyPreviewData.goTos, stores: FamilyPreviewData.stores, openPersonId: "you")
    }
}

#Preview("Family - AX5") {
    FamilyPreviewData.screen(open: "mia").environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Store picker") {
    NavigationStack {
        FamilyStoreView(region: Region(zip: "78701", city: "Austin, TX"), selectedId: "wfm",
                        stores: FamilyPreviewData.stores, onPick: { _ in true })
    }
}

#Preview("Region") {
    NavigationStack {
        FamilyRegionView(region: Region(zip: "78701", city: "Austin, TX"), store: nil,
                         stores: FamilyPreviewData.stores, onSave: { _, _ in true }, onPickStore: { _ in true })
    }
}
#endif
