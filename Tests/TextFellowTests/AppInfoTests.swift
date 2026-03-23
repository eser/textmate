import Testing
@testable import TextFellow

@Suite("AppInfo")
struct AppInfoTests {
    @Test("shared instance is consistent")
    func sharedInstance() {
        let a = AppInfo.shared
        let b = AppInfo.shared
        #expect(a === b)
    }

    @Test("appName returns a non-empty string")
    func appName() {
        #expect(!AppInfo.shared.appName.isEmpty)
    }

    @Test("support path contains TextMate")
    func supportPath() {
        #expect(AppInfo.shared.supportPath.contains("TextMate"))
    }

    @Test("cache path contains com.macromates")
    func cachePath() {
        #expect(AppInfo.shared.cachePath.contains("com.macromates"))
    }
}
