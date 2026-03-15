# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a native macOS menu bar app (Swift/SwiftUI, macOS 14.0+). No SPM/CocoaPods — dependencies are managed via Xcode's built-in Swift Package Manager.

```bash
# Open in Xcode
open "Claude Usage.xcodeproj"
# Build and run: Cmd+R in Xcode

# CLI build (no code signing, matches CI)
xcodebuild build \
  -project "Claude Usage.xcodeproj" \
  -scheme "Claude Usage" \
  -configuration Debug \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Run tests
xcodebuild test \
  -project "Claude Usage.xcodeproj" \
  -scheme "Claude Usage" \
  -configuration Debug \
  -derivedDataPath build \
  -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Tests are in `Claude UsageTests/` — small unit test suite covering validators, date extensions, URL building, and usage calculations.

## Architecture

**Menu bar-only app** — no main window. Entry point is `ClaudeUsageTrackerApp` (`@main`) with `AppDelegate` handling lifecycle. The app runs as `.accessory` (no dock icon).

### Startup Flow
`AppDelegate.applicationDidFinishLaunching` -> `ProfileManager.loadProfiles()` -> check credentials -> either show `SetupWizardView` or create `MenuBarManager.setup()`.

### Key Singletons (all `@MainActor` where applicable)
- **`MenuBarManager`** — Central coordinator. Owns the popover, settings/dashboard windows, and orchestrates refresh cycles. Delegates to `StatusBarUIManager` for rendering menu bar icons and `UsageRefreshCoordinator` for API polling.
- **`ProfileManager`** — Manages multiple Claude accounts (profiles). Each profile has isolated credentials, appearance settings, and refresh intervals. Publishes `activeProfile` and `displayMode` (single vs multi-profile menu bar).
- **`DataStore`** / **`ProfileStore`** — Persistence via `UserDefaults`. `DataStore` handles usage data and settings; `ProfileStore` handles profile CRUD. Credentials go through `KeychainService`.
- **`ClaudeAPIService`** — Fetches usage data from `claude.ai/api/organizations/{org}/usage` (web) and `api.anthropic.com` (console). Supports three auth modes: session cookie, CLI OAuth bearer token, and console API session.
- **`SessionDataService`** — Parses Claude Code JSONL session files (`~/.claude/projects/`) to extract per-session context window usage, token counts, tool usage, and file operations. Scans every 15 seconds on a background thread.
- **`ActiveSessionDetector`** — Detects running `claude` processes via `ps` and maps them to project directories. Polls every 10 seconds.
- **`BurnRateTracker`** — Tracks usage snapshots over time to calculate burn rate (% per minute/hour) and time-to-exhaustion estimates.

### UI Layer
- **`PopoverContentView`** — Main popover shown when clicking the menu bar icon. Contains usage cards, session list, burn rate display.
- **`SessionDashboardView`** — Separate window with split-pane session browser (list + detail panel). Shows context window usage, tool usage breakdown, and file operations per session.
- **`SettingsView`** — Sidebar-based settings with per-profile tabs (credentials, appearance, general) and app-wide tabs (manage profiles, language, Claude Code statusline, updates, about).
- **`SetupWizardView`** — First-run 3-step wizard for credential configuration.

### Data Flow for Usage Refresh
`UsageRefreshCoordinator` timer fires -> `ClaudeAPIService.fetchUsageData()` -> result published on `MenuBarManager` (`@Published usage`, `apiUsage`) -> `StatusBarUIManager` re-renders menu bar icons via `MenuBarIconRenderer` -> `PopoverContentView` observes `MenuBarManager` via `@ObservedObject`.

### Multi-Profile System
Profiles are stored as `[Profile]` in UserDefaults via `ProfileStore`. Each profile can have separate Claude.ai session key, API key, organization ID, and CLI OAuth credentials. `ProfileDisplayMode` controls whether the menu bar shows one icon (active profile) or multiple icons (all profiles). `StatusBarUIManager` manages `NSStatusItem` instances per mode.

## SwiftUI Gotchas in This Codebase

- **`.buttonStyle(.plain)` hit testing**: Only opaque content (text, icons) is clickable — empty space (Spacer, padding) is not. Always add `.contentShape(Rectangle())` to the button's label container to make the full area tappable.
- **`LazyVStack` row caching**: Rows may not re-render when `@Published` data changes if the `Identifiable.id` stays the same. Use compound `.id()` modifiers (e.g., `.id("\(session.id)-\(session.contextWindowTokens)")`) to force re-render when key data changes.

## Localization

8 languages supported. Strings are in `Claude Usage/Shared/Localization/` managed by `LanguageManager` and `LocalizationManager`. When adding user-facing strings, use the localization system.

## CI

GitHub Actions on push/PR to `main` — builds Debug + Release (no code signing) and runs tests on macOS 15 with Xcode 26.
