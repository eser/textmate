import Testing
@testable import SW3TConfig

@Test func defaultsProvideExpectedValues() {
    let config = LayeredConfig()
    #expect(config.bool(for: "ui.sidebar") == false)
    #expect(config.bool(for: "ui.line_numbers") == true)
    #expect(config.integer(for: "editor.tab_size") == 4)
    #expect(config.string(for: "editor.font_name") == "Menlo")
    #expect(config.string(for: "theme.chrome") == "system")
    #expect(config.bool(for: "ui.typewriter_mode") == false)
}

@Test func higherPriorityLayerOverridesLower() {
    let config = LayeredConfig()

    // Add a "user" layer with tab_size = 2
    let userLayer = ConfigLayer(
        name: "user",
        values: ["editor.tab_size": .integer(2)],
        priority: 2
    )
    config.addLayer(userLayer)

    #expect(config.integer(for: "editor.tab_size") == 2) // user overrides default
    #expect(config.string(for: "editor.font_name") == "Menlo") // default still works
}

@Test func projectOverridesUser() {
    let config = LayeredConfig()

    config.addLayer(ConfigLayer(
        name: "user",
        values: ["editor.tab_size": .integer(2)],
        priority: 2
    ))
    config.addLayer(ConfigLayer(
        name: "project",
        values: ["editor.tab_size": .integer(8)],
        priority: 4
    ))

    #expect(config.integer(for: "editor.tab_size") == 8)
}

@Test func missingKeyReturnsNil() {
    let config = LayeredConfig()
    #expect(config.string(for: "nonexistent.key") == nil)
    #expect(config.integer(for: "nonexistent.key") == nil)
    #expect(config.bool(for: "nonexistent.key") == nil)
}

@Test func keysInSectionReturnsAllMatching() {
    let config = LayeredConfig()
    let uiKeys = config.keys(in: "ui")
    #expect(uiKeys.contains("ui.sidebar"))
    #expect(uiKeys.contains("ui.line_numbers"))
    #expect(!uiKeys.contains("editor.tab_size"))
}

@Test func tomlParsingBasicTypes() {
    let config = LayeredConfig()
    let parsed = config.parseTOML("""
    # Comment line
    name = "TextFellow"
    version = 42
    enabled = true
    disabled = false

    [theme]
    editor = "Monokai"
    chrome = "system"

    [ui]
    sidebar = true
    """)

    #expect(parsed["name"] == .string("TextFellow"))
    #expect(parsed["version"] == .integer(42))
    #expect(parsed["enabled"] == .bool(true))
    #expect(parsed["disabled"] == .bool(false))
    #expect(parsed["theme.editor"] == .string("Monokai"))
    #expect(parsed["theme.chrome"] == .string("system"))
    #expect(parsed["ui.sidebar"] == .bool(true))
}

@Test func tomlParsingSkipsEmptyAndComments() {
    let config = LayeredConfig()
    let parsed = config.parseTOML("""

    # This is a comment
    key = "value"

    # Another comment
    """)

    #expect(parsed.count == 1)
    #expect(parsed["key"] == .string("value"))
}

@Test func progressiveDisclosureDefaults() {
    // Verify the progressive disclosure principle:
    // Factory defaults should produce TextMate-like clean canvas
    let config = LayeredConfig()

    // Hidden by default
    #expect(config.bool(for: "ui.sidebar") == false)
    #expect(config.bool(for: "ui.terminal") == false)
    #expect(config.bool(for: "ui.scope_bar") == false)
    #expect(config.bool(for: "ui.minimap") == false)
    #expect(config.bool(for: "ui.typewriter_mode") == false)
    #expect(config.bool(for: "diagnostics.inline_summary") == false)
    #expect(config.bool(for: "git.inline_blame") == false)

    // Visible by default
    #expect(config.bool(for: "ui.line_numbers") == true)
    #expect(config.bool(for: "ui.fold_markers") == true)
    #expect(config.bool(for: "ui.sticky_scroll") == true)
    #expect(config.bool(for: "animations.enabled") == true)
}
