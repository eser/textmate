// SW3 TextFellow — Language Server Protocol Client
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Actor-based LSP client using JSON-RPC 2.0 over stdin/stdout.
// Manages a language server subprocess and provides async/await API
// for common LSP operations.

import Foundation

// MARK: - Data Types

/// Position in a text document (0-based line and character).
public struct LSPPosition: Codable, Sendable {
    public let line: Int
    public let character: Int

    public init(line: Int, character: Int) {
        self.line = line
        self.character = character
    }
}

/// A range in a text document.
public struct LSPRange: Codable, Sendable {
    public let start: LSPPosition
    public let end: LSPPosition

    public init(start: LSPPosition, end: LSPPosition) {
        self.start = start
        self.end = end
    }
}

/// A location in a document (URI + range).
public struct LSPLocation: Codable, Sendable {
    public let uri: String
    public let range: LSPRange

    public init(uri: String, range: LSPRange) {
        self.uri = uri
        self.range = range
    }
}

/// A completion item returned by the server.
public struct LSPCompletionItem: Codable, Sendable {
    public let label: String
    public let kind: Int?
    public let detail: String?
    public let insertText: String?
    public let documentation: LSPDocumentation?

    public init(
        label: String,
        kind: Int? = nil,
        detail: String? = nil,
        insertText: String? = nil,
        documentation: LSPDocumentation? = nil
    ) {
        self.label = label
        self.kind = kind
        self.detail = detail
        self.insertText = insertText
        self.documentation = documentation
    }
}

/// Documentation can be a plain string or MarkupContent.
public enum LSPDocumentation: Codable, Sendable {
    case string(String)
    case markup(kind: String, value: String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
            return
        }
        let obj = try container.decode(MarkupContent.self)
        self = .markup(kind: obj.kind, value: obj.value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s):
            try container.encode(s)
        case .markup(let kind, let value):
            try container.encode(MarkupContent(kind: kind, value: value))
        }
    }

    private struct MarkupContent: Codable {
        let kind: String
        let value: String
    }
}

/// Hover result returned by the server.
public struct LSPHoverResult: Sendable {
    public let contents: String
    public let range: LSPRange?

    public init(contents: String, range: LSPRange? = nil) {
        self.contents = contents
        self.range = range
    }
}

/// JSON-RPC message types.
public enum LSPMessage: @unchecked Sendable {
    case request(id: Int, method: String, params: [String: Any]?)
    case response(id: Int, result: Any?, error: LSPError?)
    case notification(method: String, params: [String: Any]?)
}

/// JSON-RPC error.
public struct LSPError: Error, Sendable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

// MARK: - LSP Client Actor

/// Actor that manages a language server subprocess and communicates
/// using JSON-RPC 2.0 over stdin/stdout with Content-Length framing.
public actor LSPClient {

    // MARK: - State

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    private var nextRequestID: Int = 1
    private var pendingRequests: [Int: CheckedContinuation<Data, Error>] = [:]
    private var isRunning = false
    private var readTask: Task<Void, Never>?

    private let serverPath: String
    private let serverArguments: [String]
    private let workspaceRoot: URL?

    // MARK: - Init

    /// Create an LSP client for a given server executable.
    ///
    /// - Parameters:
    ///   - serverPath: Path to the language server binary.
    ///   - arguments: Arguments to pass to the server.
    ///   - workspaceRoot: Root URL of the workspace.
    public init(
        serverPath: String,
        arguments: [String] = [],
        workspaceRoot: URL? = nil
    ) {
        self.serverPath = serverPath
        self.serverArguments = arguments
        self.workspaceRoot = workspaceRoot
    }

    deinit {
        readTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Start the language server process and perform initialization.
    public func start() async throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: serverPath)
        proc.arguments = serverArguments

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        stdinPipe = stdin
        stdoutPipe = stdout
        stderrPipe = stderr
        process = proc

        try proc.run()
        isRunning = true

        // Start reading responses
        readTask = Task { [weak self] in
            await self?.readLoop()
        }

        // Send initialize request
        _ = try await initialize()
        try await sendNotification("initialized", params: [:])
    }

    /// Shut down the language server gracefully.
    public func stop() async throws {
        guard isRunning else { return }

        _ = try await sendRequest("shutdown", params: nil)
        try await sendNotification("exit", params: nil)

        readTask?.cancel()
        readTask = nil

        process?.terminate()
        process?.waitUntilExit()
        isRunning = false

        // Fail any pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: LSPError(code: -1, message: "Server stopped"))
        }
        pendingRequests.removeAll()
    }

    // MARK: - LSP Methods

    /// Send the initialize request.
    private func initialize() async throws -> Data {
        var params: [String: Any] = [
            "processId": ProcessInfo.processInfo.processIdentifier,
            "capabilities": [
                "textDocument": [
                    "completion": [
                        "completionItem": ["snippetSupport": true]
                    ],
                    "hover": ["contentFormat": ["plaintext", "markdown"]],
                    "definition": [:] as [String: Any],
                ] as [String: Any]
            ] as [String: Any],
        ]

        if let root = workspaceRoot {
            params["rootUri"] = root.absoluteString
            params["rootPath"] = root.path
        }

        return try await sendRequest("initialize", params: params)
    }

    /// Notify the server that a document was opened.
    public func didOpenDocument(uri: String, languageId: String, version: Int, text: String) async throws {
        try await sendNotification("textDocument/didOpen", params: [
            "textDocument": [
                "uri": uri,
                "languageId": languageId,
                "version": version,
                "text": text,
            ]
        ])
    }

    /// Notify the server of a full document change.
    public func didChangeDocument(uri: String, version: Int, text: String) async throws {
        try await sendNotification("textDocument/didChange", params: [
            "textDocument": [
                "uri": uri,
                "version": version,
            ],
            "contentChanges": [
                ["text": text]
            ],
        ])
    }

    /// Request completions at a position.
    public func completion(uri: String, position: LSPPosition) async throws -> [LSPCompletionItem] {
        let data = try await sendRequest("textDocument/completion", params: [
            "textDocument": ["uri": uri],
            "position": ["line": position.line, "character": position.character],
        ])

        // Parse response — can be CompletionList or [CompletionItem]
        let json = try JSONSerialization.jsonObject(with: data)

        let items: [[String: Any]]
        if let list = json as? [String: Any], let listItems = list["items"] as? [[String: Any]] {
            items = listItems
        } else if let arr = json as? [[String: Any]] {
            items = arr
        } else {
            return []
        }

        return items.compactMap { dict in
            guard let label = dict["label"] as? String else { return nil }
            return LSPCompletionItem(
                label: label,
                kind: dict["kind"] as? Int,
                detail: dict["detail"] as? String,
                insertText: dict["insertText"] as? String
            )
        }
    }

    /// Request hover information at a position.
    public func hover(uri: String, position: LSPPosition) async throws -> LSPHoverResult? {
        let data = try await sendRequest("textDocument/hover", params: [
            "textDocument": ["uri": uri],
            "position": ["line": position.line, "character": position.character],
        ])

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let json else { return nil }

        let contents: String
        if let contentsObj = json["contents"] as? [String: Any],
           let value = contentsObj["value"] as? String
        {
            contents = value
        } else if let str = json["contents"] as? String {
            contents = str
        } else {
            return nil
        }

        var range: LSPRange?
        if let rangeObj = json["range"] as? [String: Any] {
            range = parseRange(rangeObj)
        }

        return LSPHoverResult(contents: contents, range: range)
    }

    /// Request go-to-definition at a position.
    public func definition(uri: String, position: LSPPosition) async throws -> [LSPLocation] {
        let data = try await sendRequest("textDocument/definition", params: [
            "textDocument": ["uri": uri],
            "position": ["line": position.line, "character": position.character],
        ])

        let json = try JSONSerialization.jsonObject(with: data)

        // Can be Location | [Location] | null
        if let loc = json as? [String: Any] {
            if let parsed = parseLocation(loc) {
                return [parsed]
            }
        } else if let arr = json as? [[String: Any]] {
            return arr.compactMap { parseLocation($0) }
        }

        return []
    }

    // MARK: - JSON-RPC Transport

    /// Send a JSON-RPC request and wait for the response.
    private func sendRequest(_ method: String, params: [String: Any]?) async throws -> Data {
        let id = nextRequestID
        nextRequestID += 1

        var message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
        ]
        if let params { message["params"] = params }

        let data = try JSONSerialization.data(withJSONObject: message)
        try writeMessage(data)

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
        }
    }

    /// Send a JSON-RPC notification (no response expected).
    private func sendNotification(_ method: String, params: [String: Any]?) async throws {
        var message: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
        ]
        if let params { message["params"] = params }

        let data = try JSONSerialization.data(withJSONObject: message)
        try writeMessage(data)
    }

    /// Write a message with Content-Length header framing.
    private func writeMessage(_ data: Data) throws {
        guard let stdin = stdinPipe else {
            throw LSPError(code: -1, message: "Server not started")
        }

        let header = "Content-Length: \(data.count)\r\n\r\n"
        guard let headerData = header.data(using: .utf8) else {
            throw LSPError(code: -1, message: "Failed to encode header")
        }

        let handle = stdin.fileHandleForWriting
        handle.write(headerData)
        handle.write(data)
    }

    /// Continuously read messages from stdout.
    private func readLoop() async {
        guard let stdout = stdoutPipe else { return }
        let handle = stdout.fileHandleForReading

        while !Task.isCancelled {
            do {
                guard let message = try readMessage(from: handle) else {
                    break
                }
                await handleIncomingMessage(message)
            } catch {
                if !Task.isCancelled { break }
            }
        }
    }

    /// Read a single JSON-RPC message with Content-Length framing.
    private func readMessage(from handle: FileHandle) throws -> Data? {
        // Read headers line by line until empty line
        var headerString = ""
        while true {
            let byte = handle.readData(ofLength: 1)
            if byte.isEmpty { return nil }
            headerString += String(data: byte, encoding: .utf8) ?? ""
            if headerString.hasSuffix("\r\n\r\n") { break }
        }

        // Extract Content-Length
        guard let match = headerString.range(of: #"Content-Length:\s*(\d+)"#, options: .regularExpression),
              let length = Int(
                  headerString[match]
                      .replacingOccurrences(of: "Content-Length:", with: "")
                      .trimmingCharacters(in: .whitespaces)
              )
        else {
            throw LSPError(code: -1, message: "Missing Content-Length header")
        }

        // Read body
        var body = Data()
        while body.count < length {
            let chunk = handle.readData(ofLength: length - body.count)
            if chunk.isEmpty { return nil }
            body.append(chunk)
        }

        return body
    }

    /// Handle an incoming JSON-RPC message (response or notification).
    private func handleIncomingMessage(_ data: Data) async {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Response (has "id" and either "result" or "error")
        if let id = json["id"] as? Int {
            if let continuation = pendingRequests.removeValue(forKey: id) {
                if let error = json["error"] as? [String: Any] {
                    let code = error["code"] as? Int ?? -1
                    let message = error["message"] as? String ?? "Unknown error"
                    continuation.resume(throwing: LSPError(code: code, message: message))
                } else {
                    // Re-serialize the result portion
                    let result = json["result"]
                    if let result, JSONSerialization.isValidJSONObject(result) {
                        do {
                            let resultData = try JSONSerialization.data(withJSONObject: result)
                            continuation.resume(returning: resultData)
                        } catch {
                            continuation.resume(returning: Data())
                        }
                    } else if let result {
                        // Scalar result (e.g., null)
                        let wrapped: Any = ["_": result]
                        if let d = try? JSONSerialization.data(withJSONObject: wrapped) {
                            continuation.resume(returning: d)
                        } else {
                            continuation.resume(returning: Data())
                        }
                    } else {
                        // null result (e.g., shutdown response)
                        continuation.resume(returning: Data())
                    }
                }
            }
        }
        // Server-initiated notifications are silently ignored for now.
    }

    // MARK: - Helpers

    private func parsePosition(_ dict: [String: Any]) -> LSPPosition? {
        guard let line = dict["line"] as? Int,
              let character = dict["character"] as? Int
        else { return nil }
        return LSPPosition(line: line, character: character)
    }

    private func parseRange(_ dict: [String: Any]) -> LSPRange? {
        guard let start = dict["start"] as? [String: Any],
              let end = dict["end"] as? [String: Any],
              let startPos = parsePosition(start),
              let endPos = parsePosition(end)
        else { return nil }
        return LSPRange(start: startPos, end: endPos)
    }

    private func parseLocation(_ dict: [String: Any]) -> LSPLocation? {
        guard let uri = dict["uri"] as? String,
              let rangeDict = dict["range"] as? [String: Any],
              let range = parseRange(rangeDict)
        else { return nil }
        return LSPLocation(uri: uri, range: range)
    }
}
