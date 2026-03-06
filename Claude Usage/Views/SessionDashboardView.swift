//
//  SessionDashboardView.swift
//  Claude Usage
//
//  Full-window dashboard showing expanded session data, tool usage, and metrics.
//

import SwiftUI

struct SessionDashboardView: View {
    @StateObject private var sessionService = SessionDataService.shared
    @State private var selectedSessionId: String?
    @State private var searchText = ""
    @State private var isRefreshing = false

    private var filteredSessions: [SessionDetail] {
        if searchText.isEmpty { return sessionService.sessions }
        let query = searchText.lowercased()
        return sessionService.sessions.filter {
            $0.projectName.lowercased().contains(query) ||
            $0.slug.lowercased().contains(query) ||
            $0.model.lowercased().contains(query) ||
            ($0.gitBranch?.lowercased().contains(query) ?? false)
        }
    }

    private var activeSessions: [SessionDetail] {
        filteredSessions.filter { $0.isActive }
    }

    private var recentSessions: [SessionDetail] {
        filteredSessions.filter { !$0.isActive }
    }

    /// Resolve selected session from live data to avoid stale state after refreshes
    private var resolvedSession: SessionDetail? {
        guard let id = selectedSessionId else { return nil }
        return sessionService.sessions.first { $0.id == id }
    }

    var body: some View {
        HSplitView {
            sessionListPanel
                .frame(minWidth: 320, idealWidth: 380, maxWidth: 500)

            detailPanel
                .frame(minWidth: 400, idealWidth: 500)
        }
        .frame(minWidth: 780, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func openGeneralSettings() {
        NotificationCenter.default.post(name: .openSettings, object: SettingsSection.general)
    }

    // MARK: - Session List Panel

    private var sessionListPanel: some View {
        VStack(spacing: 0) {
            // Search bar + toolbar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                TextField("dashboard.search".localized, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Refresh button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) { isRefreshing = true }
                    sessionService.refresh()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        withAnimation(.easeInOut(duration: 0.3)) { isRefreshing = false }
                    }
                }) {
                    ZStack {
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
                .help("dashboard.refresh".localized)

                // Settings link
                Button(action: { openGeneralSettings() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("dashboard.open_settings".localized)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            statsBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 2, pinnedViews: [.sectionHeaders]) {
                    if !activeSessions.isEmpty {
                        Section {
                            ForEach(activeSessions) { session in
                                DashboardSessionRow(
                                    session: session,
                                    isSelected: selectedSessionId == session.id,
                                    onSelect: { selectedSessionId = session.id }
                                )
                                .id("\(session.id)-\(session.contextWindowTokens)-\(session.turnCount)")
                            }
                        } header: {
                            sectionHeader("dashboard.active".localized, count: activeSessions.count, color: .green)
                        }
                    }

                    if !recentSessions.isEmpty {
                        Section {
                            ForEach(recentSessions) { session in
                                DashboardSessionRow(
                                    session: session,
                                    isSelected: selectedSessionId == session.id,
                                    onSelect: { selectedSessionId = session.id }
                                )
                                .id("\(session.id)-\(session.contextWindowTokens)-\(session.turnCount)")
                            }
                        } header: {
                            sectionHeader("sessions.recent".localized, count: recentSessions.count, color: .secondary)
                        }
                    }

                    if filteredSessions.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("dashboard.no_sessions".localized)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)
            Text("\(count)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial)
    }

    private var statsBar: some View {
        HStack(spacing: 16) {
            StatChip(
                icon: "terminal.fill",
                label: "dashboard.stat_total".localized,
                value: "\(sessionService.sessions.count)",
                color: .blue
            )
            StatChip(
                icon: "bolt.fill",
                label: "dashboard.stat_active".localized,
                value: "\(activeSessions.count)",
                color: .green
            )

            let totalTools = sessionService.sessions.reduce(0) { $0 + $1.totalToolCalls }
            StatChip(
                icon: "wrench.fill",
                label: "dashboard.stat_tool_calls".localized,
                value: SessionDetail.formatTokens(totalTools),
                color: .orange
            )

            Spacer()
        }
    }

    // MARK: - Detail Panel

    @ViewBuilder
    private var detailPanel: some View {
        if let session = resolvedSession {
            SessionDetailPanel(session: session)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary.opacity(0.4))
                Text("dashboard.select_session".localized)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                Text("dashboard.select_hint".localized)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Stat Chip

private struct StatChip: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Dashboard Session Row

private struct DashboardSessionRow: View {
    let session: SessionDetail
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    private var displayName: String {
        if !session.slug.isEmpty { return session.slug }
        return session.projectName
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Circle()
                    .fill(session.isActive ? Color.green : Color.secondary.opacity(0.2))
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Text(session.modelShortName)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(session.modelColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(session.modelColor.opacity(0.12)))
                    }

                    HStack(spacing: 6) {
                        if !session.slug.isEmpty {
                            Text(session.projectName)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        if let branch = session.gitBranch, !branch.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 8))
                                Text(branch)
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.0f%%", session.contextPercentage))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(session.contextColor)
                    Text(session.isActive ? session.formattedDuration : session.timeAgo)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) :
                          isHovered ? Color.secondary.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Session Detail Panel

private struct SessionDetailPanel: View {
    let session: SessionDetail

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                detailHeader
                metricsGrid
                contextWindowSection

                if !session.sortedToolUsage.isEmpty {
                    toolUsageSection
                }

                if !session.filesByOperation.isEmpty {
                    filesTouchedSection
                }

                sessionInfoSection
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Detail Header

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if session.isActive {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .fill(Color.green.opacity(0.3))
                                    .frame(width: 14, height: 14)
                            )
                        Text("dashboard.active".localized)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green)
                    }
                }

                Text(session.modelShortName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(session.modelColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(session.modelColor.opacity(0.12))
                    )
            }

            Text(!session.slug.isEmpty ? session.slug : session.projectName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)

            HStack(spacing: 8) {
                if !session.slug.isEmpty {
                    Label(session.projectName, systemImage: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                if let branch = session.gitBranch, !branch.isEmpty {
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Metrics Grid

    private var metricsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            MetricCard(
                icon: "arrow.turn.down.right",
                title: "dashboard.metric_turns".localized,
                value: "\(session.turnCount)",
                color: .blue
            )
            MetricCard(
                icon: "clock.fill",
                title: "dashboard.metric_duration".localized,
                value: session.formattedDuration,
                color: .purple
            )
            MetricCard(
                icon: "wrench.fill",
                title: "dashboard.stat_tool_calls".localized,
                value: "\(session.totalToolCalls)",
                color: .orange
            )
            MetricCard(
                icon: "doc.on.doc",
                title: "dashboard.metric_files".localized,
                value: "\(session.totalFilesTouched)",
                color: .cyan
            )
        }
    }

    // MARK: - Context Window

    private var contextWindowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("dashboard.context_window".localized)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            VStack(spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.1))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [session.contextColor, session.contextColor.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geometry.size.width * CGFloat(session.contextPercentage / 100.0)))
                    }
                }
                .frame(height: 10)

                HStack {
                    Text("\(SessionDetail.formatTokens(session.contextWindowTokens)) / \(SessionDetail.formatTokens(session.contextWindowLimit))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(String(format: "%.1f%%", session.contextPercentage))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(session.contextColor)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
        }
    }

    // MARK: - Tool Usage

    private var toolUsageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("dashboard.tool_usage".localized)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text("dashboard.total_calls".localized(with: session.totalToolCalls))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            let tools = session.sortedToolUsage
            let maxCount = tools.first?.count ?? 1

            VStack(spacing: 6) {
                ForEach(tools, id: \.name) { tool in
                    ToolUsageRow(
                        name: tool.name,
                        count: tool.count,
                        maxCount: maxCount,
                        color: Self.toolColor(for: tool.name)
                    )
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
        }
    }

    // MARK: - Files Touched

    private var filesTouchedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("dashboard.files_touched".localized)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text("dashboard.files_count".localized(with: session.totalFilesTouched))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 12) {
                ForEach(session.filesByOperation, id: \.tool) { group in
                    FileOperationGroup(
                        operation: group.label,
                        icon: group.icon,
                        files: group.files,
                        color: Self.toolColor(for: group.tool),
                        shortenPath: session.shortenPath
                    )
                    .id("\(group.tool)-\(group.files.count)")
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
        }
    }

    static func toolColor(for name: String) -> Color {
        switch name {
        case "Read": return .blue
        case "Edit": return .orange
        case "Write": return .green
        case "Bash": return .red
        case "Grep": return .purple
        case "Glob": return .teal
        case "Agent": return .indigo
        case "LSP": return .mint
        default: return .secondary
        }
    }

    // MARK: - Session Info

    private var sessionInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("dashboard.session_info".localized)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            VStack(spacing: 0) {
                InfoRow(label: "dashboard.info_session_id".localized, value: session.id)
                Divider().padding(.horizontal, 12)
                InfoRow(label: "dashboard.info_model".localized, value: session.model)
                Divider().padding(.horizontal, 12)
                InfoRow(label: "dashboard.info_started".localized, value: Self.dateFormatter.string(from: session.startTime))
                Divider().padding(.horizontal, 12)
                InfoRow(label: "dashboard.info_last_activity".localized, value: Self.dateFormatter.string(from: session.lastActivityTime))
                Divider().padding(.horizontal, 12)
                InfoRow(label: "dashboard.info_project_path".localized, value: session.projectPath)
                Divider().padding(.horizontal, 12)
                InfoRow(label: "dashboard.info_input_tokens".localized, value: SessionDetail.formatTokens(session.totalInputTokens))
                Divider().padding(.horizontal, 12)
                InfoRow(label: "dashboard.info_output_tokens".localized, value: SessionDetail.formatTokens(session.totalOutputTokens))
            }
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

// MARK: - Metric Card

private struct MetricCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Tool Usage Row

private struct ToolUsageRow: View {
    let name: String
    let count: Int
    let maxCount: Int
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toolIcon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color)
                .frame(width: 16)

            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 50, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.08))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.6))
                        .frame(width: max(4, geometry.size.width * CGFloat(count) / CGFloat(maxCount)))
                }
            }
            .frame(height: 8)

            Text("\(count)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(count) calls")
    }

    private var toolIcon: String {
        switch name {
        case "Read": return "doc.text"
        case "Edit": return "pencil"
        case "Write": return "doc.badge.plus"
        case "Bash": return "terminal"
        case "Grep": return "magnifyingglass"
        case "Glob": return "folder"
        case "Agent": return "person.2"
        case "LSP": return "chevron.left.forwardslash.chevron.right"
        default: return "wrench"
        }
    }
}

// MARK: - File Operation Group

private struct FileOperationGroup: View {
    let operation: String
    let icon: String
    let files: [String]
    let color: Color
    let shortenPath: (String) -> String

    @State private var isExpanded = false

    private static let collapsedLimit = 5
    private static let expandedLimit = 200

    private var displayFiles: [String] {
        let limit = isExpanded ? Self.expandedLimit : Self.collapsedLimit
        return Array(files.prefix(limit))
    }

    private var hiddenCount: Int {
        let limit = isExpanded ? Self.expandedLimit : Self.collapsedLimit
        return max(0, files.count - limit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(color)
                        .frame(width: 16)

                    Text(operation)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("\(files.count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.1)))

                    Spacer()

                    if files.count > Self.collapsedLimit {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(displayFiles, id: \.self) { file in
                    Text(shortenPath(file))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(file)
                }

                if hiddenCount > 0 {
                    Text("dashboard.files_more".localized(with: hiddenCount))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(color.opacity(0.8))
                }
            }
            .padding(.leading, 22)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(operation): \(files.count) files")
    }
}

// MARK: - Info Row

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
