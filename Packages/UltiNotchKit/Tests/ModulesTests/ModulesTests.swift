import Testing
@testable import Modules

@Suite("First-party modules")
@MainActor
struct ModulesTests {
    @Test func descriptorsFollowProductRules() {
        for descriptor in [MediaModule.descriptor, BatteryModule.descriptor] {
            #expect(descriptor.validationIssues.isEmpty, "\(descriptor.id)")
        }
    }
}
