// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "sw3t",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        // Core libraries — shared across platforms
        .library(name: "SW3TTextEngine", targets: ["SW3TTextEngine"]),
        .library(name: "SW3TViewport", targets: ["SW3TViewport"]),
        .library(name: "SW3TRenderer", targets: ["SW3TRenderer"]),
        .library(name: "SW3TSyntax", targets: ["SW3TSyntax"]),
        .library(name: "SW3TDocument", targets: ["SW3TDocument"]),
        .library(name: "SW3TConfig", targets: ["SW3TConfig"]),
        .library(name: "SW3TViews", targets: ["SW3TViews"]),
        .library(name: "SW3TBundleRuntime", targets: ["SW3TBundleRuntime"]),
        .library(name: "SW3TLSP", targets: ["SW3TLSP"]),

        // Embeddable editor component (Phase 6)
        .library(name: "TextFellowKit", targets: [
            "SW3TTextEngine",
            "SW3TViewport",
            "SW3TRenderer",
            "SW3TSyntax",
        ]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
    ],
    targets: [
        // ─────────────────────────────────────────────
        // MARK: - Core Engine (no UI dependencies)
        // ─────────────────────────────────────────────

        .target(
            name: "SW3TTextEngine",
            dependencies: [
                .product(name: "Collections", package: "swift-collections"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),

        // ─────────────────────────────────────────────
        // MARK: - Syntax Highlighting
        // ─────────────────────────────────────────────

        .target(
            name: "SW3TSyntax",
            dependencies: ["SW3TTextEngine"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),

        // ─────────────────────────────────────────────
        // MARK: - Viewport (render coordination)
        // ─────────────────────────────────────────────

        .target(
            name: "SW3TViewport",
            dependencies: ["SW3TTextEngine", "SW3TSyntax"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),

        // ─────────────────────────────────────────────
        // MARK: - Metal Renderer
        // ─────────────────────────────────────────────

        .target(
            name: "SW3TRenderer",
            dependencies: ["SW3TViewport", "SW3TSyntax"],
            resources: [
                .process("Shaders.metal"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),

        // ─────────────────────────────────────────────
        // MARK: - Document Model
        // ─────────────────────────────────────────────

        .target(
            name: "SW3TDocument",
            dependencies: ["SW3TTextEngine", "SW3TSyntax", "SW3TViewport"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),

        // ─────────────────────────────────────────────
        // MARK: - Configuration
        // ─────────────────────────────────────────────

        .target(
            name: "SW3TConfig",
            dependencies: [],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),

        // ─────────────────────────────────────────────
        // MARK: - SwiftUI Views
        // ─────────────────────────────────────────────

        .target(
            name: "SW3TViews",
            dependencies: ["SW3TDocument", "SW3TRenderer", "SW3TConfig", "SW3TTextEngine", "SW3TSyntax"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),

        // ─────────────────────────────────────────────
        // MARK: - Bundle Runtime (WASM extension host)
        // ─────────────────────────────────────────────

        .target(
            name: "SW3TBundleRuntime",
            dependencies: ["SW3TTextEngine"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),

        // ─────────────────────────────────────────────
        // MARK: - LSP Client
        // ─────────────────────────────────────────────

        .target(
            name: "SW3TLSP",
            dependencies: ["SW3TTextEngine"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),

        // ─────────────────────────────────────────────
        // MARK: - App (macOS entry point)
        // ─────────────────────────────────────────────

        .executableTarget(
            name: "SW3TApp",
            dependencies: [
                "SW3TViews",
                "SW3TBundleRuntime",
                "SW3TLSP",
                "SW3TConfig",
            ],
            exclude: ["Info.plist"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),

        // ─────────────────────────────────────────────
        // MARK: - Tests
        // ─────────────────────────────────────────────

        .testTarget(
            name: "SW3TTextEngineTests",
            dependencies: ["SW3TTextEngine"]
        ),
        .testTarget(
            name: "SW3TViewportTests",
            dependencies: ["SW3TViewport", "SW3TTextEngine", "SW3TSyntax"]
        ),
        .testTarget(
            name: "SW3TRendererTests",
            dependencies: ["SW3TRenderer"]
        ),
        .testTarget(
            name: "SW3TSyntaxTests",
            dependencies: ["SW3TSyntax", "SW3TTextEngine"]
        ),
        .testTarget(
            name: "SW3TDocumentTests",
            dependencies: ["SW3TDocument", "SW3TTextEngine", "SW3TSyntax", "SW3TViewport"]
        ),
        .testTarget(
            name: "SW3TConfigTests",
            dependencies: ["SW3TConfig"]
        ),
    ]
)
