import SwiftUI

/// Smart, minimal, and professional popover interface
struct PopoverContentView: View {
    @ObservedObject var manager: MenuBarManager
    let onRefresh: () -> Void
    let onPreferences: () -> Void
    let onDashboard: () -> Void
    let onQuit: () -> Void

    @State private var isRefreshing = false
    @State private var showInsights = false
    @ObservedObject private var profileManager = ProfileManager.shared

    // Computed properties for multi-profile mode support
    private var displayUsage: ClaudeUsage {
        // In multi-profile mode, use the clicked profile's usage
        manager.clickedProfileUsage ?? manager.usage
    }

    private var displayAPIUsage: APIUsage? {
        manager.clickedProfileAPIUsage ?? manager.apiUsage
    }

    var body: some View {
        VStack(spacing: 0) {
            // Smart Header with Status and Profile Switcher
            SmartHeader(
                usage: displayUsage,
                status: manager.status,
                isRefreshing: isRefreshing,
                onRefresh: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isRefreshing = true
                    }
                    onRefresh()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isRefreshing = false
                        }
                    }
                },
                onManageProfiles: onPreferences,
                clickedProfileId: manager.clickedProfileId
            )

            // Scrollable content area
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    // Intelligent Usage Dashboard
                    SmartUsageDashboard(usage: displayUsage, apiUsage: displayAPIUsage)

                    // Sessions & Burn Rate
                    SessionsSection(burnRateMetrics: manager.burnRateMetrics)

                    // Contextual Insights
                    if showInsights {
                        ContextualInsights(usage: displayUsage)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                    }
                }
            }

            // Smart Footer with Actions
            SmartFooter(
                usage: displayUsage,
                status: manager.status,
                showInsights: $showInsights,
                onPreferences: onPreferences,
                onDashboard: onDashboard,
                onQuit: onQuit
            )
        }
        .frame(width: 380)
        .background(.regularMaterial)
    }
}

// MARK: - Profile Switcher Compact (for header)

struct ProfileSwitcherCompact: View {
    @ObservedObject private var profileManager = ProfileManager.shared
    @State private var isHovered = false
    let onManageProfiles: () -> Void

    var body: some View {
        Menu {
            ForEach(profileManager.profiles) { profile in
                Button(action: {
                    Task {
                        await profileManager.activateProfile(profile.id)
                    }
                }) {
                    HStack(spacing: 8) {
                        // Profile icon
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 12))

                        // Profile name
                        Text(profile.name)
                            .font(.system(size: 12, weight: .medium))

                        Spacer()

                        // Badges
                        HStack(spacing: 4) {
                            // CLI Account badge
                            if profile.hasCliAccount {
                                Image(systemName: "terminal.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.green)
                            }

                            // Claude.ai badge
                            if profile.claudeSessionKey != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.blue)
                            }

                            // Active indicator
                            if profile.id == profileManager.activeProfile?.id {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }

            Divider()

            Button(action: onManageProfiles) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                    Text("popover.manage_profiles".localized)
                        .font(.system(size: 12, weight: .medium))
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(profileManager.activeProfile?.name ?? "popover.no_profile".localized)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                // Status badges
                if profileManager.activeProfile?.hasCliAccount == true || profileManager.activeProfile?.claudeSessionKey != nil {
                    HStack(spacing: 3) {
                        if profileManager.activeProfile?.hasCliAccount == true {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 5, height: 5)
                        }
                        if profileManager.activeProfile?.claudeSessionKey != nil {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 5, height: 5)
                        }
                    }
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Profile Switcher Bar

struct ProfileSwitcherBar: View {
    @ObservedObject private var profileManager = ProfileManager.shared
    @State private var isHovered = false
    let onManageProfiles: () -> Void

    var body: some View {
        Menu {
            ForEach(profileManager.profiles) { profile in
                Button(action: {
                    Task {
                        await profileManager.activateProfile(profile.id)
                    }
                }) {
                    HStack(spacing: 8) {
                        // Profile icon
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 12))

                        // Profile name
                        Text(profile.name)
                            .font(.system(size: 12, weight: .medium))

                        Spacer()

                        // Badges
                        HStack(spacing: 4) {
                            // CLI Account badge
                            if profile.hasCliAccount {
                                Image(systemName: "terminal.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.green)
                            }

                            // Claude.ai badge
                            if profile.claudeSessionKey != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.blue)
                            }

                            // Active indicator
                            if profile.id == profileManager.activeProfile?.id {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }

            Divider()

            Button(action: onManageProfiles) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                    Text("popover.manage_profiles".localized)
                        .font(.system(size: 12, weight: .medium))
                }
            }
        } label: {
            HStack(spacing: 10) {
                // Profile avatar with gradient background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.8), Color.accentColor],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)

                    Text(profileInitials)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }

                // Profile info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(profileManager.activeProfile?.name ?? "popover.no_profile".localized)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        // Status badges
                        HStack(spacing: 3) {
                            if profileManager.activeProfile?.hasCliAccount == true {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 5, height: 5)
                            }
                            if profileManager.activeProfile?.claudeSessionKey != nil {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }

                    HStack(spacing: 4) {
                        if profileManager.profiles.count > 1 {
                            Text(String(format: "popover.profiles_count".localized, profileManager.profiles.count))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        } else {
                            Text("popover.profile_count_singular".localized)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        Text("•")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.5))

                        Text("common.switch".localized)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Chevron indicator
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.6))
                    .rotationEffect(.degrees(isHovered ? 180 : 0))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isHovered
                        ? Color.accentColor.opacity(0.08)
                        : Color(nsColor: .controlBackgroundColor).opacity(0.5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isHovered
                                ? Color.accentColor.opacity(0.3)
                                : Color.secondary.opacity(0.1),
                                lineWidth: 1
                            )
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }

    private var profileInitials: String {
        guard let name = profileManager.activeProfile?.name else { return "?" }
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        } else if let first = words.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }
}

// MARK: - Smart Header Component
struct SmartHeader: View {
    let usage: ClaudeUsage
    let status: ClaudeStatus
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onManageProfiles: () -> Void
    var clickedProfileId: UUID? = nil  // Profile ID that was clicked in multi-profile mode

    @ObservedObject private var profileManager = ProfileManager.shared

    private var statusColor: Color {
        switch status.indicator.color {
        case .green: return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .red: return .red
        case .gray: return .gray
        }
    }

    /// Check if we're in multi-profile mode
    private var isMultiProfileMode: Bool {
        profileManager.displayMode == .multi
    }

    /// Get the clicked profile (for multi-profile mode)
    private var clickedProfile: Profile? {
        guard let id = clickedProfileId else { return nil }
        return profileManager.profiles.first { $0.id == id }
    }

    /// Get initials from profile name
    private func profileInitials(for name: String) -> String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        } else if let first = words.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }

    var body: some View {
        HStack(spacing: 12) {
            // App Logo or Profile Initial
            HStack(spacing: 8) {
                if isMultiProfileMode, let profile = clickedProfile {
                    // Show profile initial in multi-profile mode - clean, minimal style
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                            .frame(width: 24, height: 24)

                        Text(profileInitials(for: profile.name))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                } else {
                    // Show app logo in single-profile mode
                    Image("HeaderLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                }

                VStack(alignment: .leading, spacing: 4) {
                    // Profile Switcher (always shown)
                    ProfileSwitcherCompact(onManageProfiles: onManageProfiles)

                    // Claude Status Badge
                    Button(action: {
                        if let url = URL(string: "https://status.claude.com") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 6, height: 6)

                            Text(status.description)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.primary.opacity(0.8))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(statusColor.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Click to open status.claude.com")
                }
            }

            Spacer()

            // Smart Refresh Button
            Button(action: onRefresh) {
                ZStack {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .foregroundColor(.secondary)
                .frame(width: 24, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        )
    }
}

// MARK: - Smart Usage Dashboard
struct SmartUsageDashboard: View {
    let usage: ClaudeUsage
    let apiUsage: APIUsage?
    @ObservedObject private var profileManager = ProfileManager.shared

    // Get the display mode from active profile's icon config
    private var showRemainingPercentage: Bool {
        profileManager.activeProfile?.iconConfig.showRemainingPercentage ?? false
    }

    // Check if API tracking is enabled globally
    private var isAPITrackingEnabled: Bool {
        DataStore.shared.loadAPITrackingEnabled()
    }

    var body: some View {
        VStack(spacing: 16) {
            // Primary Usage Card
            SmartUsageCard(
                title: "menubar.session_usage".localized,
                subtitle: "menubar.5_hour_window".localized,
                usedPercentage: usage.sessionPercentage,
                showRemaining: showRemainingPercentage,
                resetTime: usage.sessionResetTime,
                isPrimary: true
            )

            // Secondary Usage Cards
            HStack(spacing: 12) {
                SmartUsageCard(
                    title: "menubar.all_models".localized,
                    subtitle: "menubar.weekly".localized,
                    usedPercentage: usage.weeklyPercentage,
                    showRemaining: showRemainingPercentage,
                    resetTime: usage.weeklyResetTime,
                    isPrimary: false
                )

                if usage.opusWeeklyTokensUsed > 0 {
                    SmartUsageCard(
                        title: "menubar.opus_usage".localized,
                        subtitle: "menubar.weekly".localized,
                        usedPercentage: usage.opusWeeklyPercentage,
                        showRemaining: showRemainingPercentage,
                        resetTime: nil,
                        isPrimary: false
                    )
                }

                if usage.sonnetWeeklyTokensUsed > 0 {
                    SmartUsageCard(
                        title: "menubar.sonnet_usage".localized,
                        subtitle: "menubar.weekly".localized,
                        usedPercentage: usage.sonnetWeeklyPercentage,
                        showRemaining: showRemainingPercentage,
                        resetTime: usage.sonnetWeeklyResetTime,
                        isPrimary: false
                    )
                }
            }

            if let used = usage.costUsed, let limit = usage.costLimit, let currency = usage.costCurrency, limit > 0 {
                let usedPercentage = (used / limit) * 100.0
                SmartUsageCard(
                    title: "menubar.extra_usage".localized,
                    subtitle: String(format: "%.2f / %.2f %@", used / 100.0, limit / 100.0, currency),
                    usedPercentage: usedPercentage,
                    showRemaining: showRemainingPercentage,
                    resetTime: nil,
                    isPrimary: false
                )
            }

            // API Usage Card (only if tracking is enabled AND profile has credentials)
            if isAPITrackingEnabled,
               let apiUsage = apiUsage,
               let profile = profileManager.activeProfile,
               profile.hasAPIConsole {
                APIUsageCard(apiUsage: apiUsage, showRemaining: showRemainingPercentage)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Smart Usage Card
struct SmartUsageCard: View {
    let title: String
    let subtitle: String
    let usedPercentage: Double
    let showRemaining: Bool
    let resetTime: Date?
    let isPrimary: Bool

    /// Display percentage based on mode
    private var displayPercentage: Double {
        UsageStatusCalculator.getDisplayPercentage(
            usedPercentage: usedPercentage,
            showRemaining: showRemaining
        )
    }

    /// Status level based on display mode
    private var statusLevel: UsageStatusLevel {
        UsageStatusCalculator.calculateStatus(
            usedPercentage: usedPercentage,
            showRemaining: showRemaining
        )
    }

    /// Color based on status level
    private var statusColor: Color {
        switch statusLevel {
        case .safe: return .green
        case .moderate: return .orange
        case .critical: return .red
        }
    }

    private var statusIcon: String {
        switch statusLevel {
        case .safe: return "checkmark.circle.fill"
        case .moderate: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.circle.fill"
        }
    }

    var body: some View {
        VStack(spacing: isPrimary ? 12 : 8) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: isPrimary ? 13 : 11, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.system(size: isPrimary ? 10 : 9, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Status indicator
                HStack(spacing: 4) {
                    Image(systemName: statusIcon)
                        .font(.system(size: isPrimary ? 12 : 10, weight: .medium))
                        .foregroundColor(statusColor)

                    Text("\(Int(displayPercentage))%")
                        .font(.system(size: isPrimary ? 16 : 14, weight: .bold, design: .monospaced))
                        .foregroundColor(statusColor)
                }
            }

            // Progress visualization
            VStack(spacing: 6) {
                // Animated progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [statusColor, statusColor.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * min(displayPercentage / 100.0, 1.0))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .animation(.easeInOut(duration: 0.8), value: displayPercentage)
                    }
                }
                .frame(height: 8)

                // Reset time information
                if let reset = resetTime {
                    HStack {
                        Spacer()
                        Text("menubar.resets_time".localized(with: reset.resetTimeString()))
                            .font(.system(size: isPrimary ? 9 : 8, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(isPrimary ? 16 : 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        )
    }
}

// MARK: - Contextual Insights
struct ContextualInsights: View {
    let usage: ClaudeUsage

    private var insights: [Insight] {
        var result: [Insight] = []

        // Session insights
        if usage.sessionPercentage > 80 {
            result.append(Insight(
                icon: "exclamationmark.triangle.fill",
                color: .orange,
                title: "usage.high_session".localized,
                description: "usage.high_session.desc".localized
            ))
        }

        // Weekly insights
        if usage.weeklyPercentage > 90 {
            result.append(Insight(
                icon: "clock.fill",
                color: .red,
                title: "usage.weekly_approaching".localized,
                description: "usage.weekly_approaching.desc".localized
            ))
        }

        // Efficiency insights
        if usage.sessionPercentage < 20 && usage.weeklyPercentage < 30 {
            result.append(Insight(
                icon: "checkmark.circle.fill",
                color: .green,
                title: "usage.efficient".localized,
                description: "usage.efficient.desc".localized
            ))
        }

        return result
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(insights, id: \.title) { insight in
                HStack(spacing: 10) {
                    Image(systemName: insight.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(insight.color)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(insight.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)

                        Text(insight.description)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(insight.color.opacity(0.08))
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct Insight {
    let icon: String
    let color: Color
    let title: String
    let description: String
}

// MARK: - Smart Footer
struct SmartFooter: View {
    let usage: ClaudeUsage
    let status: ClaudeStatus
    @Binding var showInsights: Bool
    let onPreferences: () -> Void
    let onDashboard: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 16)

            // Action buttons
            HStack(spacing: 8) {
                SmartActionButton(
                    icon: "rectangle.split.3x1.fill",
                    title: "dashboard.title".localized,
                    action: onDashboard
                )

                SmartActionButton(
                    icon: "gearshape.fill",
                    title: "common.settings".localized,
                    action: onPreferences
                )

                SmartActionButton(
                    icon: "power",
                    title: "common.quit".localized,
                    isDestructive: true,
                    action: onQuit
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Claude Status Row
struct ClaudeStatusRow: View {
    let status: ClaudeStatus
    @State private var isHovered = false

    private var statusColor: Color {
        switch status.indicator.color {
        case .green: return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .red: return .red
        case .gray: return .gray
        }
    }

    var body: some View {
        Button(action: {
            if let url = URL(string: "https://status.claude.com") {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack(spacing: 8) {
                // Status indicator dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                // Status text
                Text(status.description)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                // External link icon
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.secondary.opacity(0.05) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .help("Click to open status.claude.com")
    }
}

// MARK: - Smart Action Button
struct SmartActionButton: View {
    let icon: String
    let title: String
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDestructive ? .red : .secondary)
                    .frame(width: 14)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDestructive ? .red : .primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isHovered
                        ? (isDestructive ? Color.red.opacity(0.1) : Color.accentColor.opacity(0.1))
                        : Color.clear
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Burn Rate Section
// MARK: - Pulsing Live Dot
struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.3))
                .frame(width: 12, height: 12)
                .scaleEffect(isPulsing ? 1.4 : 1.0)
                .opacity(isPulsing ? 0 : 0.6)

            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Sessions Section (Rich Context Window Tracking)

struct SessionsSection: View {
    let burnRateMetrics: BurnRateMetrics
    @StateObject private var sessionService = SessionDataService.shared
    @StateObject private var detector = ActiveSessionDetector.shared
    @State private var showAll = false

    private var activeSessions: [SessionDetail] {
        sessionService.sessions.filter { $0.isActive }
    }

    private var recentSessions: [SessionDetail] {
        sessionService.sessions.filter { !$0.isActive }
    }

    private var hasContent: Bool {
        !sessionService.sessions.isEmpty || !detector.activeSessions.isEmpty || burnRateMetrics.hasSessionRate
    }

    private var activeCount: Int {
        max(activeSessions.count, detector.totalProcessCount)
    }

    var body: some View {
        if hasContent {
            VStack(spacing: 10) {
                // Header
                SessionsSectionHeader(
                    activeCount: activeCount,
                    burnRateMetrics: burnRateMetrics
                )

                // Active session cards
                if !activeSessions.isEmpty {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 1)

                    let visible = showAll ? activeSessions : Array(activeSessions.prefix(3))
                    ForEach(visible) { session in
                        SessionCard(session: session)
                    }
                } else if !detector.activeSessions.isEmpty {
                    // Fallback: show basic active sessions while JSONL data loads
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 1)

                    ForEach(detector.activeSessions.prefix(3)) { session in
                        BasicSessionRow(session: session)
                    }
                }

                // Recent sessions
                if !recentSessions.isEmpty {
                    if !activeSessions.isEmpty || !detector.activeSessions.isEmpty {
                        HStack(spacing: 6) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.1))
                                .frame(height: 1)
                            Text("sessions.recent".localized)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.6))
                            Rectangle()
                                .fill(Color.secondary.opacity(0.1))
                                .frame(height: 1)
                        }
                    }

                    let visibleRecent = showAll ? recentSessions : Array(recentSessions.prefix(2))
                    ForEach(visibleRecent) { session in
                        SessionCard(session: session)
                    }
                }

                // Show more / less toggle
                let totalCount = sessionService.sessions.count
                if totalCount > 3 {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAll.toggle()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text(showAll ? "sessions.show_less".localized : "sessions.show_all".localized(with: totalCount))
                                .font(.system(size: 10, weight: .medium))
                            Image(systemName: showAll ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .foregroundColor(.secondary.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .opacity
            ))
        }
    }
}

// MARK: - Sessions Section Header

private struct SessionsSectionHeader: View {
    let activeCount: Int
    let burnRateMetrics: BurnRateMetrics

    private var burnRateColor: Color {
        guard let mins = burnRateMetrics.sessionMinutesRemaining else { return .orange }
        if mins < 15 { return .red }
        if mins < 30 { return .orange }
        return Color(nsColor: .systemYellow)
    }

    private var timeRemainingText: String? {
        guard let mins = burnRateMetrics.sessionMinutesRemaining else { return nil }
        let capped = min(mins, 300)
        if capped >= 300 { return "5h+ left" }
        if capped < 60 { return String(format: "~%.0fm left", capped) }
        let h = Int(capped / 60)
        let m = Int(capped.truncatingRemainder(dividingBy: 60))
        return "~\(h)h \(m)m left"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("sessions.title".localized)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)

                if activeCount > 0 {
                    Text("sessions.active_count".localized(with: activeCount))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Burn rate chip with time remaining
            if burnRateMetrics.hasSessionRate {
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9, weight: .medium))
                        Text(String(format: "%.1f%%/min", burnRateMetrics.sessionRatePerMinute))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(burnRateColor)

                    if let remaining = timeRemainingText {
                        HStack(spacing: 2) {
                            Image(systemName: "hourglass")
                                .font(.system(size: 7, weight: .medium))
                            Text(remaining)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(burnRateColor.opacity(0.7))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(burnRateColor.opacity(0.08))
                )
            }

            if activeCount > 0 {
                PulsingDot()
            }
        }
    }
}

// MARK: - Session Card (Rich)

private struct SessionCard: View {
    let session: SessionDetail
    @State private var isHovered = false

    private var displayName: String {
        if !session.slug.isEmpty {
            return session.slug
        }
        return session.projectName
    }

    private var subtitle: String {
        var parts: [String] = []
        if !session.slug.isEmpty {
            parts.append(session.projectName)
        }
        if let branch = session.gitBranch, !branch.isEmpty {
            parts.append(branch)
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        Button(action: {
            NSWorkspace.shared.open(URL(fileURLWithPath: session.projectPath))
        }) {
            VStack(alignment: .leading, spacing: 6) {
                // Row 1: Status dot + Name + Model badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(session.isActive ? Color.green : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)

                    Text(displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(session.isActive ? .primary : .primary.opacity(0.6))
                        .lineLimit(1)

                    Spacer()

                    Text(session.modelShortName)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(session.modelColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(session.modelColor.opacity(0.12))
                        )
                }

                // Row 2: Project + Branch (if slug is shown as name)
                if !subtitle.isEmpty {
                    HStack(spacing: 0) {
                        Spacer().frame(width: 12) // align with name above
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.7))
                            .lineLimit(1)
                    }
                }

                // Row 3: Context window progress bar
                HStack(spacing: 0) {
                    Spacer().frame(width: 12)
                    VStack(spacing: 4) {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.secondary.opacity(0.12))

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        LinearGradient(
                                            colors: [session.contextColor, session.contextColor.opacity(0.7)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(0, geometry.size.width * CGFloat(session.contextPercentage / 100.0)))
                                    .animation(.easeInOut(duration: 0.6), value: session.contextPercentage)
                            }
                        }
                        .frame(height: 6)

                        // Token counts + percentage
                        HStack {
                            Text("\(SessionDetail.formatTokens(session.contextWindowTokens)) / \(SessionDetail.formatTokens(session.contextWindowLimit))")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.7))

                            Spacer()

                            Text(String(format: "%.0f%%", session.contextPercentage))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(session.contextColor)
                        }
                    }
                }

                // Row 4: Metadata (turns, duration, time ago)
                HStack(spacing: 0) {
                    Spacer().frame(width: 12)
                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 8, weight: .medium))
                            Text("\(session.turnCount) turns")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(.secondary.opacity(0.65))

                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.system(size: 8, weight: .medium))
                            Text(session.formattedDuration)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(.secondary.opacity(0.65))

                        if !session.isActive {
                            HStack(spacing: 3) {
                                Image(systemName: "moon.fill")
                                    .font(.system(size: 8, weight: .medium))
                                Text(session.timeAgo)
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundColor(.secondary.opacity(0.55))
                        }

                        if session.compactionCount > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.trianglehead.2.clockwise")
                                    .font(.system(size: 8, weight: .medium))
                                Text("\(session.compactionCount)×")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(.orange.opacity(0.7))
                            .help("sessions.compaction_tooltip".localized(with: session.autoCompactions, session.manualCompactions))
                        }

                        Spacer()
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.secondary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Basic Session Row (Fallback while JSONL loads)

private struct BasicSessionRow: View {
    let session: ActiveSession
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            NSWorkspace.shared.open(URL(fileURLWithPath: session.projectPath))
        }) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)

                Image(systemName: "folder.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isHovered ? .green : .secondary.opacity(0.5))
                    .frame(width: 12)

                Text(session.projectName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isHovered ? .primary : .primary.opacity(0.85))
                    .lineLimit(1)

                Spacer()

                if session.sessionCount > 1 {
                    Text("\(session.sessionCount)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.green.opacity(0.12))
                        )
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.secondary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - API Usage Card
struct APIUsageCard: View {
    let apiUsage: APIUsage
    let showRemaining: Bool

    /// Display percentage based on mode
    private var displayPercentage: Double {
        UsageStatusCalculator.getDisplayPercentage(
            usedPercentage: apiUsage.usagePercentage,
            showRemaining: showRemaining
        )
    }

    /// Status level based on display mode
    private var statusLevel: UsageStatusLevel {
        UsageStatusCalculator.calculateStatus(
            usedPercentage: apiUsage.usagePercentage,
            showRemaining: showRemaining
        )
    }

    /// Color based on status level
    private var usageColor: Color {
        switch statusLevel {
        case .safe: return .green
        case .moderate: return .orange
        case .critical: return .red
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("menubar.api_credits".localized)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("menubar.anthropic_console".localized)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Percentage
                Text("\(Int(displayPercentage))%")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(usageColor)
            }

            // Progress Bar
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1))

                // Fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(usageColor)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(x: displayPercentage / 100.0, y: 1.0, anchor: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 8)

            // Used / Remaining
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("menubar.used".localized)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(apiUsage.formattedUsed)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("menubar.remaining".localized)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(apiUsage.formattedRemaining)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                }
            }

            // Reset Time
            if apiUsage.resetsAt > Date() {
                HStack {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)

                    Text("menubar.resets_time".localized(with: apiUsage.resetsAt.formatted(.relative(presentation: .named))))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(usageColor.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
