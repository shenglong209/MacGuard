// ThemeConstants.swift
// MacGuard - Liquid Glass UI Theme
// Created: 2025-12-21

import SwiftUI

// MARK: - Theme Namespace

enum Theme {
    // MARK: - State Colors (semantic)

    enum StateColor {
        static let idle = Color.gray
        static let armed = Color.green
        static let triggered = Color.orange
        static let alarming = Color.red
    }

    // MARK: - Accent Colors

    enum Accent {
        static let primary = Color.blue
        static let success = Color.green
        static let warning = Color.orange
        static let danger = Color.red
        static let info = Color.blue
    }

    // MARK: - Background Opacities

    enum Opacity {
        static let surfaceSubtle: Double = 0.06
        static let surfaceHover: Double = 0.08
        static let surfaceActive: Double = 0.15
        static let overlayLight: Double = 0.35
        static let overlayMedium: Double = 0.50
        static let overlayHeavy: Double = 0.85
        static let overlayFull: Double = 0.95
    }

    // MARK: - Corner Radius

    enum CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 20
        static let xxxl: CGFloat = 24
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }
}

// MARK: - Shadow Modifiers

struct DropdownShadow: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(0.25), radius: 20, y: 8)
    }
}

struct ModalShadow: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(0.40), radius: 40, y: 20)
    }
}

struct IntenseShadow: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(0.50), radius: 50, y: 25)
    }
}

struct ButtonShadow: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content.shadow(color: color.opacity(0.40), radius: 8, y: 4)
    }
}

extension View {
    func dropdownShadow() -> some View {
        modifier(DropdownShadow())
    }

    func modalShadow() -> some View {
        modifier(ModalShadow())
    }

    func intenseShadow() -> some View {
        modifier(IntenseShadow())
    }

    func buttonShadow(color: Color = .black) -> some View {
        modifier(ButtonShadow(color: color))
    }
}
