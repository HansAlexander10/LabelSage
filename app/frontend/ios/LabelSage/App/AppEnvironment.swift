import SwiftUI

/// One instance of each service for the whole app; the environment defaults and the app root use these.
nonisolated enum AppServices {
    static let productSource: any ProductSource = ProductSourceFactory.make()
    static let verdictService = VerdictService()
    static let explanationService = ExplanationService()
}

// Services in the environment, so screens and previews read them without globals.
extension EnvironmentValues {
    /// Products by barcode, name and options. Fixtures until D4 is decided.
    @Entry var productSource: any ProductSource = AppServices.productSource
    /// The verdict for the household, with the mascot pose.
    @Entry var verdictService: VerdictService = AppServices.verdictService
    /// The on-device rewrite of a reason, with the engine's line as fallback.
    @Entry var explanationService: ExplanationService = AppServices.explanationService
}
