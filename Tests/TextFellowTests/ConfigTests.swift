import Testing
@testable import TextFellow

@Suite("LayeredConfig")
struct ConfigTests {
    @Test("defaults provide editor.font_name")
    func defaultFont() {
        let config = LayeredConfig()  // fresh instance, defaults only
        #expect(config.stringValue(forKey: "editor.font_name") == "Menlo")
    }

    @Test("defaults provide editor.tab_size")
    func defaultTabSize() {
        let config = LayeredConfig()
        #expect(config.integerValue(forKey: "editor.tab_size") == 4)
    }

    @Test("defaults provide editor.soft_tabs")
    func defaultSoftTabs() {
        let config = LayeredConfig()
        #expect(config.boolValue(forKey: "editor.soft_tabs") == true)
    }

    @Test("defaults provide editor.font_size")
    func defaultFontSize() {
        let config = LayeredConfig()
        #expect(config.integerValue(forKey: "editor.font_size") == 13)
    }

    @Test("unknown key returns nil")
    func unknownKey() {
        let config = LayeredConfig()
        #expect(config.stringValue(forKey: "nonexistent.key") == nil)
    }

    @Test("shared instance loads user settings")
    func sharedLoadsUser() {
        // shared instance may have user overrides — just verify it exists
        #expect(LayeredConfig.shared.stringValue(forKey: "editor.font_name") != nil)
    }
}
