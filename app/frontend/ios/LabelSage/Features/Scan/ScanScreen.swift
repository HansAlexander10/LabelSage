import SwiftUI
import AVFoundation
import PhotosUI
import LabelSageCore

/// "Check a product" (spec 03, boards 20, 60, 61): the full-screen camera. Point at a barcode, or
/// switch to Ingredients and photograph the list; the result opens as a sheet over the camera.
/// Present it with `.fullScreenCover`. It owns no navigation: every exit is a closure.
struct ScanScreen: View {
    @State private var model: ScanModel
    /// Close (✕).
    let onClose: () -> Void
    /// "Type a name": to the chat with the composer focused.
    let onTypeName: () -> Void
    /// Every product shown (sheet or "no ingredients" card): the result also lands in the chat
    /// thread and the local history.
    let onResult: (Product) -> Void
    /// "Ask LabelSage" on the result: to the chat with this product.
    let onAsk: (Product) -> Void
    /// "Report it": the caller stores the report on the iPhone (D4, no backend).
    let onReport: (ScanReport) -> Void
    /// Whether a product is in the go-tos, for the heart on the product sheet.
    let isGoTo: (Product) -> Bool
    /// The heart on the product sheet: saved (`true`) or removed.
    let onSetGoTo: (Product, Bool) -> Void
    /// "Compare" on Try instead: this product and the option. The host closes the camera for it.
    var onCompare: (Product, Product) -> Void = { _, _ in }
    /// "See all" next to Other options: Compare with, starting from this product.
    var onCompareWith: (Product) -> Void = { _ in }

    @State private var handle = ScannerHandle()
    /// The scan frame on screen: live for the dim layer, settled for the scanner.
    @State private var frame = ScanFrameRect()
    @State private var showEnterCode = false
    @State private var enteredCode = ""
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showReport = false
    /// Camera access confirmed and the scanner can run. `ScannerView` is created only after this,
    /// so the first permission prompt never leaves a scanner that did not start.
    @State private var cameraReady = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - checkedBefore: the local history for the offline list (T13 passes the SwiftData checks).
    init(source: any ProductSource, verdictService: VerdictService, household: Household, region: Region?,
         checkedBefore: [Product] = [],
         onClose: @escaping () -> Void, onTypeName: @escaping () -> Void,
         onResult: @escaping (Product) -> Void = { _ in }, onAsk: @escaping (Product) -> Void = { _ in },
         onReport: @escaping (ScanReport) -> Void = { _ in }, isGoTo: @escaping (Product) -> Bool = { _ in false },
         onSetGoTo: @escaping (Product, Bool) -> Void = { _, _ in },
         onCompare: @escaping (Product, Product) -> Void = { _, _ in },
         onCompareWith: @escaping (Product) -> Void = { _ in }) {
        self.init(model: ScanModel(source: source, verdictService: verdictService, household: household,
                                   region: region, checkedBefore: checkedBefore),
                  onClose: onClose, onTypeName: onTypeName, onResult: onResult, onAsk: onAsk, onReport: onReport,
                  isGoTo: isGoTo, onSetGoTo: onSetGoTo, onCompare: onCompare, onCompareWith: onCompareWith)
    }

    /// With a prepared model (previews and tests).
    init(model: ScanModel, onClose: @escaping () -> Void = {}, onTypeName: @escaping () -> Void = {},
         onResult: @escaping (Product) -> Void = { _ in }, onAsk: @escaping (Product) -> Void = { _ in },
         onReport: @escaping (ScanReport) -> Void = { _ in }, isGoTo: @escaping (Product) -> Bool = { _ in false },
         onSetGoTo: @escaping (Product, Bool) -> Void = { _, _ in },
         onCompare: @escaping (Product, Product) -> Void = { _, _ in },
         onCompareWith: @escaping (Product) -> Void = { _ in }) {
        _model = State(initialValue: model)
        self.onClose = onClose
        self.onTypeName = onTypeName
        self.onResult = onResult
        self.onAsk = onAsk
        self.onReport = onReport
        self.isGoTo = isGoTo
        self.onSetGoTo = onSetGoTo
        self.onCompare = onCompare
        self.onCompareWith = onCompareWith
    }

    var body: some View {
        Group {
            switch model.phase {
            case .cameraOff:
                ScanCameraOffView(onClose: onClose, onOpenSettings: openSettings, onTypeName: onTypeName)
            case .offline:
                ScanOfflineView(checkedBefore: model.checkedBeforeResults(), onBack: model.checkAnother,
                                onTryAgain: model.tryAgain, onOpen: model.show)
            default:
                camera
            }
        }
        .task { await checkCameraAccess() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await checkCameraAccess() } }
        }
        .onAppear {
            AccessibilityNotification.Announcement("Check a product. Point the camera at a barcode.").post()
        }
        .onDisappear { model.stop() }
        .sensoryFeedback(.success, trigger: model.foundCount)
        .onChange(of: model.phase) { _, phase in resultShown(phase) }
        // The sheet lives here, not in `Router.cameraSheet`: its lifetime is the scan phase, and
        // "Check another" and Close both reset the phase, which dismisses it.
        .sheet(item: productBinding) { result in
            ProductPage(product: result.product, verdict: result.verdict.verdict, household: model.household,
                        presentation: .sheet, photo: .hidden, isGoTo: isGoTo(result.product),
                        actions: productActions(result.product))
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .environment(\.colorScheme, .light)
                .onAppear { Perf.endPending("scan.toSheet") }
        }
        .alert("Enter code", isPresented: $showEnterCode) {
            TextField("Barcode digits", text: $enteredCode)
                .keyboardType(.numberPad)
            Button("Check") { model.codeEntered(enteredCode); enteredCode = "" }
                .disabled(!ScanModel.isValidEnteredCode(enteredCode.filter(\.isNumber)))
            Button("Cancel", role: .cancel) { enteredCode = "" }
        } message: {
            Text("The 12 or 13 digits under the barcode.")
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            readPhoto { try await item.loadTransferable(type: Data.self).flatMap(UIImage.init(data:)) }
        }
        .confirmationDialog("What’s wrong?", isPresented: $showReport, titleVisibility: .visible) {
            ForEach(ScanReportReason.allCases) { reason in
                Button(reason.title) { report(reason) }
            }
        }
    }

    // MARK: Camera layout

    private var camera: some View {
        ZStack {
            feed.ignoresSafeArea()
            DimLayer(frame: frame, cornerRadius: Self.frameRadius)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                topBar
                if case .product = model.phase {
                    checkAnotherPill.padding(.top, Theme.spacing.l)
                }
                Text(hint)
                    .themeText(Theme.TypeStyle(size: 17, weight: .medium, relativeTo: .body))
                    .multilineTextAlignment(.center)
                    .padding(.top, Theme.spacing.xxl)
                    .padding(.horizontal, Theme.spacing.screenGutter)
                    .frame(minHeight: 60)
                    .accessibilityAddTraits(.isHeader)
                scanFrame
                    .padding(.top, Theme.spacing.xl)
                if model.phase == .idle { subhint.padding(.top, Theme.spacing.s) }
                Spacer(minLength: Theme.spacing.l)
                bottom
            }
            .foregroundStyle(.white)
            // The phase animation stays on the controls and cards, off the live feed and dim layer.
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.26), value: model.phase)
        }
        .background(Theme.screenTint.scan)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var feed: some View {
        #if targetEnvironment(simulator)
        // The simulator has no camera: a stand-in feed (prototype `Scan.dc.html` mock feed).
        LinearGradient(colors: [Theme.color.inkSecondary, Theme.color.ink, .black],
                       startPoint: .top, endPoint: .bottom)
        #else
        if cameraReady {
            GeometryReader { geo in
                let origin = geo.frame(in: .global).origin
                ScannerView(mode: model.mode,
                            regionOfInterest: frame.settled == .zero ? nil : frame.settled.offsetBy(dx: -origin.x, dy: -origin.y),
                            handle: handle, onBarcode: model.barcodeRead)
                    .id(model.mode)
            }
        } else {
            Color.black
        }
        #endif
    }

    private var topBar: some View {
        GlassEffectContainer(spacing: Theme.spacing.m) {
            HStack {
                CameraGlassButton(systemImage: "xmark", label: "Close", action: onClose)
                Spacer()
                Text("Check a product")
                    .themeText(Theme.TypeStyle(size: 17, weight: .semibold, relativeTo: .headline))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if handle.hasTorch {
                    CameraGlassButton(systemImage: handle.torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                                      label: handle.torchOn ? "Torch off" : "Torch on", action: handle.toggleTorch)
                } else {
                    Color.clear.frame(width: Theme.size.minTap, height: Theme.size.minTap)
                }
            }
        }
        .padding(.horizontal, Theme.spacing.l)
        .padding(.top, Theme.spacing.s)
    }

    private var checkAnotherPill: some View {
        Button(action: model.checkAnother) {
            Label("Check another", systemImage: "barcode.viewfinder")
                .themeText(Theme.TypeStyle(size: 15, weight: .medium, relativeTo: .subheadline))
                .frame(minHeight: 40)
        }
        .buttonStyle(.glass(.clear))
    }

    private var hint: String {
        switch model.phase {
        case .idle, .unreadable:
            model.mode == .barcode ? "Point at the barcode" : "No barcode? Photo the ingredients"
        case .checking, .noIngredients: "Barcode found"
        case .notFound: "Barcode read"
        case .reading: "Ingredients photo"
        case .product, .cameraOff, .offline: ""
        }
    }

    private var subhint: some View {
        HStack(alignment: .bottom, spacing: Theme.spacing.xs) {
            MascotView(state: .point, size: 26, animates: false)
            Text(model.mode == .barcode ? "Hold steady inside the frame · tap to try"
                                        : "The ingredient list on the pack, or upload a photo of it")
                .themeText(.callout)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, Theme.spacing.screenGutter)
    }

    // MARK: Frame

    static let frameRadius: CGFloat = 24

    /// "brackets tighten 6 pt and turn green" once a barcode is found.
    private var isFound: Bool {
        switch model.phase {
        case .checking, .product, .noIngredients: true
        default: false
        }
    }

    private var frameSize: CGSize {
        model.mode == .barcode ? CGSize(width: 280, height: 200) : CGSize(width: 280, height: 360)
    }

    private var scanFrame: some View {
        let inset: CGFloat = isFound ? 6 : 0
        return FrameBrackets(cornerRadius: Self.frameRadius)
            .stroke(isFound ? Theme.verdict.ok.color : .white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .padding(inset)
            .frame(width: frameSize.width, height: frameSize.height)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame.update($0) }
            .overlay { frameTapTarget }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isFound)
            .animation(.easeOut(duration: 0.26), value: model.mode)
    }

    /// Tap the frame: the shutter in ingredients mode. In the simulator, the fixture picker.
    @ViewBuilder private var frameTapTarget: some View {
        if model.phase == .idle {
            #if targetEnvironment(simulator)
            fixturePicker
            #else
            if model.mode == .ingredients {
                Button(action: shutter) { Color.clear.contentShape(.rect) }
                    .accessibilityLabel("Take a photo of the ingredients")
            }
            #endif
        }
    }

    #if targetEnvironment(simulator)
    /// Simulator fallback: pick what the camera "sees" from the fixtures.
    private static let fixtures = (try? SampleData.products()) ?? []

    private var fixturePicker: some View {
        let fixtures = Self.fixtures
        return Menu {
            if model.mode == .barcode {
                ForEach(fixtures.filter { $0.barcode != nil }) { product in
                    Button(product.name) { model.barcodeRead(product.barcode ?? "") }
                }
                Button("Unknown barcode") { model.barcodeRead("012345678905") }
                Button("Camera off") { model.cameraAccess(granted: false) }
                Button("No connection") { model.phase = .offline }
            } else {
                ForEach(fixtures.filter { $0.ingredientsText != nil }) { product in
                    Button(product.name) {
                        model.readingStarted()
                        model.ingredientsRecognized(["Ingredients: " + (product.ingredientsText ?? "")])
                    }
                }
                Button("A photo with no list") {
                    model.readingStarted()
                    model.ingredientsRecognized([])
                }
            }
        } label: {
            Color.clear.contentShape(.rect)
        }
        .accessibilityLabel("Pick a sample product")
        .accessibilityIdentifier("scan.fixturePicker")
    }
    #endif

    // MARK: Bottom

    @ViewBuilder private var bottom: some View {
        switch model.phase {
        case .idle:
            controls.padding(.bottom, Theme.spacing.xl)
        case .checking(let code):
            ScanCheckingCard(line: "Looking up \(BarcodeFormat.display(code))…").transition(cardTransition)
        case .reading:
            ScanCheckingCard(line: "Reading the ingredients…").transition(cardTransition)
        case .notFound(let code):
            ScanNotFoundCard(barcode: code, reported: model.reported, onPhoto: model.photoTheIngredients,
                             onReport: { showReport = true }, onCheckAnother: model.checkAnother)
                .transition(cardTransition)
        case .noIngredients(let result):
            ScanNoIngredientsCard(result: result, reported: model.reported, onPhoto: model.photoTheIngredients,
                                  onReport: { showReport = true }, onCheckAnother: model.checkAnother)
                .transition(cardTransition)
        case .unreadable:
            ScanUnreadableCard(onRetake: model.photoTheIngredients, onCheckAnother: model.checkAnother)
                .transition(cardTransition)
        case .product, .cameraOff, .offline:
            EmptyView()
        }
    }

    /// "slides up 24 pt + fade"; fade only with Reduce Motion.
    private var cardTransition: AnyTransition {
        reduceMotion ? .opacity : .offset(y: 24).combined(with: .opacity)
    }

    private var controls: some View {
        // One glass pass for the mode picker and the pills.
        GlassEffectContainer(spacing: Theme.spacing.xs) {
            VStack(spacing: Theme.spacing.l) {
                SegmentedPicker(label: "Mode", options: [(ScanModel.Mode.barcode, "Barcode"), (.ingredients, "Ingredients")],
                                selection: Binding(get: { model.mode }, set: { model.mode = $0; model.modeChanged() }))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.spacing.m) { pills }
                    VStack(spacing: Theme.spacing.s) { pills }
                }
            }
        }
        .padding(.horizontal, Theme.spacing.l)
    }

    @ViewBuilder private var pills: some View {
        if model.mode == .barcode {
            pill("Enter code", systemImage: "keyboard") { showEnterCode = true }
        } else {
            pill("Upload a photo", systemImage: "photo") { showPhotoPicker = true }
        }
        pill("Type a name", systemImage: "magnifyingglass", action: onTypeName)
    }

    private func pill(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .themeText(Theme.TypeStyle(size: 17, weight: .medium, relativeTo: .body))
                .frame(minHeight: 36)
        }
        .buttonStyle(.glass(.clear))
    }

    // MARK: Actions

    private var productBinding: Binding<ScanResult?> {
        Binding {
            if case .product(let result) = model.phase { result } else { nil }
        } set: { newValue in
            if newValue == nil, case .product = model.phase { model.checkAnother() }
        }
    }

    private func productActions(_ product: Product) -> ProductPage.Actions {
        var actions = ProductPage.Actions()
        actions.setGoTo = { onSetGoTo(product, $0) }
        actions.ask = { _ in onAsk(product) }
        actions.compare = { onCompare(product, $0) }
        actions.seeAllOptions = { onCompareWith(product) }
        actions.checkAnother = model.checkAnother
        actions.photoIngredients = model.photoTheIngredients
        actions.close = model.checkAnother
        return actions
    }

    private func resultShown(_ phase: ScanModel.Phase) {
        switch phase {
        case .product(let result), .noIngredients(let result):
            onResult(result.product)
            AccessibilityNotification.Announcement(result.verdict.verdict.line).post()
        case .notFound:
            AccessibilityNotification.Announcement(ScanNotFoundCard.headline).post()
        case .unreadable:
            AccessibilityNotification.Announcement(ScanUnreadableCard.headline).post()
        case .offline:
            AccessibilityNotification.Announcement(ScanOfflineView.headline).post()
        default:
            break
        }
    }

    private func shutter() {
        readPhoto { try await handle.capturePhoto() }
    }

    /// The photo stays in memory only; Vision reads it on the iPhone.
    private func readPhoto(_ load: @escaping () async throws -> UIImage?) {
        model.readingStarted()
        Task {
            let image = try? await load()
            let lines = if let image { await TextRecognizer.lines(in: image) } else { [String]() }
            model.ingredientsRecognized(lines)
        }
    }

    private func report(_ reason: ScanReportReason) {
        var barcode: String?
        var name: String?
        switch model.phase {
        case .notFound(let code): barcode = code
        case .noIngredients(let result): barcode = result.product.barcode; name = result.product.name
        default: break
        }
        onReport(ScanReport(reason: reason, barcode: barcode, productName: name))
        model.markReported()
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    /// `AVCaptureDevice` authorization, asked only when the screen opens (HIG privacy).
    private func checkCameraAccess() async {
        #if targetEnvironment(simulator)
        // No camera in the simulator: the fixture picker stands in, so access is not asked.
        return
        #else
        let granted: Bool
        if !ScannerView.canScan && AVCaptureDevice.authorizationStatus(for: .video) != .notDetermined {
            granted = false
        } else {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: granted = true
            case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
            default: granted = false
            }
        }
        // `isAvailable` turns true only once access is granted, so check it after the prompt.
        let ready = granted && ScannerView.canScan
        cameraReady = ready
        model.cameraAccess(granted: ready)
        #endif
    }
}

/// Four rounded corner brackets (spec 03 "Frame", prototype path).
// Custom shape: no system viewfinder brackets.
nonisolated struct FrameBrackets: Shape {
    let cornerRadius: CGFloat
    /// Length of each bracket arm past the corner arc.
    var arm: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        let r = cornerRadius, a = arm
        var p = Path()
        // Top left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + r + a))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + r, y: rect.minY), radius: r)
        p.addLine(to: CGPoint(x: rect.minX + r + a, y: rect.minY))
        // Top right
        p.move(to: CGPoint(x: rect.maxX - r - a, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r), radius: r)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r + a))
        // Bottom right
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - r - a))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY), radius: r)
        p.addLine(to: CGPoint(x: rect.maxX - r - a, y: rect.maxY))
        // Bottom left
        p.move(to: CGPoint(x: rect.minX + r + a, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r), radius: r)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r - a))
        return p
    }
}

/// The dim layer around the frame: #232323 at 55 % with a clear cutout (spec 03 "Layout").
// Custom: an even-odd path; no system dimming view has a cutout.
/// The scan frame's global rect. `live` follows every layout frame and only `DimLayer` reads it, so
/// a moving frame redraws the dim layer, not the whole screen and the scanner. `settled` is the rect
/// once it has not moved for 150 ms: the scanner's region of interest.
@Observable
final class ScanFrameRect {
    private(set) var live: CGRect = .zero
    private(set) var settled: CGRect = .zero
    @ObservationIgnored private var settling: Task<Void, Never>?

    func update(_ rect: CGRect) {
        live = rect
        settling?.cancel()
        // The first layout settles at once, so the scanner starts with its region.
        guard settled != .zero else { settled = rect; return }
        settling = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.settled = rect
        }
    }
}

private struct DimLayer: View {
    let frame: ScanFrameRect
    /// The frame in global coordinates.
    private var cutout: CGRect { frame.live }
    let cornerRadius: CGFloat

    init(frame: ScanFrameRect, cornerRadius: CGFloat) {
        self.frame = frame
        self.cornerRadius = cornerRadius
    }

    /// spec 03 "dim layer": #232323 at 55 %. #232323 is not a token; ink is the nearest (Q18, Q-T8-2).
    private static let dim = Theme.color.ink.opacity(0.55)

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            Path { p in
                p.addRect(CGRect(origin: .zero, size: geo.size))
                if cutout != .zero {
                    p.addRoundedRect(in: cutout.offsetBy(dx: -origin.x, dy: -origin.y),
                                     cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: .continuous)
                }
            }
            .fill(Self.dim, style: FillStyle(eoFill: true))
        }
    }
}

// MARK: - Previews (one per state in spec 03)

/// Preview helpers: the sample household and a model already in a state.
enum ScanPreview {
    static let household = (try? SampleData.household()) ?? Household(people: [Person(id: "you", name: "Alex", isOwner: true)])
    static let products = (try? SampleData.products()) ?? []

    static func model(_ phase: ((ScanModel) -> Void)? = nil, mode: ScanModel.Mode = .barcode) -> ScanModel {
        let model = ScanModel(source: FixtureProductSource(), verdictService: VerdictService(),
                              household: household, region: household.region,
                              checkedBefore: Array(products.prefix(3)))
        model.mode = mode
        phase?(model)
        return model
    }

    static func product(_ barcode: String) -> Product? { products.first { $0.barcode == barcode } }
}

#Preview("1 Idle, barcode") {
    ScanScreen(model: ScanPreview.model())
}

#Preview("2 Checking") {
    ScanScreen(model: ScanPreview.model { $0.phase = .checking(barcode: "028400590318") })
}

#Preview("3 Product") {
    ScanScreen(model: ScanPreview.model { model in
        if let p = ScanPreview.product("0000000000017") { model.show(p) }
    })
}

#Preview("4 Ingredients mode") {
    ScanScreen(model: ScanPreview.model(mode: .ingredients))
}

#Preview("5 Not found") {
    ScanScreen(model: ScanPreview.model { $0.phase = .notFound(barcode: "012345678905") })
}

#Preview("6 No ingredients") {
    ScanScreen(model: ScanPreview.model { model in
        if let p = ScanPreview.product("0000000000086") { model.show(p) }
    })
}

#Preview("7 Camera off") {
    ScanScreen(model: ScanPreview.model { $0.phase = .cameraOff })
}

#Preview("8 Offline") {
    ScanScreen(model: ScanPreview.model { $0.phase = .offline })
}

#Preview("Reading a photo") {
    ScanScreen(model: ScanPreview.model({ $0.readingStarted() }, mode: .ingredients))
}

#Preview("Photo unreadable") {
    ScanScreen(model: ScanPreview.model({ $0.readingStarted(); $0.ingredientsRecognized([]) }, mode: .ingredients))
}
