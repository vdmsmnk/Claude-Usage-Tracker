import SwiftUI
import Charts

// MARK: - Always-active vibrancy background
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let container = NSView()

        // Base vibrancy layer
        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.isEmphasized = true
        effectView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(effectView)

        // Solid tint overlay for more density
        let tintView = NSView()
        tintView.wantsLayer = true
        if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        } else {
            tintView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.4).cgColor
        }
        tintView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tintView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: container.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            tintView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: container.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Update tint for appearance changes
        if let tintView = nsView.subviews.last {
            tintView.wantsLayer = true
            if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
            } else {
                tintView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.4).cgColor
            }
        }
    }
}

/// Native macOS popover interface - minimal, flat, system-style
struct PopoverContentView: View {
    @ObservedObject var manager: MenuBarManager
    let onRefresh: () -> Void
    let onPreferences: () -> Void
    let onDashboard: () -> Void
    let onQuit: () -> Void

    @State private var isRefreshing = false
    @State private var showInsights = false
    @ObservedObject private var profileManager = ProfileManager.shared

    private func profileInitials(for name: String) -> String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        } else if let first = words.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }

    // Computed properties for multi-profile mode support
    private var displayUsage: ClaudeUsage {
        manager.clickedProfileUsage ?? manager.usage
    }

    private var displayAPIUsage: APIUsage? {
        // When viewing a non-active profile, use only that profile's API data
        // to avoid leaking the active profile's console data
        if manager.clickedProfileUsage != nil {
            return manager.clickedProfileAPIUsage
        }
        return manager.apiUsage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
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
                onPreferences: onPreferences,
                clickedProfileId: manager.clickedProfileId
            )

            PopoverDivider()

            // Error / stale data banners
            if manager.hasCredentialError {
                StatusBannerView(
                    icon: "exclamationmark.triangle.fill",
                    message: "popover.banner.credentials_expired".localized,
                    color: .orange
                ) {
                    onPreferences()
                }
            } else if manager.consecutiveRefreshFailures >= 3 {
                StatusBannerView(
                    icon: "arrow.clockwise.circle.fill",
                    message: String(format: "popover.banner.refresh_failed".localized, manager.consecutiveRefreshFailures),
                    color: .yellow
                ) {
                    onRefresh()
                }
            } else if let lastRefresh = manager.lastSuccessfulRefreshTime,
                      Date().timeIntervalSince(lastRefresh) > 300 {
                let minutesAgo = Int(Date().timeIntervalSince(lastRefresh) / 60)
                StatusBannerView(
                    icon: "clock.fill",
                    message: String(format: "popover.banner.updated_ago".localized, minutesAgo),
                    color: .orange
                ) {
                    onRefresh()
                }
            }

            // Viewing usage tag (shown in multi-profile mode)
            if profileManager.displayMode == .multi,
               let viewingProfile = manager.clickedProfileId.flatMap({ id in
                   profileManager.profiles.first(where: { $0.id == id })
               }) ?? profileManager.activeProfile {
                HStack(spacing: 8) {
                    // Profile initials avatar
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 20, height: 20)

                        Text(profileInitials(for: viewingProfile.name))
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(.accentColor)
                    }

                    Text(viewingProfile.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    if viewingProfile.id == profileManager.activeProfile?.id {
                        Text("Active")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.12))
                            )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.03))
                )
                .padding(.horizontal, 10)
                .padding(.top, 6)
            }

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
        .background(VisualEffectBackground())
    }
}

// MARK: - Native Divider

struct PopoverDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 16)
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
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 12))

                        Text(profile.name)
                            .font(.system(size: 12, weight: .medium))

                        Spacer()

                        HStack(spacing: 4) {
                            if profile.hasCliAccount {
                                Image(systemName: "terminal.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.adaptiveGreen)
                            }

                            if profile.claudeSessionKey != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.blue)
                            }

                            if profile.id == profileManager.activeProfile?.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
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
            Text(profileManager.activeProfile?.name ?? "popover.no_profile".localized)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
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
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 12))

                        Text(profile.name)
                            .font(.system(size: 12, weight: .medium))

                        Spacer()

                        HStack(spacing: 4) {
                            if profile.hasCliAccount {
                                Image(systemName: "terminal.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.adaptiveGreen)
                            }

                            if profile.claudeSessionKey != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.blue)
                            }

                            if profile.id == profileManager.activeProfile?.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
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
            HStack(spacing: 8) {
                // Profile avatar
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 28, height: 28)

                    Text(profileInitials)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(profileManager.activeProfile?.name ?? "popover.no_profile".localized)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

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
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.5))

                        Text("common.switch".localized)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
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
    let onPreferences: () -> Void
    var clickedProfileId: UUID? = nil

    @ObservedObject private var profileManager = ProfileManager.shared

    private var statusColor: Color {
        switch status.indicator.color {
        case .green: return .adaptiveGreen
        case .yellow: return .yellow
        case .orange: return .orange
        case .red: return .red
        case .gray: return .gray
        }
    }

    private var isMultiProfileMode: Bool {
        profileManager.displayMode == .multi
    }

    private var clickedProfile: Profile? {
        guard let id = clickedProfileId else { return nil }
        return profileManager.profiles.first { $0.id == id }
    }

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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                ProfileSwitcherCompact(onManageProfiles: onManageProfiles)

                // Status
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
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("Click to open status.claude.com")
            }

            Spacer()

            HStack(alignment: .center, spacing: 2) {
                // Refresh
                HeaderIconButton(
                    icon: "arrow.clockwise",
                    isRefreshing: isRefreshing,
                    action: onRefresh
                )
                .disabled(isRefreshing)

                // Settings
                HeaderIconButton(
                    icon: "gearshape.fill",
                    fontSize: 12,
                    action: onPreferences
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Header Icon Button
struct HeaderIconButton: View {
    let icon: String
    var fontSize: CGFloat = 10.5
    var isRefreshing: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 10, height: 10)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: fontSize, weight: .medium))
                        .imageScale(.medium)
                }
            }
            .foregroundColor(isHovered ? .primary : .secondary)
            .frame(width: 24, height: 24, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Smart Usage Dashboard
struct SmartUsageDashboard: View {
    let usage: ClaudeUsage
    let apiUsage: APIUsage?
    @ObservedObject private var profileManager = ProfileManager.shared

    private var showRemainingPercentage: Bool {
        profileManager.activeProfile?.iconConfig.showRemainingPercentage ?? false
    }

    private var showTimeMarker: Bool {
        if profileManager.displayMode == .multi {
            return profileManager.multiProfileConfig.showTimeMarker
        }
        return profileManager.activeProfile?.iconConfig.showTimeMarker ?? true
    }

    private var usePaceColoring: Bool {
        if profileManager.displayMode == .multi {
            return profileManager.multiProfileConfig.usePaceColoring
        }
        return profileManager.activeProfile?.iconConfig.usePaceColoring ?? true
    }

    private var showPaceMarker: Bool {
        if profileManager.displayMode == .multi {
            return profileManager.multiProfileConfig.showPaceMarker
        }
        return profileManager.activeProfile?.iconConfig.showPaceMarker ?? true
    }

    private var timeDisplay: PopoverTimeDisplay {
        SharedDataStore.shared.loadPopoverTimeDisplay()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Primary: Session Usage
            UsageRow(
                title: "menubar.session_usage".localized,
                subtitle: "menubar.5_hour_window".localized,
                usedPercentage: usage.effectiveSessionPercentage,
                showRemaining: showRemainingPercentage,
                resetTime: usage.sessionResetTime,
                periodDuration: Constants.sessionWindow,
                showTimeMarker: showTimeMarker,
                showPaceMarker: showPaceMarker,
                usePaceColoring: usePaceColoring,
                timeDisplay: timeDisplay
            )

            // All Models (Weekly)
            UsageRow(
                title: "menubar.all_models".localized,
                tag: "menubar.weekly".localized,
                subtitle: nil,
                usedPercentage: usage.weeklyPercentage,
                showRemaining: showRemainingPercentage,
                resetTime: usage.weeklyResetTime,
                periodDuration: Constants.weeklyWindow,
                showTimeMarker: showTimeMarker,
                showPaceMarker: showPaceMarker,
                usePaceColoring: usePaceColoring,
                timeDisplay: timeDisplay
            )

            if usage.opusWeeklyTokensUsed > 0 {
                UsageRow(
                    title: "menubar.opus_usage".localized,
                    tag: "menubar.weekly".localized,
                    subtitle: nil,
                    usedPercentage: usage.opusWeeklyPercentage,
                    showRemaining: showRemainingPercentage,
                    resetTime: nil,
                    periodDuration: nil
                )
            }

            if usage.sonnetWeeklyTokensUsed > 0 {
                UsageRow(
                    title: "menubar.sonnet_usage".localized,
                    subtitle: nil,
                    usedPercentage: usage.sonnetWeeklyPercentage,
                    showRemaining: showRemainingPercentage,
                    resetTime: usage.sonnetWeeklyResetTime,
                    periodDuration: nil,
                    timeDisplay: timeDisplay
                )
            }

            // Extra usage (cost-based)
            if let used = usage.costUsed, let limit = usage.costLimit, let currency = usage.costCurrency, limit > 0 {
                let usedPercentage = (used / limit) * 100.0
                UsageRow(
                    title: "menubar.extra_usage".localized,
                    subtitle: String(format: "%.2f / %.2f %@", used / 100.0, limit / 100.0, currency),
                    usedPercentage: usedPercentage,
                    showRemaining: showRemainingPercentage,
                    resetTime: nil,
                    periodDuration: nil
                )

                // Overage credit grant balance
                if let balance = usage.overageBalance, let balanceCurrency = usage.overageBalanceCurrency {
                    HStack {
                        Text("popover.overage_balance".localized)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.2f %@", balance / 100.0, balanceCurrency.uppercased()))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.adaptiveGreen)
                    }
                }
            }

            // API Usage
            if let apiUsage = apiUsage {
                APIUsageCard(apiUsage: apiUsage, showRemaining: showRemainingPercentage, timeDisplay: timeDisplay)

                // API Cost Card (only if cost data is available)
                if let costCents = apiUsage.apiTokenCostCents, costCents > 0 {
                    APICostCard(apiUsage: apiUsage)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Usage Row (flat, native style)
struct UsageRow: View {
    let title: String
    var tag: String? = nil
    let subtitle: String?
    let usedPercentage: Double
    let showRemaining: Bool
    let resetTime: Date?
    let periodDuration: TimeInterval?
    var showTimeMarker: Bool = true
    var showPaceMarker: Bool = true
    var usePaceColoring: Bool = true
    var timeDisplay: PopoverTimeDisplay = .resetTime

    private var displayPercentage: Double {
        UsageStatusCalculator.getDisplayPercentage(
            usedPercentage: usedPercentage,
            showRemaining: showRemaining
        )
    }

    private var rawElapsedFraction: Double? {
        UsageStatusCalculator.elapsedFraction(
            resetTime: resetTime,
            duration: periodDuration ?? 0,
            showRemaining: false
        )
    }

    private var timeMarkerFraction: CGFloat? {
        guard showTimeMarker, let f = rawElapsedFraction else { return nil }
        return CGFloat(showRemaining ? 1.0 - f : f)
    }

    private var paceStatus: PaceStatus? {
        guard showPaceMarker, let elapsed = rawElapsedFraction else { return nil }
        return PaceStatus.calculate(usedPercentage: usedPercentage, elapsedFraction: elapsed)
    }

    private var timeMarkerColor: Color {
        if let pace = paceStatus {
            return pace.swiftUIColor
        }
        return Color(nsColor: .labelColor)
    }

    private var statusLevel: UsageStatusLevel {
        UsageStatusCalculator.calculateStatus(
            usedPercentage: usedPercentage,
            showRemaining: showRemaining,
            elapsedFraction: usePaceColoring ? rawElapsedFraction : nil
        )
    }

    private var statusColor: Color {
        switch statusLevel {
        case .safe: return .adaptiveGreen
        case .moderate: return .orange
        case .critical: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Title row with percentage
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)

                        if let tag = tag {
                            Text(tag)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule()
                                        .fill(Color.primary.opacity(0.08))
                                )
                        }
                    }

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Text("\(Int(displayPercentage))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(statusColor)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.primary.opacity(0.08))

                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(statusColor)
                        .frame(width: geometry.size.width * min(displayPercentage / 100.0, 1.0))
                        .animation(.easeInOut(duration: 0.6), value: displayPercentage)
                }
                .overlay(alignment: .leading) {
                    if let fraction = timeMarkerFraction {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(timeMarkerColor)
                            .frame(width: 2.5, height: 8)
                            .offset(x: round(geometry.size.width * fraction) - 0.75)
                    }
                }
            }
            .frame(height: 4)

            // Reset time
            if let reset = resetTime {
                Text(resetTimeText(for: reset))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    private func resetTimeText(for reset: Date) -> String {
        switch timeDisplay {
        case .resetTime:
            return "menubar.resets_time".localized(with: reset.resetTimeString())
        case .remainingTime:
            return "menubar.resets_in".localized(with: reset.timeRemainingString())
        case .both:
            return "menubar.resets_both".localized(with: reset.timeRemainingString(), reset.resetTimeString())
        }
    }
}

// MARK: - Contextual Insights
struct ContextualInsights: View {
    let usage: ClaudeUsage

    private var insights: [Insight] {
        var result: [Insight] = []

        if usage.effectiveSessionPercentage > 80 {
            result.append(Insight(
                icon: "exclamationmark.triangle.fill",
                color: .orange,
                title: "usage.high_session".localized,
                description: "usage.high_session.desc".localized
            ))
        }

        if usage.weeklyPercentage > 90 {
            result.append(Insight(
                icon: "clock.fill",
                color: .red,
                title: "usage.weekly_approaching".localized,
                description: "usage.weekly_approaching.desc".localized
            ))
        }

        if usage.effectiveSessionPercentage < 20 && usage.weeklyPercentage < 30 {
            result.append(Insight(
                icon: "checkmark.circle.fill",
                color: .adaptiveGreen,
                title: "usage.efficient".localized,
                description: "usage.efficient.desc".localized
            ))
        }

        return result
    }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(insights, id: \.title) { insight in
                HStack(spacing: 8) {
                    Image(systemName: insight.icon)
                        .font(.system(size: 11))
                        .foregroundColor(insight.color)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(insight.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)

                        Text(insight.description)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 4)
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
        case .green: return .adaptiveGreen
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
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(status.description)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .help("Click to open status.claude.com")
    }
}

// MARK: - Smart Action Button (kept for backward compatibility)
struct SmartActionButton: View {
    let icon: String
    let title: String
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 12)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isDestructive ? .red : (isHovered ? .primary : .secondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
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

// MARK: - API Cost Card
struct APICostCard: View {
    let apiUsage: APIUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("API Cost")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    Text("This Month")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Total cost
                if let formatted = apiUsage.formattedAPICost {
                    Text(formatted)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                }
            }

            // Daily cost chart
            DailyCostChart(dailyCosts: apiUsage.sortedDailyCosts, currency: apiUsage.currency)

            // Per-key breakdown (if multiple sources) or flat model list
            if apiUsage.hasMultipleSources {
                VStack(spacing: 6) {
                    ForEach(apiUsage.sortedCostSources) { source in
                        APICostSourceRow(source: source, currency: apiUsage.currency)
                    }
                }
            } else {
                // Single source or no source data — show flat model breakdown
                let models = apiUsage.sortedModelCosts
                if !models.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(models, id: \.model) { item in
                            HStack {
                                Text(item.model)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)

                                Spacer()

                                Text(item.cost)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }
}

// MARK: - Daily Cost Chart
struct DailyCostChart: View {
    let dailyCosts: [(date: Date, cents: Double)]
    let currency: String

    private struct DayCost: Identifiable {
        let id: Date
        let dollars: Double
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private var xDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let today = Date()
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: today))!
        // End of today (start of tomorrow)
        let endOfToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: today))!
        return startOfMonth ... endOfToday
    }

    var body: some View {
        if !dailyCosts.isEmpty {
            let data = dailyCosts.map { DayCost(id: $0.date, dollars: $0.cents / 100.0) }
            let maxValue = data.map(\.dollars).max() ?? 0
            Chart(data) { item in
                BarMark(
                    x: .value("Day", item.id, unit: .day),
                    y: .value("Cost", item.dollars),
                    width: .fixed(12)
                )
                .foregroundStyle(Color.orange.opacity(0.75))
                .cornerRadius(2)
            }
            .chartXScale(domain: xDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(centered: true) {
                        if let date = value.as(Date.self) {
                            Text("\(Calendar.current.component(.day, from: date))")
                                .font(.system(size: 7))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                        .foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(formatDollars(v, max: maxValue))
                                .font(.system(size: 7, design: .rounded))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                }
            }
            .chartYScale(domain: 0 ... max(maxValue * 1.15, 0.01))
            .frame(height: 80)
        }
    }

    private func formatDollars(_ amount: Double, max: Double) -> String {
        if max >= 100 {
            return "$\(Int(amount))"
        } else if max >= 1 {
            return String(format: "$%.1f", amount)
        } else {
            return String(format: "$%.2f", amount)
        }
    }
}

// MARK: - API Cost Source Row
struct APICostSourceRow: View {
    let source: APICostSource
    let currency: String
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 4) {
            // Source header (tappable to expand)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: source.sourceType.icon)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 12)

                    Text(source.keyName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text(source.formattedTotal(currency: currency))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.6))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.06))
                )
            }
            .buttonStyle(.plain)

            // Expanded model breakdown
            if isExpanded {
                let models = source.sortedModelCosts(currency: currency)
                VStack(spacing: 3) {
                    ForEach(models, id: \.model) { item in
                        HStack {
                            Text(item.model)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)

                            Spacer()

                            Text(item.cost)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.leading, 24)
                .padding(.trailing, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - API Usage Card
struct APIUsageCard: View {
    let apiUsage: APIUsage
    let showRemaining: Bool
    var timeDisplay: PopoverTimeDisplay = .resetTime

    private var displayPercentage: Double {
        UsageStatusCalculator.getDisplayPercentage(
            usedPercentage: apiUsage.usagePercentage,
            showRemaining: showRemaining
        )
    }

    private var statusLevel: UsageStatusLevel {
        UsageStatusCalculator.calculateStatus(
            usedPercentage: apiUsage.usagePercentage,
            showRemaining: showRemaining
        )
    }

    private var usageColor: Color {
        switch statusLevel {
        case .safe: return .adaptiveGreen
        case .moderate: return .orange
        case .critical: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("menubar.api_credits".localized)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    Text("menubar.anthropic_console".localized)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(Int(displayPercentage))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(usageColor)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.primary.opacity(0.08))

                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(usageColor)
                        .frame(width: geometry.size.width * min(displayPercentage / 100.0, 1.0))
                        .animation(.easeInOut(duration: 0.6), value: displayPercentage)
                }
            }
            .frame(height: 4)

            // Used / Remaining
            HStack {
                Text(apiUsage.formattedUsed)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                Text(apiUsage.formattedRemaining)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            // Reset Time
            if apiUsage.resetsAt > Date() {
                Text(resetTimeText(for: apiUsage.resetsAt))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    private func resetTimeText(for reset: Date) -> String {
        switch timeDisplay {
        case .resetTime:
            return "menubar.resets_time".localized(with: reset.resetTimeString())
        case .remainingTime:
            return "menubar.resets_in".localized(with: reset.timeRemainingString())
        case .both:
            return "menubar.resets_both".localized(with: reset.timeRemainingString(), reset.resetTimeString())
        }
    }
}

// MARK: - Status Banner View
struct StatusBannerView: View {
    let icon: String
    let message: String
    let color: Color
    var onTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .cornerRadius(6)
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .onTapGesture { onTap?() }
    }
}
