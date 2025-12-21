// VisualEffectView.swift
// MacGuard - Liquid Glass UI Theme
// Created: 2025-12-21

import SwiftUI
import AppKit

/// NSVisualEffectView wrapper for SwiftUI
/// Provides blur materials for liquid glass backporting to macOS 13+
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    var isEmphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = isEmphasized
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.isEmphasized = isEmphasized
    }
}

// MARK: - Convenience Initializers

extension VisualEffectView {
    /// Menu dropdown material
    static var menu: VisualEffectView {
        VisualEffectView(material: .menu, blendingMode: .withinWindow, isEmphasized: true)
    }

    /// Selection highlight material
    static var selection: VisualEffectView {
        VisualEffectView(material: .selection, blendingMode: .withinWindow, isEmphasized: true)
    }

    /// Header/section material
    static var header: VisualEffectView {
        VisualEffectView(material: .headerView, blendingMode: .withinWindow)
    }

    /// HUD window material (dark, prominent)
    static var hud: VisualEffectView {
        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow, isEmphasized: true)
    }

    /// Full-screen UI material (immersive)
    static var fullScreen: VisualEffectView {
        VisualEffectView(material: .fullScreenUI, blendingMode: .withinWindow, isEmphasized: true)
    }

    /// Sidebar material
    static var sidebar: VisualEffectView {
        VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
    }
}
