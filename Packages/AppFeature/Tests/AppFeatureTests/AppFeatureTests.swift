import Testing
@testable import AppFeature

// Milestone 0 smoke test: confirms the test target is wired up and Swift Testing runs.
// Real coverage arrives with the implementation — see docs/TESTING.md.
@Suite("AppFeature")
struct AppFeatureTests {
    @Test("module is importable")
    func moduleLoads() {
        #expect(Bool(true))
    }
}
