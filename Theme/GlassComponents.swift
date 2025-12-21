// GlassComponents.swift
// MacGuard - Liquid Glass UI Theme
// Created: 2025-12-21

import SwiftUI

// MARK: - Glass Background (Regular Variant)

/// Regular liquid glass background for navigation, controls, menus
/// High blur + luminosity adjustment
struct GlassBackground: View {
    var material: NSVisualEffectView.Material = .menu
    var cornerRadius: CGFloat = Theme.CornerRadius.lg
    var showBorder: Bool = true

    var body: some View {
        ZStack {
            // Base material
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.clear)
                .background(
                    VisualEffectView(
                        material: material,
                        blendingMode: .withinWindow,
                        isEmphasized: true
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

            // Depth gradient overlay
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.08), location: 0.0),
                            .init(color: .clear, location: 0.5),
                            .init(color: .black.opacity(0.05), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .allowsHitTesting(false)
        }
        .overlay {
            if showBorder {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.20), location: 0.0),
                                .init(color: .white.opacity(0.08), location: 0.3),
                                .init(color: .clear, location: 0.5),
                                .init(color: .black.opacity(0.08), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
        }
    }
}

// MARK: - Clear Glass Background (Over Media/Content)

/// Clear liquid glass for media overlays, immersive content
/// Minimal blur, highly translucent
struct ClearGlassBackground: View {
    var overBrightContent: Bool = false
    var cornerRadius: CGFloat = Theme.CornerRadius.lg
    var showBorder: Bool = true

    var body: some View {
        ZStack {
            // Dimming layer for bright backgrounds
            if overBrightContent {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.black.opacity(0.35))
            }

            // Lighter material
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.clear)
                .background(
                    VisualEffectView(
                        material: .sheet,
                        blendingMode: .withinWindow,
                        isEmphasized: false
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

            // Minimal depth gradient
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.06), location: 0.0),
                            .init(color: .black.opacity(0.04), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .allowsHitTesting(false)
        }
        .overlay {
            if showBorder {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.15), location: 0.0),
                                .init(color: .clear, location: 0.5),
                                .init(color: .black.opacity(0.06), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
        }
    }
}

// MARK: - Glass Section Container

/// Container for settings sections with glass background
struct GlassSection<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if let title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            content()
        }
        .padding(Theme.Spacing.lg)
        .background {
            GlassBackground(
                material: .headerView,
                cornerRadius: Theme.CornerRadius.lg
            )
        }
    }
}

// MARK: - Glass Card

/// Prominent glass card for modals, overlays
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = Theme.CornerRadius.xxxl
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background {
                GlassBackground(
                    material: .hudWindow,
                    cornerRadius: cornerRadius
                )
                .modalShadow()
            }
    }
}

// MARK: - Full Screen Glass Background

/// Full-screen glass overlay for countdown/alarm states
struct FullScreenGlass: View {
    var body: some View {
        VisualEffectView(
            material: .fullScreenUI,
            blendingMode: .withinWindow,
            isEmphasized: true
        )
        .ignoresSafeArea()
    }
}

// MARK: - Glass Icon Circle

/// Circular glass background for icons
struct GlassIconCircle: View {
    var size: CGFloat = 32
    var material: NSVisualEffectView.Material = .selection

    var body: some View {
        Circle()
            .fill(.clear)
            .background(
                VisualEffectView(
                    material: material,
                    blendingMode: .withinWindow
                )
            )
            .clipShape(Circle())
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.15), location: 0.0),
                                .init(color: .clear, location: 0.5),
                                .init(color: .black.opacity(0.08), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
    }
}
