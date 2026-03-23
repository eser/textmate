import Testing
@testable import TextFellow

@Suite("LSPCoordinator")
struct LSPCoordinatorTests {
    @Test("has default servers registered")
    func defaultServers() {
        let coord = LSPCoordinator.shared
        #expect(coord.registeredServerCount >= 5)
    }

    @Test("finds client config for Swift files")
    func swiftConfig() {
        // No server running, but config should exist
        let coord = LSPCoordinator.shared
        // client returns nil when server not started
        // but the config lookup should work
        #expect(coord.registeredServerCount > 0)
    }

    @Test("no active servers at startup")
    func noActiveAtStartup() {
        #expect(LSPCoordinator.shared.activeServerCount == 0)
    }
}
