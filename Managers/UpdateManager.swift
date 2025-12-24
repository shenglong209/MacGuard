// UpdateManager.swift
// MacGuard - Anti-Theft Alarm for macOS

import SwiftUI
import Sparkle

/// Manages Sparkle auto-update functionality
final class UpdateManager: ObservableObject {
    /// Shared instance for app-wide access
    static let shared = UpdateManager()

    /// Sparkle updater controller
    private let updaterController: SPUStandardUpdaterController

    /// Whether update check is available (not already in progress)
    @Published var canCheckForUpdates = false

    private init() {
        // Initialize updater - starts automatic checking
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Bind canCheckForUpdates to updater state
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Trigger manual update check (user-initiated, shows dialog even if no update)
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Silent background update check (only shows UI if update available)
    func checkForUpdatesInBackground() {
        updaterController.updater.checkForUpdatesInBackground()
    }

    /// Access to underlying updater for advanced usage
    var updater: SPUUpdater {
        updaterController.updater
    }
}
