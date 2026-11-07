import Foundation
import Darwin

func runAgentCommand(_ name: String, _ arguments: [String], allowFailure: Bool = false) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [name] + arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    FileHandle.standardError.write(Data("  Running: \(([name] + arguments).joined(separator: " "))\n".utf8))
    try process.run()
    let timeout = TimeInterval(ProcessInfo.processInfo.environment["MAC_OCR_CONFIG_TIMEOUT_MS"].flatMap(Int.init) ?? 30_000) / 1000
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
    if process.isRunning {
        kill(process.processIdentifier, SIGTERM)
        Thread.sleep(forTimeInterval: 0.5)
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        throw CLIError.invalid("\(name) command timed out after \(Int(timeout)) seconds")
    }
    process.waitUntilExit()
    if process.terminationStatus != 0 && !allowFailure {
        throw CLIError.invalid("\(name) command failed with status \(process.terminationStatus)")
    }
}

func locateMCPBundle() throws -> (server: URL, opencodeHelper: URL) {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let installedRoot = home.appendingPathComponent(".local/share/mac-ocr")
    let installedServer = installedRoot.appendingPathComponent("mcp/dist/index.js")
    let installedHelper = installedRoot.appendingPathComponent("scripts/register-opencode.mjs")
    var directory = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
    while directory.path != "/" {
        let server = directory.appendingPathComponent("mcp/dist/index.js")
        let helper = directory.appendingPathComponent("scripts/register-opencode.mjs")
        if FileManager.default.fileExists(atPath: server.path), FileManager.default.fileExists(atPath: helper.path) {
            return (server, helper)
        }
        directory.deleteLastPathComponent()
    }
    if FileManager.default.fileExists(atPath: installedServer.path), FileManager.default.fileExists(atPath: installedHelper.path) {
        return (installedServer, installedHelper)
    }
    throw CLIError.invalid("MCP bundle not found. Build it with `make build-mcp` or install it with `make install`.")
}

func configureAgents(_ requested: [String]) throws {
    let allowed = ["claude", "codex", "opencode"]
    guard requested.allSatisfy(allowed.contains) else { throw CLIError.usage("Usage: mac-ocr configure [claude|codex|opencode]") }
    let bundle = try locateMCPBundle()
    let server = bundle.server
    for agent in requested {
        let label = agent == "claude" ? "Claude Code" : agent == "codex" ? "Codex" : "OpenCode"
        FileHandle.standardError.write(Data("Configuring \(label) MCP...\n".utf8))
        switch agent {
        case "claude":
            try runAgentCommand("claude", ["mcp", "remove", "mac-ocr", "--scope", "user"], allowFailure: true)
            try runAgentCommand("claude", ["mcp", "add", "--scope", "user", "mac-ocr", "--", "node", server.path])
        case "codex":
            try runAgentCommand("codex", ["mcp", "remove", "mac-ocr"], allowFailure: true)
            try runAgentCommand("codex", ["mcp", "add", "mac-ocr", "--", "node", server.path])
        case "opencode":
            try runAgentCommand("node", [bundle.opencodeHelper.path, server.path])
        default: break
        }
        FileHandle.standardError.write(Data("Configured \(label) MCP.\n".utf8))
    }
}
