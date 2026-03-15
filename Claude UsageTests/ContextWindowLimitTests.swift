import XCTest
@testable import Claude_Usage

final class ContextWindowLimitTests: XCTestCase {

    // MARK: - Known Model Families

    func testOpusModels() {
        XCTAssertEqual(Constants.SessionLimits.contextWindowLimit(for: "claude-opus-4-6"), 1_000_000)
        XCTAssertEqual(Constants.SessionLimits.contextWindowLimit(for: "claude-opus-4-5-20250514"), 1_000_000)
    }

    func testSonnetModels() {
        XCTAssertEqual(Constants.SessionLimits.contextWindowLimit(for: "claude-sonnet-4-6"), 200_000)
        XCTAssertEqual(Constants.SessionLimits.contextWindowLimit(for: "claude-sonnet-4-5-20250514"), 200_000)
        XCTAssertEqual(Constants.SessionLimits.contextWindowLimit(for: "claude-3-5-sonnet-20241022"), 200_000)
    }

    func testHaikuModels() {
        XCTAssertEqual(Constants.SessionLimits.contextWindowLimit(for: "claude-haiku-4-5-20251001"), 200_000)
        XCTAssertEqual(Constants.SessionLimits.contextWindowLimit(for: "claude-3-5-haiku-20241022"), 200_000)
    }

    // MARK: - Case Insensitivity

    func testCaseInsensitive() {
        XCTAssertEqual(Constants.SessionLimits.contextWindowLimit(for: "Claude-OPUS-4-6"), 1_000_000)
        XCTAssertEqual(Constants.SessionLimits.contextWindowLimit(for: "SONNET"), 200_000)
        XCTAssertEqual(Constants.SessionLimits.contextWindowLimit(for: "Haiku"), 200_000)
    }

    // MARK: - Fallback

    func testUnknownModelFallsBackToDefault() {
        let fallback = Constants.SessionLimits.defaultContextWindowLimit
        XCTAssertEqual(Constants.SessionLimits.contextWindowLimit(for: "unknown"), fallback)
        XCTAssertEqual(Constants.SessionLimits.contextWindowLimit(for: ""), fallback)
        XCTAssertEqual(Constants.SessionLimits.contextWindowLimit(for: "some-future-model"), fallback)
    }

    func testDefaultMatchesExpectedValue() {
        XCTAssertEqual(Constants.SessionLimits.defaultContextWindowLimit, 200_000)
    }
}
