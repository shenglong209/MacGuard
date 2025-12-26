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

    /// Bring app to front when about to show update dialog
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        bringToFront()
    }

    /// Bring app to front when showing update found window
    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        bringToFront()
    }

    // MARK: - Private

    private func bringToFront() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            // Also bring any Sparkle windows to front
            for window in NSApp.windows where window.isVisible {
                if String(describing: type(of: window)).contains("SPU") ||
                   window.title.contains("Update") ||
                   window.title.contains("update") {
                    window.makeKeyAndOrderFront(nil)
                    window.level = .floating
                    // Reset level after a moment
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        window.level = .normal
                    }
                }
            }
        }
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
