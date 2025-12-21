# Phase 2: Glass Background Components

**Goal:** Create reusable glass background views and section containers.

---

## 2.1 GlassComponents.swift

```swift
// Theme/GlassComponents.swift

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
```

---

## 2.2 View Modifier Extensions

Add to `GlassModifiers.swift`:

```swift
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
```

---

## Usage Examples

### Menu Dropdown
```swift
VStack(spacing: 0) {
    // menu items
}
.padding(.vertical, 8)
.background {
    GlassBackground(material: .menu, cornerRadius: 10)
        .dropdownShadow()
}
```

### Settings Section
```swift
GlassSection(title: "Security") {
    Toggle("Lock screen when armed", isOn: $lockScreen)
    Toggle("Lid close alarm", isOn: $lidCloseAlarm)
}
```

### Countdown Card
```swift
GlassCard(cornerRadius: 24) {
    VStack(spacing: 24) {
        Text("\(countdown)")
            .font(.system(size: 120, weight: .bold, design: .rounded))
        Text("Touch ID or PIN to disarm")
    }
    .padding(48)
}
```

---

## Verification

1. Test `GlassBackground` renders blur effect in preview
2. Test `GlassSection` wraps content correctly
3. Verify glass border gradient visible on light/dark backgrounds
4. Test `FullScreenGlass` covers entire screen
