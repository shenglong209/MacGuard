// GlassButtonStyles.swift
// MacGuard - Liquid Glass UI Theme
// Created: 2025-12-21

import SwiftUI

// MARK: - Primary Button Style (Capsule, Prominent)

struct GlassPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.primary)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.md)
            .background {
                Capsule()
                    .fill(.clear)
                    .background(
                        VisualEffectView(
                            material: .hudWindow,
                            blendingMode: .withinWindow,
                            isEmphasized: configuration.isPressed
                        )
                    )
                    .clipShape(Capsule())
            }
            .glassCapsuleBorder(prominent: true)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.5)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Secondary Button Style (Rounded Rect, Subtle)

struct GlassSecondaryButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = Theme.CornerRadius.sm

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .foregroundStyle(.primary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs + 2)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.clear)
                    .background(
                        VisualEffectView(
                            material: .hudWindow,
                            blendingMode: .withinWindow,
                            isEmphasized: configuration.isPressed
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
            .glassBorder(cornerRadius: cornerRadius)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Menu Row Button Style

struct GlassMenuRowButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isHovered || configuration.isPressed {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                        .fill(.clear)
                        .background(
                            VisualEffectView(
                                material: .selection,
                                blendingMode: .withinWindow,
                                isEmphasized: configuration.isPressed
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm))
                }
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

// MARK: - Pill Button Style (Compact Capsule)

struct GlassPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background {
                Capsule()
                    .fill(.clear)
                    .background(
                        VisualEffectView(
                            material: .hudWindow,
                            blendingMode: .withinWindow,
                            isEmphasized: configuration.isPressed
                        )
                    )
                    .clipShape(Capsule())
            }
            .glassCapsuleBorder()
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Icon Button Style (Circle)

struct GlassIconButtonStyle: ButtonStyle {
    var size: CGFloat = 32

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.5))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(.clear)
                    .background(
                        VisualEffectView(
                            material: .selection,
                            blendingMode: .withinWindow,
                            isEmphasized: configuration.isPressed
                        )
                    )
                    .clipShape(Circle())
            }
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
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - State-Colored Primary Button

struct GlassStateButtonStyle: ButtonStyle {
    let state: AlarmState

    var stateColor: Color {
        switch state {
        case .idle: return Theme.StateColor.idle
        case .armed: return Theme.StateColor.armed
        case .triggered: return Theme.StateColor.triggered
        case .alarming: return Theme.StateColor.alarming
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.md)
            .background {
                ZStack {
                    Capsule()
                        .fill(stateColor)

                    // Glass overlay
                    Capsule()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.25), location: 0.0),
                                    .init(color: .clear, location: 0.5),
                                    .init(color: .black.opacity(0.15), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .glassCapsuleBorder(prominent: true)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .shadow(color: stateColor.opacity(0.4), radius: 8, y: 4)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Bordered Prominent Glass Button (replacement for system .borderedProminent)

struct GlassBorderedProminentButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background {
                ZStack {
                    Capsule()
                        .fill(tint)

                    // Glass overlay
                    Capsule()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.20), location: 0.0),
                                    .init(color: .clear, location: 0.5),
                                    .init(color: .black.opacity(0.10), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .glassCapsuleBorder(prominent: true)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.5)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
