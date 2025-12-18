// CountdownWindowController.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-18

import SwiftUI
import AppKit

/// Custom window that can become key even when borderless
class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Controller for the fullscreen countdown overlay window
/// Uses a persistent window that's shown/hidden to avoid cleanup crashes
class CountdownWindowController {
    private var window: KeyableWindow?
    private var hostingController: NSHostingController<CountdownContainerView>?
    private var viewModel = CountdownViewModel()

    /// Show the fullscreen overlay
    func show(alarmManager: AlarmStateManager) {
        // Update view model with current manager
        viewModel.alarmManager = alarmManager

        if window == nil {
            createWindow()
        }

        // Show the window
        if let screen = NSScreen.main {
            window?.setFrame(screen.frame, display: true)
        }

        // Force activation and key window status
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        print("[Overlay] Countdown overlay shown")
    }

    /// Hide the overlay (does not destroy window)
    func hide() {
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        print("[Overlay] Countdown overlay hidden")
    }

    private func createWindow() {
        let view = CountdownContainerView(viewModel: viewModel)
        hostingController = NSHostingController(rootView: view)

        window = KeyableWindow(
            contentRect: NSScreen.main?.frame ?? .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window?.contentViewController = hostingController
        window?.level = .screenSaver
        window?.backgroundColor = NSColor.black.withAlphaComponent(0.85)
        window?.isOpaque = false
        window?.ignoresMouseEvents = false
        window?.acceptsMouseMovedEvents = true
    }
}

/// Observable view model to pass alarm manager without recreating views
class CountdownViewModel: ObservableObject {
    @Published var alarmManager: AlarmStateManager?
}

/// Container view that observes the view model
struct CountdownContainerView: View {
    @ObservedObject var viewModel: CountdownViewModel

    var body: some View {
        if let manager = viewModel.alarmManager {
            CountdownOverlayView(alarmManager: manager)
        } else {
            Color.clear
        }
    }
}
