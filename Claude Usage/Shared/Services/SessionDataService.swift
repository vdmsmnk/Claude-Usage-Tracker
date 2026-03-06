//
//  SessionDataService.swift
//  Claude Usage
//
//  Reads Claude Code JSONL session files to extract per-session context window usage,
//  token counts, and metadata. Cross-references with ActiveSessionDetector for live status.
//

import Foundation
import Combine

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

        // Cap at 10
        if allSessions.count > 10 {
            allSessions = Array(allSessions.prefix(10))
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

            let headData = handle.readData(ofLength: 10_000)
            let headStr = String(data: headData, encoding: .utf8) ?? ""

            let endOffset = handle.seekToEndOfFile()
            let tailStart = max(0, endOffset - 30_000)
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
        var turnCount = 0

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
                    totalOutput += output
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
            isActive: false
        )
    }
}
