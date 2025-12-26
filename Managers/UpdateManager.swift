// UpdateManager.swift
// MacGuard - Anti-Theft Alarm for macOS

import SwiftUI
import Sparkle

/// Manages Sparkle auto-update functionality
final class UpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    /// Shared instance for app-wide access
    static let shared = UpdateManager()

    /// Sparkle updater controller
    private var updaterController: SPUStandardUpdaterController!

    /// Whether update check is available (not already in progress)
    @Published var canCheckForUpdates = false

    private override init() {
        super.init()

        // Initialize updater with self as delegate
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )

        // Bind canCheckForUpdates to updater state
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    // MARK: - SPUStandardUserDriverDelegate

    /// Bring app to front when showing update found dialog
    @objc func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Public Methods

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
