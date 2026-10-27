import Foundation
import Observation
import LabelSageCore

/// A product checked on the camera screen, with its household verdict.
nonisolated struct ScanResult: Sendable, Equatable, Identifiable {
    let product: Product
    /// From `VerdictEngine` through `VerdictService`; nothing else sets the level.
    let verdict: VerdictResult
    var id: String { product.id }

    /// The worst person's reason, the line under the flag ("Sunflower oil is the 2nd ingredient…").
    var reason: String {
        verdict.verdict.decidingPerson?.reason ?? ""
    }
}

/// What "Report it" says is wrong (spec 03: not found, wrong product, ingredients changed).
nonisolated enum ScanReportReason: String, Sendable, CaseIterable, Identifiable {
    case notFound
    case wrongProduct
    case ingredientsChanged

    var id: Self { self }

    var title: String {
        switch self {
        case .notFound: "It wasn’t found"
        case .wrongProduct: "Wrong product"
        case .ingredientsChanged: "Ingredients changed"
        }
    }
}

/// A report from the camera screen. The caller stores it on the iPhone (no backend in the MVP, D4).
/// Only the barcode and the product name: nothing about a person.
nonisolated struct ScanReport: Sendable, Equatable {
    let reason: ScanReportReason
    let barcode: String?
    let productName: String?
}

/// The state machine of "Check a product" (spec 03, states 1 to 8). The view only draws `phase`
/// and forwards events; lookups, debouncing, cancellation and the timeout live here.
@Observable
final class ScanModel {
    /// Barcode | Ingredients.
    enum Mode: Hashable, Sendable {
        case barcode
        case ingredients
    }

    enum Phase: Equatable {
        /// 1 and 4: the hint and the frame, nothing found yet.
        case idle
        /// 2: a barcode was read, the lookup runs.
        case checking(barcode: String)
        /// 4: an ingredients photo is being read on the iPhone.
        case reading
        /// 3: the product sheet over the camera.
        case product(ScanResult)
        /// 5: the source does not know this barcode.
        case notFound(barcode: String)
        /// 6: found, but no ingredient list yet ("Can’t confirm").
        case noIngredients(ScanResult)
        /// Edge case: the photo had no ingredient list on it.
        case unreadable
        /// 7: camera permission denied or restricted.
        case cameraOff
        /// 8: no connection.
        case offline
    }

    /// The name an ingredients photo gets (spec 03).
    static let photoName = "Your photo"
    /// "One barcode read is enough: debounce repeated reads of the same code for 2 s."
    static let debounce: Duration = .seconds(2)

    var mode: Mode = .barcode
    var phase: Phase = .idle
    /// Bumps once per barcode read or entered, and per ingredients photo read; drives the `success`
    /// haptic. "Try again" does not bump it.
    private(set) var foundCount = 0
    /// Reported in this visit, so the card shows "Thanks. We’ll add it."
    private(set) var reported = false

    /// Products checked before (local history), re-evaluated with today's household for the
    /// offline list.
    let checkedBefore: [Product]

    @ObservationIgnored private let source: any ProductSource
    @ObservationIgnored private let verdictService: VerdictService
    /// Who the verdicts are for; the product sheet shows the same household.
    @ObservationIgnored let household: Household
    @ObservationIgnored private let region: Region?
    @ObservationIgnored private let timeout: Duration
    @ObservationIgnored private var lastRead: (code: String, at: ContinuousClock.Instant)?
    @ObservationIgnored private var lastLookup: String?
    /// The running lookup; cancelled by "Check another", a mode switch or closing the screen.
    @ObservationIgnored private(set) var lookupTask: Task<Void, Never>?

    /// - Parameters:
    ///   - timeout: spec 03 state 2, "timeout 8 s → offline or not found". Tests pass a short one.
    init(source: any ProductSource, verdictService: VerdictService, household: Household,
         region: Region?, checkedBefore: [Product] = [], timeout: Duration = .seconds(8)) {
        self.source = source
        self.verdictService = verdictService
        self.household = household
        self.region = region
        self.checkedBefore = checkedBefore
        self.timeout = timeout
    }

    // MARK: Events

    /// The scanner read a code. Ignored unless the screen is idle in barcode mode, and for the same
    /// code within 2 s.
    func barcodeRead(_ raw: String) {
        let code = raw.filter(\.isNumber)
        guard phase == .idle, mode == .barcode, !code.isEmpty else { return }
        let now = ContinuousClock.now
        if let lastRead, lastRead.code == code, now - lastRead.at < Self.debounce { return }
        lastRead = (code, now)
        foundCount += 1
        startLookup(code)
    }

    /// "Enter code": the accessible path without the camera.
    func codeEntered(_ raw: String) {
        let code = raw.filter(\.isNumber)
        guard Self.isValidEnteredCode(code) else { return }
        mode = .barcode
        foundCount += 1
        startLookup(code)
    }

    /// Spec 03: "a numeric field (12 or 13 digits)".
    static func isValidEnteredCode(_ code: String) -> Bool {
        (code.count == 12 || code.count == 13) && code.allSatisfy(\.isNumber)
    }

    /// The OCR started on a photo.
    func readingStarted() {
        cancelLookup()
        phase = .reading
    }

    /// The OCR finished: lines from Vision become `Product(name: "Your photo", ingredientsText:)`.
    /// Ignored unless a photo is being read (the person may have tapped "Check another").
    func ingredientsRecognized(_ lines: [String]) {
        guard phase == .reading else { return }
        guard let text = IngredientsText.extract(from: lines) else {
            phase = .unreadable
            return
        }
        let product = Product(name: Self.photoName, ingredientsText: text)
        // The parser must find a list; otherwise it is the "couldn’t read" edge case.
        guard LabelParser.parse(product, catalog: verdictService.engine.catalog).hasList else {
            phase = .unreadable
            return
        }
        foundCount += 1
        show(product)
    }

    /// Camera permission or availability (spec 03 state 7).
    func cameraAccess(granted: Bool) {
        if !granted {
            cancelLookup()
            phase = .cameraOff
        } else if phase == .cameraOff {
            phase = .idle
        }
    }

    /// "Check another": closes the sheet or card, back to the frame. Cancels a running lookup.
    func checkAnother() {
        cancelLookup()
        reported = false
        phase = .idle
    }

    /// "Photo the ingredients": switches to ingredients mode.
    func photoTheIngredients() {
        checkAnother()
        mode = .ingredients
    }

    /// Barcode | Ingredients changed.
    func modeChanged() {
        if phase != .cameraOff { checkAnother() }
    }

    /// "Try again" on the offline state: repeats the last lookup.
    func tryAgain() {
        guard let lastLookup else { return checkAnother() }
        startLookup(lastLookup)
    }

    /// A row of "Checked before" tapped: open it like a fresh result.
    func show(_ product: Product) {
        cancelLookup()
        let result = ScanResult(product: product, verdict: verdictService.check(product, for: household))
        let hasList = !(product.ingredientsText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        phase = !hasList && result.verdict.verdict.overall == .cantConfirm ? .noIngredients(result) : .product(result)
    }

    /// A report was sent.
    func markReported() { reported = true }

    /// The checked-before list with today's verdicts.
    func checkedBeforeResults() -> [ScanResult] {
        checkedBefore.map { ScanResult(product: $0, verdict: verdictService.check($0, for: household)) }
    }

    /// The screen went away.
    func stop() { cancelLookup() }

    // MARK: Lookup

    /// Starts a lookup and returns its task (tests await it).
    @discardableResult
    func startLookup(_ code: String) -> Task<Void, Never> {
        cancelLookup()
        lastLookup = code
        reported = false
        phase = .checking(barcode: code)
        let task = Task { await lookUp(code) }
        lookupTask = task
        return task
    }

    private func lookUp(_ code: String) async {
        // Ends when the product sheet appears (ScanScreen); a lookup without a sheet leaves it open.
        Perf.beginPending("scan.toSheet")
        let timeout = self.timeout
        // The timeout ends a slow lookup as offline; it is cancelled with the lookup.
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, self.phase == .checking(barcode: code) else { return }
            Log.lookup.notice("Barcode lookup timed out")
            self.lookupTask?.cancel()
            self.phase = .offline
        }
        defer { timer.cancel() }

        let outcome: Result<Product, ProductSourceError>
        do {
            outcome = .success(try await source.requireProduct(barcode: code, region: region))
        } catch {
            outcome = .failure(error)
        }
        // A cancelled lookup never shows a result, and never "not found" (requireProduct throws
        // .cancelled, which `phase(for:)` ignores). The phase check drops a result that arrives after
        // "Check another" or a newer lookup.
        guard !Task.isCancelled, phase == .checking(barcode: code) else { return }
        switch outcome {
        case .success(let product): show(product)
        case .failure(let error): if let next = Self.phase(for: error, barcode: code) { phase = next }
        }
    }

    /// The screen state for a lookup error; nil means "ignore it" (a cancelled lookup).
    /// A cancelled lookup changes nothing on screen.
    static func phase(for error: ProductSourceError, barcode: String) -> Phase? {
        switch error {
        case .offline: .offline
        case .cancelled: nil
        case .notFound: .notFound(barcode: barcode)
        }
    }

    private func cancelLookup() {
        lookupTask?.cancel()
        lookupTask = nil
    }
}

/// Barcode digits as printed under the bars: "0 28400 59031 8" (UPC-A), "4 006381 333931" (EAN-13).
nonisolated enum BarcodeFormat {
    static func display(_ code: String) -> String {
        let d = Array(code)
        switch d.count {
        case 12: return "\(String(d[0])) \(String(d[1...5])) \(String(d[6...10])) \(String(d[11]))"
        case 13: return "\(String(d[0])) \(String(d[1...6])) \(String(d[7...12]))"
        case 8: return "\(String(d[0...3])) \(String(d[4...7]))"
        default: return code
        }
    }
}

/// Turns OCR lines into an ingredient list: everything from the word "Ingredients" on, so a
/// nutrition panel above it is left out. Without the word, all lines are used.
nonisolated enum IngredientsText {
    static func extract(from lines: [String]) -> String? {
        let text = lines.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !text.isEmpty else { return nil }
        if let range = text.range(of: "ingredient", options: [.caseInsensitive]) {
            return String(text[range.lowerBound...])
        }
        return text
    }
}
