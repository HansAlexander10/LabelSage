import Testing
@testable import LabelSage

/// Smoke test for the unit-test target: the names come from one config value (handoff D11).
@Test func brandNamesAreLabelSage() {
    #expect(Brand.app == "LabelSage")
    #expect(Brand.mascot == "LabelSage")
}
