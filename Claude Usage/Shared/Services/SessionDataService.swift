//
//  SessionDataService.swift
//  Claude Usage
//
//  Reads Claude Code JSONL session files to extract per-session context window usage,
//  token counts, and metadata. Cross-references with ActiveSessionDetector for live status.
//

import Foundation
import Combine
import SwiftUI

// MARK: - Session Detail Model

struct SessionDetail: Identifiable, Equatable, Sendable {
    let id: String
    let slug: String
    let projectPath: String
    let projectName: String
    let gitBranch: String?
    let model: String
    let startTime: Date
    let lastActivityTime: Date
    let turnCount: Int
    let contextWindowTokens: Int
    let contextWindowLimit: Int
    let totalOutputTokens: Int
    let totalInputTokens: Int
    let toolUsage: [String: Int]
    let toolFiles: [String: [String]]
    var isActive: Bool

    var contextPercentage: Double {
        guard contextWindowLimit > 0 else { return 0 }
        return min(100, Double(contextWindowTokens) / Double(contextWindowLimit) * 100)
    }

    var duration: TimeInterval {
        lastActivityTime.timeIntervalSince(startTime)
    }

    var modelShortName: String {
        if model.contains("opus") { return "Opus" }
        if model.contains("sonnet") { return "Sonnet" }
        if model.contains("haiku") { return "Haiku" }
        return "Claude"
    }

    var contextColor: Color {
        let pct = contextPercentage
        if pct >= 90 { return .red }
        if pct >= 75 { return .orange }
        if pct >= 50 { return Color(nsColor: .systemYellow) }
        return .green
    }

    var modelColor: Color {
        switch modelShortName {
        case "Opus": return .purple
        case "Sonnet": return .blue
        case "Haiku": return .teal
        default: return .secondary
        }
    }

    /// Excluded internal/meta tools that aren't meaningful to surface
    private static let internalTools: Set<String> = ["ToolSearch"]

    var totalToolCalls: Int {
        toolUsage.filter { !Self.internalTools.contains($0.key) }.values.reduce(0, +)
    }

    /// Shared tool metadata for icons and display labels
    private static let toolMeta: [String: (label: String, icon: String)] = [
        "Read": ("Read", "doc.text"),
        "Edit": ("Edited", "pencil"),
        "Write": ("Written", "doc.badge.plus"),
        "Grep": ("Searched", "magnifyingglass"),
        "Glob": ("Globbed", "folder"),
        "Bash": ("Bash", "terminal"),
        "Agent": ("Agent", "person.2"),
        "LSP": ("LSP", "chevron.left.forwardslash.chevron.right"),
    ]

    /// Files grouped by tool, derived dynamically from toolFiles keys
    var filesByOperation: [(tool: String, label: String, icon: String, files: [String])] {
        // Preferred display order
        let order = ["Read", "Edit", "Write", "Grep", "Glob", "Bash", "Agent", "LSP"]
        return toolFiles
            .filter { !$0.value.isEmpty }
            .sorted { (order.firstIndex(of: $0.key) ?? Int.max) < (order.firstIndex(of: $1.key) ?? Int.max) }
            .map { tool, files in
                let meta = Self.toolMeta[tool] ?? (label: tool, icon: "wrench")
                return (tool: tool, label: meta.label, icon: meta.icon, files: files)
            }
    }

    var totalFilesTouched: Int {
        var allFiles = Set<String>()
        for (tool, files) in toolFiles where ["Read", "Edit", "Write"].contains(tool) {
            allFiles.formUnion(files)
        }
        return allFiles.count
    }

    private static let homePath: String = FileManager.default.homeDirectoryForCurrentUser.path

    /// Shorten a file path relative to the session's project path
    func shortenPath(_ path: String) -> String {
        if path.hasPrefix(projectPath) {
            let relative = String(path.dropFirst(projectPath.count))
            return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
        }
        if path.hasPrefix(Self.homePath) {
            return "~" + String(path.dropFirst(Self.homePath.count))
        }
        return path
    }

    /// Tool usage sorted by count descending, excluding internal tools
    var sortedToolUsage: [(name: String, count: Int)] {
        toolUsage
            .filter { !Self.internalTools.contains($0.key) }
            .sorted { $0.value > $1.value }
            .map { (name: $0.key, count: $0.value) }
    }

    var formattedDuration: String {
        let minutes = Int(duration / 60)
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 { return "\(hours)h" }
        return "\(hours)h \(remainingMinutes)m"
    }

    var timeAgo: String {
        let seconds = Date().timeIntervalSince(lastActivityTime)
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    static func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        } else if tokens >= 1_000 {
            return String(format: "%.1fK", Double(tokens) / 1_000)
        }
        return "\(tokens)"
    }

    nonisolated static func contextLimit(for model: String) -> Int {
        200_000
    }
}

// MARK: - Service

@MainActor
final class SessionDataService: ObservableObject {
    static let shared = SessionDataService()

    @Published private(set) var sessions: [SessionDetail] = []

    private var fileCache: [String: (modDate: Date, detail: SessionDetail)] = [:]
    private var scanTimer: Timer?
    private let scanInterval: TimeInterval = 15

    private init() {}

    // MARK: - Lifecycle

    func start() {
        scan()
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: scanInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scan()
            }
        }
    }

    func stop() {
        scanTimer?.invalidate()
        scanTimer = nil
    }

    // MARK: - Scanning

    private func scan() {
        let activeSessions = ActiveSessionDetector.shared.activeSessions
        let activeByEncoded: [String: Int] = Dictionary(
            activeSessions.map { ($0.projectPath.replacingOccurrences(of: "/", with: "-"), $0.sessionCount) },
            uniquingKeysWith: max
        )
        let cachedFiles = fileCache

        Task.detached(priority: .utility) {
            let result = SessionDataService.scanAllSessions(activeByEncoded: activeByEncoded, fileCache: cachedFiles)
            await MainActor.run { [weak self] in
                self?.fileCache = result.cache
                self?.sessions = result.sessions
            }
        }
    }

    // MARK: - Scan Result

    private struct ScanResult: Sendable {
        let sessions: [SessionDetail]
        let cache: [String: (modDate: Date, detail: SessionDetail)]
    }

    nonisolated private static func scanAllSessions(
        activeByEncoded: [String: Int],
        fileCache: [String: (modDate: Date, detail: SessionDetail)]
    ) -> ScanResult {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let projectsDir = homeDir.appendingPathComponent(".claude/projects")
        let fm = FileManager.default
        let recentCutoff = Date().addingTimeInterval(-2 * 3600)

        var newCache = [String: (modDate: Date, detail: SessionDetail)]()
        var allSessions: [SessionDetail] = []

        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return ScanResult(sessions: [], cache: [:])
        }

        for projectDir in projectDirs {
            guard projectDir.hasDirectoryPath else { continue }

            let encodedName = projectDir.lastPathComponent
            let activeCount = activeByEncoded[encodedName] ?? 0
            let isActiveProject = activeCount > 0

            guard let files = try? fm.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            ) else { continue }

            // Get JSONL files sorted by modification date (newest first)
            var jsonlWithDates: [(url: URL, modDate: Date)] = []
            for file in files where file.pathExtension == "jsonl" {
                guard let attrs = try? fm.attributesOfItem(atPath: file.path),
                      let modDate = attrs[.modificationDate] as? Date else { continue }
                jsonlWithDates.append((file, modDate))
            }
            jsonlWithDates.sort { $0.modDate > $1.modDate }

            // Only process recent files or files in active projects
            for (index, entry) in jsonlWithDates.enumerated() {
                let isActive = isActiveProject && index < activeCount
                guard entry.modDate > recentCutoff || isActive else { continue }

                let path = entry.url.path

                // Check cache
                if let cached = fileCache[path], cached.modDate == entry.modDate {
                    var detail = cached.detail
                    detail.isActive = isActive
                    newCache[path] = (entry.modDate, detail)
                    allSessions.append(detail)
                    continue
                }

                // Parse the file
                if var detail = parseJSONLFile(at: entry.url) {
                    detail.isActive = isActive
                    newCache[path] = (entry.modDate, detail)
                    allSessions.append(detail)
                }
            }
        }

        // Sort: active first, then by last activity (most recent first)
        allSessions.sort { a, b in
            if a.isActive != b.isActive { return a.isActive }
            return a.lastActivityTime > b.lastActivityTime
        }

        // Cap at 50 (popover shows fewer, dashboard shows all)
        if allSessions.count > 50 {
            allSessions = Array(allSessions.prefix(50))
        }

        return ScanResult(sessions: allSessions, cache: newCache)
    }

    // MARK: - JSONL Parsing

    nonisolated private static func parseJSONLFile(at url: URL) -> SessionDetail? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let fileSize = attrs[.size] as? UInt64 else { return nil }

        let content: String
        if fileSize > 5_000_000 {
            // Large file: read head + tail
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }

            let headData = handle.readData(ofLength: 20_000)
            let headStr = String(data: headData, encoding: .utf8) ?? ""

            let endOffset = handle.seekToEndOfFile()
            let tailStart = max(0, endOffset - 100_000)
            handle.seek(toFileOffset: tailStart)
            let tailData = handle.readData(ofLength: Int(endOffset - tailStart))
            let tailStr = String(data: tailData, encoding: .utf8) ?? ""

            content = headStr + "\n" + tailStr
        } else {
            guard let data = try? Data(contentsOf: url),
                  let str = String(data: data, encoding: .utf8) else { return nil }
            content = str
        }

        return parseContent(content, fileURL: url, estimateTurns: fileSize > 5_000_000, fileSize: Int(fileSize))
    }

    nonisolated private static func parseContent(
        _ content: String,
        fileURL: URL,
        estimateTurns: Bool,
        fileSize: Int
    ) -> SessionDetail? {
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        var slug: String?
        var cwd: String?
        var gitBranch: String?
        var startTime: Date?
        var lastTime: Date?
        var model: String?
        var contextTokens = 0
        var totalOutput = 0
        var totalInput = 0
        var turnCount = 0
        var toolCounts: [String: Int] = [:]
        var toolFileSets: [String: Set<String>] = [:]

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            let type = obj["type"] as? String

            // Metadata from earliest messages
            if cwd == nil, let c = obj["cwd"] as? String { cwd = c }
            if slug?.isEmpty != false, let s = obj["slug"] as? String, !s.isEmpty { slug = s }
            if gitBranch == nil, let b = obj["gitBranch"] as? String { gitBranch = b }

            // Timestamps
            if let ts = obj["timestamp"] as? String, let date = dateFormatter.date(from: ts) {
                if startTime == nil { startTime = date }
                lastTime = date
            }

            if type == "user" { turnCount += 1 }

            // Latest assistant usage (overwrites previous — we want the last one)
            if type == "assistant", let message = obj["message"] as? [String: Any] {
                if let m = message["model"] as? String { model = m }
                if let usage = message["usage"] as? [String: Any] {
                    let input = usage["input_tokens"] as? Int ?? 0
                    let cacheCreate = usage["cache_creation_input_tokens"] as? Int ?? 0
                    let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
                    let output = usage["output_tokens"] as? Int ?? 0

                    contextTokens = input + cacheCreate + cacheRead
                    totalInput += input + cacheCreate + cacheRead
                    totalOutput += output
                }

                // Extract tool usage and file paths from content blocks
                if let content = message["content"] as? [[String: Any]] {
                    for block in content {
                        if block["type"] as? String == "tool_use",
                           let toolName = block["name"] as? String {
                            toolCounts[toolName, default: 0] += 1

                            // Extract file paths from tool inputs
                            if let input = block["input"] as? [String: Any] {
                                if let filePath = input["file_path"] as? String {
                                    toolFileSets[toolName, default: []].insert(filePath)
                                } else if let path = input["path"] as? String {
                                    toolFileSets[toolName, default: []].insert(path)
                                }
                            }
                        }
                    }
                }
            }
        }

        guard let cwdPath = cwd else { return nil }

        if estimateTurns && turnCount < 5 && fileSize > 50_000 {
            turnCount = max(turnCount, fileSize / 2_000)
        }

        let projectName = URL(fileURLWithPath: cwdPath).lastPathComponent
        let limit = SessionDetail.contextLimit(for: model ?? "")

        return SessionDetail(
            id: fileURL.deletingPathExtension().lastPathComponent,
            slug: slug ?? "",
            projectPath: cwdPath,
            projectName: projectName,
            gitBranch: gitBranch,
            model: model ?? "unknown",
            startTime: startTime ?? Date(),
            lastActivityTime: lastTime ?? Date(),
            turnCount: turnCount,
            contextWindowTokens: contextTokens,
            contextWindowLimit: limit,
            totalOutputTokens: totalOutput,
            totalInputTokens: totalInput,
            toolUsage: toolCounts,
            toolFiles: toolFileSets.mapValues { Array($0).sorted() },
            isActive: false
        )
    }
}
