//
//  ActiveSessionDetector.swift
//  Claude Usage
//
//  Detects active Claude Code terminal sessions by checking for running `claude` processes
//  and mapping them to project directories.
//

import Foundation
import Combine

/// Represents a detected active Claude Code session
struct ActiveSession: Identifiable, Equatable {
    let id: String // unique key: project path
    let projectPath: String
    let projectName: String
    let sessionCount: Int // number of claude processes in this project
}

/// Detects running Claude Code processes and groups them by project
@MainActor
final class ActiveSessionDetector: ObservableObject {
    static let shared = ActiveSessionDetector()

    @Published private(set) var activeSessions: [ActiveSession] = []
    @Published private(set) var totalProcessCount: Int = 0

    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 10

    private init() {}

    // MARK: - Lifecycle

    func start() {
        scanForActiveSessions()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.scanForActiveSessions()
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Process-based detection

    private func scanForActiveSessions() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let sessions = Self.detectClaudeProcesses()
            DispatchQueue.main.async {
                self?.activeSessions = sessions
                self?.totalProcessCount = sessions.reduce(0) { $0 + $1.sessionCount }
            }
        }
    }

    /// Finds running `claude` processes and maps them to project directories via lsof
    private static func detectClaudeProcesses() -> [ActiveSession] {
        // Step 1: Get PIDs of running `claude` processes
        let pids = getClaudePIDs()
        guard !pids.isEmpty else { return [] }

        // Step 2: Get working directory for each PID
        var projectCounts: [String: Int] = [:]
        for pid in pids {
            if let cwd = getProcessCWD(pid: pid), !cwd.isEmpty {
                projectCounts[cwd, default: 0] += 1
            }
        }

        // Step 3: Build session list
        return projectCounts.map { (path, count) in
            ActiveSession(
                id: path,
                projectPath: path,
                projectName: URL(fileURLWithPath: path).lastPathComponent,
                sessionCount: count
            )
        }
        .sorted { $0.projectName.localizedCaseInsensitiveCompare($1.projectName) == .orderedAscending }
    }

    /// Get PIDs of all running `claude` processes using pgrep (exact match)
    private static func getClaudePIDs() -> [Int32] {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "claude"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        // pgrep exits 1 when no matches — not an error
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return output
            .components(separatedBy: "\n")
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? nil : Int32(trimmed)
            }
    }

    /// Get the current working directory of a process via lsof
    private static func getProcessCWD(pid: Int32) -> String? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-d", "cwd", "-p", "\(pid)", "-Fn"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        // lsof -Fn output: lines starting with 'n' contain the path
        // Last 'n' line is the cwd path
        let lines = output.components(separatedBy: "\n")
        if let lastPath = lines.last(where: { $0.hasPrefix("n/") }) {
            return String(lastPath.dropFirst()) // Remove 'n' prefix
        }

        return nil
    }
}
