# Phase 1: Theme Foundation

**Goal:** Create the foundational theme system for liquid glass effects.

---

## 1.1 Create Theme Directory

```bash
mkdir -p MacGuard/Theme
```

---

## 1.2 VisualEffectView.swift

NSViewRepresentable wrapper for `NSVisualEffectView`.

```swift
// Theme/VisualEffectView.swift

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
}
```

---

## 1.3 GlassModifiers.swift

Glass border modifier with gradient highlight.

```swift
// Theme/GlassModifiers.swift

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
```

---

## 1.4 ThemeConstants.swift

Centralized constants for colors, spacing, and corner radius.

```swift
// Theme/ThemeConstants.swift

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

    // MARK: - Shadows

    enum Shadow {
        static func dropdown(_ color: Color = .black) -> some View {
            EmptyView()
                .shadow(color: color.opacity(0.25), radius: 20, y: 8)
        }

        static func modal(_ color: Color = .black) -> some View {
            EmptyView()
                .shadow(color: color.opacity(0.40), radius: 40, y: 20)
        }

        static func button(_ color: Color = .black) -> some View {
            EmptyView()
                .shadow(color: color.opacity(0.20), radius: 12, y: 6)
        }

        static func intense(_ color: Color = .black) -> some View {
            EmptyView()
                .shadow(color: color.opacity(0.50), radius: 50, y: 25)
        }
    }
}

// MARK: - Shadow Modifier Helper

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
}
```

---

## Verification

After creating files:
1. Build project to verify no syntax errors
2. Confirm `Theme/` directory appears in Xcode project navigator
3. Test `VisualEffectView.menu` renders properly in SwiftUI preview
