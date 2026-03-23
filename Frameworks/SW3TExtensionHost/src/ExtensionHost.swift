// SW³ TextFellow — WASM Extension Host
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// MARK: - Extension Protocol

/// Protocol for executing TextMate bundle commands.
/// Two implementations:
/// - `SubprocessExtensionRunner` — existing behavior (fork/exec, Ruby/bash/etc.)
/// - `WASMExtensionRunner` — new WASM-based execution via WAMR
public protocol ExtensionRunner: Sendable {
    /// Execute a command with the given input and environment.
    /// Returns the output and exit status.
    func execute(
        command: ExtensionCommand,
        input: Data,
        environment: [String: String]
    ) async throws -> ExtensionResult
}

/// A command to execute.
public struct ExtensionCommand: Sendable {
    public let name: String
    public let script: String
    public let interpreter: Interpreter
    public let workingDirectory: String?

    public init(name: String, script: String, interpreter: Interpreter, workingDirectory: String? = nil) {
        self.name = name
        self.script = script
        self.interpreter = interpreter
        self.workingDirectory = workingDirectory
    }

    public enum Interpreter: String, Sendable {
        case bash = "/bin/bash"
        case ruby = "/usr/bin/ruby"
        case python = "/usr/bin/python3"
        case node = "/usr/bin/env node"
        case wasm = "wasm"
    }
}

/// Result of executing a command.
public struct ExtensionResult: Sendable {
    public let stdout: Data
    public let stderr: Data
    public let exitCode: Int32

    public init(stdout: Data, stderr: Data, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }

    public var stdoutString: String {
        String(data: stdout, encoding: .utf8) ?? ""
    }

    public var stderrString: String {
        String(data: stderr, encoding: .utf8) ?? ""
    }

    public var success: Bool { exitCode == 0 }
}

// MARK: - Subprocess Runner (existing behavior)

/// Runs commands as subprocesses — the traditional TextMate way.
/// This wraps the existing fork/exec mechanism in the new protocol.
public final class SubprocessExtensionRunner: ExtensionRunner, @unchecked Sendable {
    public init() {}

    public func execute(
        command: ExtensionCommand,
        input: Data,
        environment: [String: String]
    ) async throws -> ExtensionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.interpreter.rawValue)
        process.arguments = ["-c", command.script]
        process.environment = environment

        if let dir = command.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
        }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Write input
        stdinPipe.fileHandleForWriting.write(input)
        stdinPipe.fileHandleForWriting.closeFile()

        // Read output
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        return ExtensionResult(
            stdout: stdoutData,
            stderr: stderrData,
            exitCode: process.terminationStatus
        )
    }
}

// MARK: - WASM Runner

/// Runs commands as WASM modules via WAMR (WebAssembly Micro Runtime).
///
/// ```
///  WASM Execution Pipeline:
///
///  .wasm module ──► WAMR Runtime ──► WASI API
///       │                               │
///       │  stdin/stdout:                 │
///       │  mapped to ExtensionCommand    │
///       │  input/output                  │
///       │                               │
///       ▼                               ▼
///  ExtensionResult ◄── stdout/stderr capture
/// ```
///
/// Current status: Stub implementation. WAMR integration requires
/// building the C runtime and linking it. The protocol boundary
/// allows the rest of the app to work regardless.
public final class WASMExtensionRunner: ExtensionRunner, @unchecked Sendable {
    /// Path to directory containing .wasm modules.
    public let modulesDirectory: URL

    public init(modulesDirectory: URL) {
        self.modulesDirectory = modulesDirectory
    }

    public func execute(
        command: ExtensionCommand,
        input: Data,
        environment: [String: String]
    ) async throws -> ExtensionResult {
        // TODO: When WAMR C runtime is compiled and linked:
        //
        // 1. Load .wasm module from modulesDirectory
        // 2. Initialize WAMR runtime with WASI support
        // 3. Map stdin to input Data
        // 4. Map environment variables
        // 5. Execute wasm_application_execute_main()
        // 6. Capture stdout/stderr
        // 7. Return ExtensionResult
        //
        // For now, return an error indicating WASM is not yet available.

        throw ExtensionHostError.wasmNotAvailable
    }
}

// MARK: - Extension Host

/// Manages extension runners and routes commands to the appropriate one.
///
/// Selection logic:
/// 1. If command.interpreter == .wasm AND wasm runner is available → WASM
/// 2. Otherwise → subprocess (existing TextMate behavior)
@objc(SW3TExtensionHost)
public final class ExtensionHost: NSObject, @unchecked Sendable {
    @objc public static let shared = ExtensionHost()

    private let subprocessRunner = SubprocessExtensionRunner()
    private var wasmRunner: WASMExtensionRunner?

    public override init() {
        super.init()

        // Look for WASM modules in Application Support
        let paths = NSSearchPathForDirectoriesInDomains(
            .applicationSupportDirectory, .userDomainMask, true)
        if let support = paths.first {
            let modulesDir = URL(fileURLWithPath: support)
                .appendingPathComponent("TextMate/Extensions/wasm")
            wasmRunner = WASMExtensionRunner(modulesDirectory: modulesDir)
        }
    }

    /// Execute a command using the appropriate runner.
    public func execute(
        command: ExtensionCommand,
        input: Data = Data(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> ExtensionResult {
        if command.interpreter == .wasm, let wasmRunner {
            do {
                return try await wasmRunner.execute(
                    command: command, input: input, environment: environment)
            } catch ExtensionHostError.wasmNotAvailable {
                // Fall through to subprocess
            }
        }

        return try await subprocessRunner.execute(
            command: command, input: input, environment: environment)
    }
}

// MARK: - Errors

public enum ExtensionHostError: Error, Sendable {
    case wasmNotAvailable
    case moduleNotFound(String)
    case runtimeError(String)
    case timeout
}
