import SwiftUI
import LabelSageCore

/// Step 15, required (D6): "Use my location", or a city or ZIP search with up to four suggestions.
/// Only the ZIP code is kept.
struct RegionStep: View {
    @Bindable var model: OnboardingModel
    /// Finds the region from the location; nil when it is denied or fails.
    let locate: () async -> Region?

    @State private var query = ""
    @State private var picked = false
    @State private var locating = false
    @State private var usedLocation = false
    @FocusState private var searchFocused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var showsSuggestions: Bool { trimmed.count >= 2 && !picked }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.s) {
            locationCard
            Text("Or search a city or ZIP code")
                .themeText(.footnote).fontWeight(.semibold)
                .foregroundStyle(Theme.color.muted)
                .padding(.horizontal, Theme.spacing.xxs)
                .padding(.top, Theme.spacing.s)
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.color.muted)
                    TextField("City or ZIP code", text: $query)
                        .themeText(.body)
                        .foregroundStyle(Theme.color.ink)
                        .textContentType(.postalCode)
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                        .onChange(of: query) { _, new in
                            // Picking a place writes its line into the field; only typing reopens the list.
                            if let region = model.region, new == Self.regionLine(region) { return }
                            picked = false
                        }
                        .accessibilityLabel("City or ZIP code")
                    if !query.isEmpty {
                        Button { query = ""; picked = false } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.color.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear")
                    }
                }
                .padding(.horizontal, Theme.spacing.m)
                .frame(minHeight: 52)
                .background(RoundedRectangle(cornerRadius: Theme.radius.field, style: .continuous).fill(Theme.color.ink.opacity(0.06)))
                .padding(Theme.spacing.s)
                if showsSuggestions { suggestions }
            }
            .background(RoundedRectangle(cornerRadius: Theme.radius.tile, style: .continuous).fill(Theme.color.surface))
            if let region = model.region, !showsSuggestions, !usedLocation {
                HStack(spacing: Theme.spacing.m) {
                    Image(systemName: "storefront")
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Self.regionLine(region)).fontWeight(.semibold)
                        Text("Stores near \(region.city ?? "this ZIP code")")
                    }
                    .themeText(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(Theme.color.ink)
                .padding(.horizontal, 14).padding(.vertical, Theme.spacing.m)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.color.ink.opacity(0.06)))
            }
            OnboardingFootnote(systemImage: "lock.shield", text: "Only your ZIP code is kept, on this iPhone.")
                .padding(.top, Theme.spacing.xxs)
        }
    }

    /// "Austin, TX 78701", or "ZIP 12345" without a city.
    static func regionLine(_ region: Region) -> String {
        region.city.map { "\($0) \(region.zip)" } ?? "ZIP \(region.zip)"
    }

    // Custom card, not `LocationButton`: the board's card layout can't be drawn with it, and the
    // location lookup itself is the app shell's (`locate`). See open-questions Q-T7-3.
    private var locationCard: some View {
        Button {
            Task {
                locating = true
                let found = await locate()
                locating = false
                if let found {
                    model.region = found
                    usedLocation = true
                    query = ""
                } else {
                    searchFocused = true
                }
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "location")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.color.surface)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: Theme.radius.field, style: .continuous).fill(Theme.color.ink))
                VStack(alignment: .leading, spacing: 0) {
                    Text(usedLocation ? model.region.map(Self.regionLine) ?? "Use my location" : "Use my location")
                        .themeText(.bodyStrong)
                    Text(usedLocation ? "Found from your location" : "Fastest. Fills in your ZIP code")
                        .themeText(.footnote).foregroundStyle(Theme.color.muted)
                }
                .foregroundStyle(Theme.color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                if locating {
                    ProgressView()
                } else if usedLocation {
                    Image(systemName: "checkmark.circle").font(.system(size: 22)).foregroundStyle(Theme.color.ink)
                }
            }
            .padding(14)
            .frame(minHeight: 68)
            .themeCardBackground(cornerRadius: Theme.radius.tile, isSelected: usedLocation)
        }
        .buttonStyle(.pressable)
        .disabled(locating)
    }

    private var suggestions: some View {
        let places = OnboardingCatalog.places(matching: trimmed)
        let typedZip = OnboardingModel.isValidZip(trimmed) && !places.contains { $0.zip == trimmed }
        return VStack(spacing: 0) {
            ForEach(Array(places.enumerated()), id: \.element.id) { i, place in
                if i > 0 { Divider().overlay(Theme.color.hairline).padding(.leading, 46) }
                suggestionRow(title: place.cityLine, detail: "\(place.state) · \(place.area)", zip: place.zip) { pick(place.region) }
            }
            if typedZip {
                suggestionRow(title: "ZIP \(trimmed)", detail: "United States", zip: trimmed) { pick(Region(zip: trimmed)) }
            } else if places.isEmpty {
                Text("No US city or ZIP code matches “\(trimmed)”.")
                    .themeText(.callout)
                    .foregroundStyle(Theme.color.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.spacing.l)
                    .padding(.bottom, Theme.spacing.l)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Matching places")
    }

    private func suggestionRow(title: String, detail: String, zip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.spacing.m) {
                Image(systemName: "location").font(.system(size: 18))
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).themeText(.bodyStrong)
                    Text(detail).themeText(.caption).foregroundStyle(Theme.color.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(zip).themeText(.callout).monospacedDigit().foregroundStyle(Theme.color.muted)
            }
            .foregroundStyle(Theme.color.ink)
            .padding(.horizontal, Theme.spacing.l)
            .frame(minHeight: 60)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
    }

    private func pick(_ region: Region) {
        model.region = region
        usedLocation = false
        query = Self.regionLine(region)
        picked = true
        searchFocused = false
    }
}

/// Step 16, optional (D6): one store near the ZIP. "Set up later" is the Skip button.
struct StoreStep: View {
    @Bindable var model: OnboardingModel
    let loadStores: (Region) async throws -> [Store]

    @State private var stores: [Store]?

    var body: some View {
        VStack(spacing: Theme.spacing.m) {
            if let stores {
                if stores.isEmpty {
                    Text("No stores found near \(model.region?.zip ?? ""). Try another ZIP code.")
                        .themeText(.body)
                        .foregroundStyle(Theme.color.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.spacing.l)
                        .background(RoundedRectangle(cornerRadius: Theme.radius.tile, style: .continuous).fill(Theme.color.surface))
                } else {
                    ForEach(stores) { store in
                        OptionCard(iconKey: "local", title: store.name, detail: Self.distance(store), mode: .single,
                                   isOn: model.store?.id == store.id) { model.store = store }
                    }
                    OnboardingFootnote(systemImage: "info.circle", text: "Stores near your ZIP code. You can set this up later.")
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task(id: model.region?.zip) {
            guard let region = model.region else { stores = []; return }
            stores = (try? await loadStores(region)) ?? []
        }
    }

    /// "1.2 mi". The board adds the neighborhood ("· Downtown"); `Store` has none (Q-T7-4).
    static func distance(_ store: Store) -> String? {
        store.distanceMiles.map { $0.formatted(.number.precision(.fractionLength(1))) + " mi" }
    }
}

#Preview("Region") {
    let model = OnboardingModel()
    model.show(.region)
    return OnboardingFlow(model: model, showsLaunch: false) { _ in }
}

#Preview("Store") {
    let model = OnboardingModel()
    model.region = Region(zip: "78701", city: "Austin, TX")
    model.store = OnboardingCatalog.demoStores.first
    model.show(.store)
    return OnboardingFlow(model: model, showsLaunch: false) { _ in }
}

#Preview("Store, none nearby") {
    let model = OnboardingModel()
    model.region = Region(zip: "99999")
    model.show(.store)
    return OnboardingFlow(model: model, showsLaunch: false, loadStores: { _ in [] }) { _ in }
}
