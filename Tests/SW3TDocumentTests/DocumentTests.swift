import Testing
@testable import SW3TDocument
import Foundation

@Test func fileServiceScansDirectory() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appending(path: "sw3t-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Create test files
    try "hello".write(to: tempDir.appending(path: "a.swift"), atomically: true, encoding: .utf8)
    try "world".write(to: tempDir.appending(path: "b.txt"), atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(
        at: tempDir.appending(path: "src"),
        withIntermediateDirectories: true
    )
    try "nested".write(
        to: tempDir.appending(path: "src/c.rs"),
        atomically: true, encoding: .utf8
    )

    let service = FileService()
    let tree = try service.scanDirectory(at: tempDir)

    // Directories first, then files (sorted)
    #expect(tree.count == 3) // src/, a.swift, b.txt
    #expect(tree[0].name == "src")
    #expect(tree[0].isDirectory)
    #expect(tree[0].children.count == 1)
    #expect(tree[0].children[0].name == "c.rs")
    #expect(tree[1].name == "a.swift")
    #expect(tree[2].name == "b.txt")
}

@Test func fileServiceExcludesNodeModules() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appending(path: "sw3t-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try FileManager.default.createDirectory(
        at: tempDir.appending(path: "node_modules"),
        withIntermediateDirectories: true
    )
    try "pkg".write(
        to: tempDir.appending(path: "node_modules/pkg.js"),
        atomically: true, encoding: .utf8
    )
    try "app".write(to: tempDir.appending(path: "app.js"), atomically: true, encoding: .utf8)

    let service = FileService()
    let tree = try service.scanDirectory(at: tempDir)

    #expect(tree.count == 1) // only app.js, node_modules excluded
    #expect(tree[0].name == "app.js")
}

@Test func fileServiceReadWrite() throws {
    let tempFile = FileManager.default.temporaryDirectory
        .appending(path: "sw3t-test-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let service = FileService()
    try service.writeFile("Hello, Fellow!", to: tempFile)
    let content = try service.readFile(at: tempFile)
    #expect(content == "Hello, Fellow!")
}
