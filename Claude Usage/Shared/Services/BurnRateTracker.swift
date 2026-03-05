//
//  BurnRateTracker.swift
//  Claude Usage
//
//  Tracks usage snapshots over time to calculate burn rate and time-to-exhaustion.
//

import Foundation

/// A single point-in-time usage snapshot
struct UsageSnapshot {
    let timestamp: Date
    let sessionPercentage: Double
    let weeklyPercentage: Double
}

/// Computed burn rate metrics
struct BurnRateMetrics {
    /// Session burn rate in percentage points per minute
    let sessionRatePerMinute: Double
    /// Estimated minutes until session limit (nil if rate <= 0 or already at limit)
    let sessionMinutesRemaining: TimeInterval?
    /// Weekly burn rate in percentage points per hour
    let weeklyRatePerHour: Double
    /// Estimated hours until weekly limit (nil if rate <= 0)
    let weeklyHoursRemaining: TimeInterval?

    static let zero = BurnRateMetrics(
        sessionRatePerMinute: 0,
        sessionMinutesRemaining: nil,
        weeklyRatePerHour: 0,
        weeklyHoursRemaining: nil
    )

    var hasSessionRate: Bool { sessionRatePerMinute > 0.01 }
    var hasWeeklyRate: Bool { weeklyRatePerHour > 0.01 }
}

/// Tracks usage over time and computes burn rate metrics
@MainActor
final class BurnRateTracker {
    static let shared = BurnRateTracker()

    /// Ring buffer of recent snapshots per profile
    private var snapshots: [UUID: [UsageSnapshot]] = [:]

    /// Maximum snapshots to keep per profile (at 30s intervals, 30 = 15 minutes of history)
    private let maxSnapshots = 30

    private init() {}

    // MARK: - Recording

    /// Record a new usage snapshot for a profile
    func record(profileId: UUID, sessionPercentage: Double, weeklyPercentage: Double) {
        var profileSnapshots = snapshots[profileId] ?? []

        let snapshot = UsageSnapshot(
            timestamp: Date(),
            sessionPercentage: sessionPercentage,
            weeklyPercentage: weeklyPercentage
        )

        profileSnapshots.append(snapshot)

        // Trim to max size
        if profileSnapshots.count > maxSnapshots {
            profileSnapshots.removeFirst(profileSnapshots.count - maxSnapshots)
        }

        // Detect session reset (percentage dropped significantly)
        if profileSnapshots.count >= 2 {
            let prev = profileSnapshots[profileSnapshots.count - 2]
            if prev.sessionPercentage > 5 && snapshot.sessionPercentage < 1 {
                // Session reset — clear history so old data doesn't skew burn rate
                profileSnapshots = [snapshot]
            }
        }

        snapshots[profileId] = profileSnapshots
    }

    // MARK: - Calculation

    /// Calculate burn rate metrics for a profile
    func metrics(for profileId: UUID) -> BurnRateMetrics {
        guard let profileSnapshots = snapshots[profileId], profileSnapshots.count >= 3 else {
            return .zero
        }

        let latest = profileSnapshots.last!
        let oldest = profileSnapshots.first!

        let elapsedSeconds = latest.timestamp.timeIntervalSince(oldest.timestamp)
        guard elapsedSeconds > 10 else { return .zero } // Need at least 10 seconds of data

        let elapsedMinutes = elapsedSeconds / 60.0

        // Session burn rate (% per minute)
        let sessionDelta = latest.sessionPercentage - oldest.sessionPercentage
        let sessionRate = max(0, sessionDelta / elapsedMinutes)

        // Time remaining for session
        let sessionRemaining: TimeInterval? = {
            guard sessionRate > 0.01 else { return nil }
            let percentLeft = 100.0 - latest.sessionPercentage
            guard percentLeft > 0 else { return nil }
            return percentLeft / sessionRate // minutes
        }()

        // Weekly burn rate (% per hour)
        let weeklyDelta = latest.weeklyPercentage - oldest.weeklyPercentage
        let elapsedHours = elapsedSeconds / 3600.0
        let weeklyRate = max(0, elapsedHours > 0 ? weeklyDelta / elapsedHours : 0)

        // Time remaining for weekly
        let weeklyRemaining: TimeInterval? = {
            guard weeklyRate > 0.01 else { return nil }
            let percentLeft = 100.0 - latest.weeklyPercentage
            guard percentLeft > 0 else { return nil }
            return percentLeft / weeklyRate // hours
        }()

        return BurnRateMetrics(
            sessionRatePerMinute: sessionRate,
            sessionMinutesRemaining: sessionRemaining,
            weeklyRatePerHour: weeklyRate,
            weeklyHoursRemaining: weeklyRemaining
        )
    }

    /// Clear snapshots for a profile (e.g., on profile switch)
    func clear(profileId: UUID) {
        snapshots[profileId] = nil
    }

    /// Clear all snapshots
    func clearAll() {
        snapshots.removeAll()
    }
}
