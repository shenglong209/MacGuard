// GlassModifiers.swift
// MacGuard - Liquid Glass UI Theme
// Created: 2025-12-21

import SwiftUI

// MARK: - Glass Border Modifier

struct GlassBorder: ViewModifier {
    let cornerRadius: CGFloat
    var prominent: Bool = false

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(borderGradient, lineWidth: 0.5)
        )
    }

    private var borderGradient: LinearGradient {
        if prominent {
            return LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.25), location: 0.0),
                    .init(color: .white.opacity(0.12), location: 0.2),
                    .init(color: .clear, location: 0.4),
                    .init(color: .black.opacity(0.12), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.20), location: 0.0),
                    .init(color: .white.opacity(0.08), location: 0.3),
                    .init(color: .clear, location: 0.5),
                    .init(color: .black.opacity(0.08), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

extension View {
    /// Apply glass border with gradient highlight
    func glassBorder(cornerRadius: CGFloat = 8, prominent: Bool = false) -> some View {
        modifier(GlassBorder(cornerRadius: cornerRadius, prominent: prominent))
    }
}

// MARK: - Glass Capsule Border (for buttons)

struct GlassCapsuleBorder: ViewModifier {
    var prominent: Bool = false

    func body(content: Content) -> some View {
        content.overlay(
            Capsule()
                .strokeBorder(borderGradient, lineWidth: 0.5)
        )
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(prominent ? 0.25 : 0.20), location: 0.0),
                .init(color: .white.opacity(prominent ? 0.12 : 0.08), location: 0.3),
                .init(color: .clear, location: 0.5),
                .init(color: .black.opacity(prominent ? 0.12 : 0.08), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension View {
    func glassCapsuleBorder(prominent: Bool = false) -> some View {
        modifier(GlassCapsuleBorder(prominent: prominent))
    }
}

// MARK: - Glass Background Modifier

extension View {
    /// Apply glass background with material
    func glassBackground(
        material: NSVisualEffectView.Material = .menu,
        cornerRadius: CGFloat = Theme.CornerRadius.lg
    ) -> some View {
        self.background {
            GlassBackground(material: material, cornerRadius: cornerRadius)
        }
    }

    /// Apply clear glass background (for media overlays)
    func clearGlassBackground(
        overBrightContent: Bool = false,
        cornerRadius: CGFloat = Theme.CornerRadius.lg
    ) -> some View {
        self.background {
            ClearGlassBackground(
                overBrightContent: overBrightContent,
                cornerRadius: cornerRadius
            )
        }
    }
}
