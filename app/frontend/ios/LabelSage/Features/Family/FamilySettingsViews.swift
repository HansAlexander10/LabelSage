import SwiftUI
import LabelSageCore

/// Settings › Region: the ZIP code (and an optional city). Saving reloads the store list; when the
/// current store is not in it, the store step opens for the new region (spec 06 "Region").
// shortcut: ZIP and city fields only; the onboarding region step (location button, search) replaces
// this when onboarding lands (spec 06 "Region and Store push the onboarding region/store steps").
struct FamilyRegionView: View {
    let region: Region?
    let store: Store?
    let stores: (Region) async throws -> [Store]
    /// Saves the region with the store to keep (nil when the old one is not near). False on failure.
    let onSave: (Region, Store?) -> Bool
    let onPickStore: (Store) -> Bool

    @State private var zip: String
    @State private var city: String
    @State private var isSaving = false
    @State private var failed = false
    @State private var needsStoreFor: Region?
    @Environment(\.dismiss) private var dismiss

    init(region: Region?, store: Store?, stores: @escaping (Region) async throws -> [Store],
         onSave: @escaping (Region, Store?) -> Bool, onPickStore: @escaping (Store) -> Bool) {
        self.region = region
        self.store = store
        self.stores = stores
        self.onSave = onSave
        self.onPickStore = onPickStore
        _zip = State(initialValue: region?.zip ?? "")
        _city = State(initialValue: region?.city ?? "")
    }

    private var canSave: Bool { FamilyLogic.isZip(zip) && !isSaving }

    var body: some View {
        Form {
            Section {
                TextField("ZIP code", text: $zip)
                    .keyboardType(.numberPad)
                    .textContentType(.postalCode)
                TextField("City (optional)", text: $city)
                    .textContentType(.addressCityAndState)
            } footer: {
                Text(failed ? "Couldn\u{2019}t load stores near \(zip). Check your connection and try again."
                            : "Only the ZIP code is kept, on this iPhone. It picks the stores for other options.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.screenTint.family)
        .navigationTitle("Region")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { Task { await save() } }.disabled(!canSave)
                }
            }
        }
        .navigationDestination(isPresented: Binding(get: { needsStoreFor != nil }, set: { if !$0 { needsStoreFor = nil } })) {
            if let needsStoreFor {
                FamilyStoreView(region: needsStoreFor, selectedId: nil, stores: stores, onPick: onPickStore)
            }
        }
    }

    private func save() async {
        let trimmedCity = city.trimmingCharacters(in: .whitespaces)
        let new = Region(zip: zip, city: trimmedCity.isEmpty ? nil : trimmedCity)
        isSaving = true
        failed = false
        defer { isSaving = false }
        do {
            let near = try await stores(new)
            let kept = near.first { $0.id == store?.id }
            guard onSave(new, kept) else { return }
            if kept == nil, !near.isEmpty { needsStoreFor = new } else { dismiss() }
        } catch {
            Log.data.failure("Store list failed", error)
            failed = true
        }
    }
}

/// Settings › Store: the stores near the region, one picked (spec 06 "Store").
struct FamilyStoreView: View {
    let region: Region
    let selectedId: String?
    let stores: (Region) async throws -> [Store]
    /// Saves the pick. False on failure.
    let onPick: (Store) -> Bool

    private enum Load {
        case loading
        case loaded([Store])
        case failed
    }

    @State private var load = Load.loading
    @State private var attempt = 0
    @State private var selection: String?
    @Environment(\.dismiss) private var dismiss

    init(region: Region, selectedId: String?, stores: @escaping (Region) async throws -> [Store],
         onPick: @escaping (Store) -> Bool) {
        self.region = region
        self.selectedId = selectedId
        self.stores = stores
        self.onPick = onPick
        _selection = State(initialValue: selectedId)
    }

    var body: some View {
        Group {
            switch load {
            case .loading:
                ProgressView("Finding stores near \(region.zip)\u{2026}")
            case .failed:
                ContentUnavailableView {
                    Label("Couldn\u{2019}t load stores", systemImage: "wifi.slash")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button("Try again") { attempt += 1 }
                }
            case .loaded(let list) where list.isEmpty:
                ContentUnavailableView("No stores near \(region.zip) yet", systemImage: "storefront")
            case .loaded(let list):
                List {
                    Picker("Stores near \(region.zip)", selection: $selection) {
                        ForEach(list) { store in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.name)
                                if let miles = store.distanceMiles {
                                    Text("\(miles.formatted(.number.precision(.fractionLength(1)))) mi")
                                        .themeText(.footnote)
                                        .foregroundStyle(Theme.color.mutedGreen)
                                }
                            }
                            .tag(Optional(store.id))
                        }
                    }
                    .pickerStyle(.inline)
                }
                .scrollContentBackground(.hidden)
                .onChange(of: selection) { old, new in
                    guard new != selectedId, let store = list.first(where: { $0.id == new }) else { return }
                    if onPick(store) { dismiss() } else { selection = old }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.screenTint.family)
        .navigationTitle("Store")
        .task(id: attempt) {
            load = .loading
            do {
                load = .loaded(try await stores(region))
            } catch {
                Log.data.failure("Store list failed", error)
                load = .failed
            }
        }
    }
}
