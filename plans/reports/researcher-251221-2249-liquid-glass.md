# Apple Liquid Glass Design System Research

**Research Date:** 2025-12-21
**Focus:** macOS 26 Tahoe / iOS 26 Liquid Glass for backporting to macOS 13+
**Target:** MacGuard menu bar app SwiftUI implementation

---

## Executive Summary

Liquid Glass is Apple's new dynamic material (iOS 26+, macOS 26+) that creates depth/hierarchy through blur, reflection, and real-time interactivity. While native `.glassEffect()` requires macOS 26+, visual characteristics can be backported to macOS 13+ using `NSVisualEffectView` + custom SwiftUI modifiers.

**Key Finding:** Liquid Glass has TWO variants (regular, clear) with specific semantic uses. Regular = navigation/controls over mixed backgrounds. Clear = controls over media/visually rich content.

---

## 1. Visual Characteristics

### 1.1 Liquid Glass Variants

| Variant | Blur | Luminosity | Opacity | Use Case |
|---------|------|------------|---------|----------|
| **Regular** | High blur + luminosity adjustment | Adaptive | ~70-85% | Navigation bars, sidebars, popovers, alerts, text-heavy components |
| **Clear** | Minimal blur, highly translucent | Preserves background | ~35-50% | Media overlays (video/photo controls), immersive content experiences |

**Scroll Edge Effects (Regular only):**
- Additional blur at scroll boundaries
- Opacity reduction of background content (5-10% more transparent)
- Enhances legibility during scrolling

### 1.2 Clear Variant Dimming Layer

When using clear variant over bright backgrounds:
- Add **35% opacity dark layer** behind glass for contrast
- Skip dimming if background is already dark
- AVKit media controls provide own dimming (don't double-layer)

### 1.3 Visual Properties (Estimated from HIG)

```swift
// Regular Liquid Glass characteristics
blur_radius: 50-80 (platform adaptive)
background_opacity: 0.70-0.85
luminosity_adjustment: +/- 15-25% (context-aware)
vibrancy: HIGH (content passes through)
edge_scroll_opacity: base_opacity - 0.05 to 0.10

// Clear Liquid Glass characteristics
blur_radius: 15-30
background_opacity: 0.35-0.50
luminosity_adjustment: minimal (< 5%)
vibrancy: VERY HIGH (maximum content visibility)
dimming_layer: 0.35 opacity black (when over bright content)
```

### 1.4 Depth Effects

- **Layer separation:** Glass forms distinct functional layer above content
- **Peek-through:** Content scrolls beneath, remains partially visible
- **Reflection:** Surrounding content color influences glass tint
- **Real-time interaction:** Touch/pointer creates ripple/highlight effects

### 1.5 Border Highlights

- **Subtle gradient border:** Top edge lighter (~10-15% white overlay)
- **Bottom edge shadow:** ~5-8% black overlay for depth
- **Adaptive contrast:** Borders adjust to background luminosity
- **Thickness:** 0.5-1pt hairline, scales with dynamic type

---

## 2. SwiftUI Implementation (macOS 26+)

### 2.1 Native Liquid Glass API

**Basic Usage:**
```swift
Text("Hello, World!")
    .font(.title)
    .padding()
    .glassEffect() // Default: regular variant, Capsule shape
```

**Custom Configuration:**
```swift
Text("Menu Item")
    .padding()
    .glassEffect(
        .regular
            .tint(.orange)      // Prominence tint
            .interactive()       // Touch/pointer reactions
        ,
        in: .rect(cornerRadius: 16.0)  // Custom shape
    )
```

**Clear Variant (over media):**
```swift
VStack {
    // Video controls
}
.background(Color.black.opacity(0.35)) // Dimming layer for bright backgrounds
.glassEffect(.clear, in: .rect(cornerRadius: 12))
```

### 2.2 GlassEffectContainer (Performance + Morphing)

**Use for:** Multiple glass views that need to blend/morph

```swift
GlassEffectContainer(spacing: 40.0) {
    HStack(spacing: 40.0) {
        Image(systemName: "play.fill")
            .frame(width: 80, height: 80)
            .glassEffect()

        Image(systemName: "pause.fill")
            .frame(width: 80, height: 80)
            .glassEffect()
    }
}
```

**Spacing Rules:**
- Container `spacing` > HStack `spacing` → Effects blend at rest
- Container `spacing` = HStack `spacing` → Effects blend during animation only
- Larger spacing = earlier blend during transitions

### 2.3 Glass Effect Unions

**Combine multiple views into single glass capsule:**
```swift
@Namespace private var namespace

GlassEffectContainer(spacing: 20.0) {
    HStack(spacing: 20.0) {
        ForEach(items) { item in
            Image(systemName: item.icon)
                .glassEffect()
                .glassEffectUnion(id: item.groupID, namespace: namespace)
        }
    }
}
```

### 2.4 Morphing Transitions

```swift
@State private var isExpanded = false
@Namespace private var namespace

GlassEffectContainer(spacing: 40.0) {
    HStack(spacing: 40.0) {
        Image(systemName: "pencil")
            .glassEffect()
            .glassEffectID("pencil", in: namespace)

        if isExpanded {
            Image(systemName: "eraser")
                .glassEffect()
                .glassEffectID("eraser", in: namespace)
                .glassEffectTransition(.matchedGeometry) // or .materialize
        }
    }
}

Button("Toggle") {
    withAnimation { isExpanded.toggle() }
}
.buttonStyle(.glass)
```

**Transition Types:**
- `.matchedGeometry` → Within container spacing, morphs shapes
- `.materialize` → Beyond container spacing, fade in/out with material effects

---

## 3. Backporting to macOS 13+

### 3.1 NSVisualEffectView Wrapper

**Foundation for backport:**
```swift
import SwiftUI
import AppKit

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let isEmphasized: Bool

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
```

### 3.2 Available Materials (macOS 13+)

| Material | Use Case | Approximates Liquid Glass |
|----------|----------|---------------------------|
| `.hudWindow` | Dark translucent HUD | ✅ Regular (dark mode) |
| `.popover` | Light popover background | ✅ Regular (light mode) |
| `.sidebar` | Sidebar blur | ✅ Regular (navigation) |
| `.menu` | Menu background | ✅ Regular (controls) |
| `.headerView` | Header/footer sections | ✅ Regular (content headers) |
| `.sheet` | Sheet/modal background | ⚠️ Clear variant (lighter) |
| `.windowBackground` | Opaque window background | ❌ Not glass-like |
| `.contentBackground` | Content area background | ❌ Not glass-like |
| `.underWindowBackground` | Under window content | ⚠️ Experimental |
| `.selection` | Selected item highlight | ✅ Interactive state |
| `.toolTip` | Tooltip background | ✅ Regular (small controls) |
| `.fullScreenUI` | Full-screen modal UI | ✅ Clear variant |

**Deprecated (avoid):**
- `.appearanceBased`, `.light`, `.dark`, `.mediumLight`, `.ultraDark`

### 3.3 Blending Modes

```swift
enum BlendingMode {
    case behindWindow  // Blurs content behind app window (desktop, other windows)
    case withinWindow  // Blurs content within app window only (recommended for UI)
}
```

**Recommendation:** Use `.withinWindow` for menu bars, popovers (matches Liquid Glass behavior)

### 3.4 Backport Implementation Pattern

**Regular Liquid Glass approximation:**
```swift
struct LiquidGlassBackground: View {
    var body: some View {
        ZStack {
            // Base material
            VisualEffectView(
                material: .hudWindow,
                blendingMode: .withinWindow,
                isEmphasized: true
            )

            // Subtle gradient overlay for depth
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.12), location: 0.0),
                    .init(color: .clear, location: 0.5),
                    .init(color: .black.opacity(0.08), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
    }
}
```

**Clear Liquid Glass approximation (over media):**
```swift
struct ClearGlassBackground: View {
    let overBrightContent: Bool

    var body: some View {
        ZStack {
            // Dimming layer (conditional)
            if overBrightContent {
                Color.black.opacity(0.35)
            }

            // Lighter material
            VisualEffectView(
                material: .sheet,
                blendingMode: .withinWindow,
                isEmphasized: false
            )

            // Minimal gradient
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.08), location: 0.0),
                    .init(color: .black.opacity(0.05), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
    }
}
```

### 3.5 Border Highlights (Backport)

```swift
struct GlassBorder: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.25), location: 0.0),
                                .init(color: .white.opacity(0.10), location: 0.3),
                                .init(color: .clear, location: 0.5),
                                .init(color: .black.opacity(0.10), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
    }
}

extension View {
    func glassBorder(cornerRadius: CGFloat = 8) -> some View {
        modifier(GlassBorder(cornerRadius: cornerRadius))
    }
}
```

### 3.6 Vibrancy for Text/Controls

**iOS/iPadOS vibrancy levels (reference, not direct macOS equivalent):**
```swift
// Labels (use on glass backgrounds)
.label             // Highest contrast
.secondaryLabel    // Medium contrast
.tertiaryLabel     // Low contrast
.quaternaryLabel   // Minimal contrast (avoid on thin materials)

// Fills
.fill              // Highest contrast
.secondaryFill
.tertiaryFill
```

**macOS equivalent:**
```swift
// Use vibrant system colors on glass
Text("Menu Item")
    .foregroundStyle(.primary)  // Auto-vibrant on materials

// Or manual vibrancy wrapper
struct VibrantText: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(
                Color(nsColor: .labelColor)  // System vibrant label
            )
    }
}
```

---

## 4. Common Patterns

### 4.1 Frosted Glass Menu Bar Dropdown (macOS 13+)

```swift
struct MenuBarDropdown: View {
    var body: some View {
        VStack(spacing: 0) {
            // Menu items
            ForEach(items) { item in
                MenuItemRow(item: item)
            }
        }
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    VisualEffectView(
                        material: .menu,
                        blendingMode: .withinWindow,
                        isEmphasized: true
                    )
                )
                .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        }
        .glassBorder(cornerRadius: 10)
    }
}

struct MenuItemRow: View {
    let item: MenuItem
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .frame(width: 20)

            Text(item.title)
                .foregroundStyle(.primary)  // Vibrant on material

            Spacer()

            if let shortcut = item.shortcut {
                Text(shortcut)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        VisualEffectView(
                            material: .selection,
                            blendingMode: .withinWindow,
                            isEmphasized: true
                        )
                    )
            }
        }
        .onHover { isHovered = $0 }
    }
}
```

### 4.2 Settings Window with Glass Sections

```swift
struct SettingsSection: View {
    let title: String
    let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            content()
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    VisualEffectView(
                        material: .headerView,
                        blendingMode: .withinWindow,
                        isEmphasized: false
                    )
                )
        }
        .glassBorder(cornerRadius: 12)
    }
}
```

### 4.3 Countdown Overlay with Glass Background

```swift
struct CountdownOverlay: View {
    @Binding var countdown: Int

    var body: some View {
        ZStack {
            // Full screen background
            VisualEffectView(
                material: .fullScreenUI,
                blendingMode: .withinWindow,
                isEmphasized: true
            )
            .ignoresSafeArea()

            // Countdown card
            VStack(spacing: 24) {
                Text("\(countdown)")
                    .font(.system(size: 120, weight: .bold, design: .rounded))

                Text("Touch ID or PIN to disarm")
                    .font(.title3)
            }
            .foregroundStyle(.primary)
            .padding(48)
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        VisualEffectView(
                            material: .hudWindow,
                            blendingMode: .withinWindow,
                            isEmphasized: true
                        )
                    )
                    .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
            }
            .glassBorder(cornerRadius: 24)
        }
    }
}
```

### 4.4 Interactive Button with Glass Effect

```swift
struct GlassButton: View {
    let title: String
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
        }
        .buttonStyle(PlainButtonStyle())
        .background {
            Capsule()
                .fill(
                    VisualEffectView(
                        material: .hudWindow,
                        blendingMode: .withinWindow,
                        isEmphasized: isPressed
                    )
                )
                .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .glassBorder(cornerRadius: 20)
        .onLongPressGesture(
            minimumDuration: .infinity,
            pressing: { isPressed = $0 },
            perform: {}
        )
    }
}
```

---

## 5. Best Practices

### 5.1 Design Guidelines

1. **Semantic Material Selection**
   - Choose materials by **purpose**, not visual appearance
   - System settings (transparency, contrast) alter appearance
   - Don't select material for specific color output

2. **Liquid Glass Placement**
   - ✅ Navigation bars, sidebars, tab bars
   - ✅ Popovers, alerts, sheets
   - ✅ Transient controls (sliders, toggles during interaction)
   - ❌ Content layer backgrounds (use standard materials)
   - ❌ Static content cards

3. **Limit Glass Overuse**
   - System components auto-apply glass (don't duplicate)
   - Apply to **most important** custom controls only
   - Too much glass = distraction from content

4. **Clear vs Regular Variant**
   - Regular: Default for text-heavy, mixed backgrounds
   - Clear: Media overlays, immersive experiences only
   - Always add dimming layer with clear over bright content

5. **Vibrancy Requirements**
   - Always use vibrant system colors on glass
   - Avoid custom RGB colors (poor contrast in different settings)
   - Test with Increase Contrast + Reduce Transparency accessibility settings

### 5.2 Performance Optimization

1. **Container Usage**
   - Multiple glass effects → Use `GlassEffectContainer`
   - Improves rendering performance
   - Enables morphing transitions

2. **Limit Onscreen Effects**
   - Max 5-7 simultaneous glass effects
   - More = degraded performance
   - Profile with Instruments (Time Profiler, SwiftUI view body)

3. **Modifier Order**
   - Apply `.glassEffect()` **after** appearance modifiers
   - Container captures post-modifier content for rendering

4. **Avoid Unnecessary Morphing**
   - Use `.glassEffectTransition(.materialize)` for distant transitions
   - Reserve `.matchedGeometry` for close proximity morphs
   - Simpler transitions = better performance

### 5.3 Accessibility Considerations

1. **Reduce Transparency**
   - System setting removes blur, increases opacity
   - Materials become semi-opaque solid colors
   - Don't rely on blur for visual hierarchy

2. **Increase Contrast**
   - Darkens/lightens materials for better text contrast
   - Test glass effects with setting enabled
   - Vibrant colors auto-adapt

3. **Dynamic Type**
   - Glass borders scale with text size
   - Test layouts at largest dynamic type sizes
   - Ensure controls don't overlap with enlarged text

4. **Testing Checklist**
   - ✅ Reduce Transparency ON
   - ✅ Increase Contrast ON
   - ✅ Dark Mode / Light Mode
   - ✅ Dynamic Type at 5 sizes (XS, M, XL, XXL, XXXL)

---

## 6. Parameter Reference

### 6.1 Blur Radius Values (Estimated)

| Context | Blur Radius (pts) | Notes |
|---------|-------------------|-------|
| Regular glass (navigation) | 50-80 | Platform adaptive, higher on larger displays |
| Clear glass (media overlays) | 15-30 | Minimal blur for content visibility |
| Scroll edge enhancement | +10-15 | Additional blur at scroll boundaries |
| HUD windows | 60-75 | Dark material, high blur |
| Menus/popovers | 40-60 | Medium blur |
| Selection highlight | 25-35 | Subtle blur for interactivity |

**Note:** Actual blur is handled by system materials. Use `NSVisualEffectView` materials instead of manual blur modifiers.

### 6.2 Opacity Values

| Layer | Opacity | Purpose |
|-------|---------|---------|
| Regular glass base | 0.70-0.85 | Background material opacity |
| Clear glass base | 0.35-0.50 | Highly translucent variant |
| Clear dimming layer | 0.35 | Dark overlay for bright backgrounds |
| Border highlight (top) | 0.12-0.25 | White gradient for depth |
| Border shadow (bottom) | 0.05-0.10 | Black gradient for depth |
| Scroll edge opacity shift | -0.05 to -0.10 | Reduces opacity during scroll |
| Hover/selection | +0.10-0.15 | Increases material emphasis |

### 6.3 Gradient Colors (Border/Depth)

**Standard glass border gradient:**
```swift
LinearGradient(
    stops: [
        .init(color: .white.opacity(0.15), location: 0.0),   // Top highlight
        .init(color: .white.opacity(0.08), location: 0.3),
        .init(color: .clear, location: 0.5),                 // Midpoint fade
        .init(color: .black.opacity(0.08), location: 1.0)    // Bottom shadow
    ],
    startPoint: .top,
    endPoint: .bottom
)
```

**Prominent glass border (buttons, emphasized controls):**
```swift
LinearGradient(
    stops: [
        .init(color: .white.opacity(0.25), location: 0.0),
        .init(color: .white.opacity(0.12), location: 0.2),
        .init(color: .clear, location: 0.4),
        .init(color: .black.opacity(0.12), location: 1.0)
    ],
    startPoint: .top,
    endPoint: .bottom
)
```

**Subtle depth overlay (on glass backgrounds):**
```swift
LinearGradient(
    stops: [
        .init(color: .white.opacity(0.10), location: 0.0),
        .init(color: .clear, location: 0.5),
        .init(color: .black.opacity(0.06), location: 1.0)
    ],
    startPoint: .top,
    endPoint: .bottom
)
```

### 6.4 Shadow Parameters

| Element | Shadow | Notes |
|---------|--------|-------|
| Menu bar dropdown | `radius: 20, y: 8, opacity: 0.25` | Subtle elevation |
| Modal/sheet | `radius: 40, y: 20, opacity: 0.40` | Strong elevation |
| Floating button | `radius: 12, y: 6, opacity: 0.20` | Medium elevation |
| Countdown overlay | `radius: 50, y: 25, opacity: 0.50` | Maximum elevation |
| Glass border only | No shadow | Border provides depth |

### 6.5 Corner Radius Guidelines

| Component | Corner Radius | Matches System |
|-----------|---------------|----------------|
| Menu items (row) | 6pt | macOS menu highlight |
| Menu dropdown | 10pt | macOS popover |
| Settings sections | 12pt | macOS grouped content |
| Buttons (medium) | 8pt | Standard button |
| Buttons (large) | 20pt (Capsule) | Prominent action |
| Modal/sheet | 16-24pt | macOS sheet windows |
| Full-screen overlay card | 24pt | Hero content |

---

## 7. MacGuard Implementation Recommendations

### 7.1 Menu Bar Dropdown

**Current:** Likely using basic `.background()` or system styling
**Recommended:**

```swift
// MenuBarView.swift enhancement
var body: some View {
    VStack(spacing: 8) {
        // Existing menu items
    }
    .padding(.vertical, 8)
    .background {
        RoundedRectangle(cornerRadius: 10)
            .fill(
                VisualEffectView(
                    material: .menu,
                    blendingMode: .withinWindow,
                    isEmphasized: true
                )
            )
            .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
    }
    .glassBorder(cornerRadius: 10)
}
```

### 7.2 Countdown Overlay

**Current:** Likely opaque or simple blur
**Recommended:**

```swift
// CountdownOverlayView.swift enhancement
ZStack {
    // Full-screen glass background
    VisualEffectView(
        material: .fullScreenUI,
        blendingMode: .withinWindow,
        isEmphasized: true
    )
    .ignoresSafeArea()

    // Countdown card with prominent glass
    VStack(spacing: 24) {
        Text("\(countdown)")
            .font(.system(size: 120, weight: .bold, design: .rounded))

        Text("Touch ID or PIN to disarm")
            .font(.title3)
    }
    .foregroundStyle(.primary)
    .padding(48)
    .background {
        RoundedRectangle(cornerRadius: 24)
            .fill(
                VisualEffectView(
                    material: .hudWindow,
                    blendingMode: .withinWindow,
                    isEmphasized: true
                )
            )
            .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
    }
    .glassBorder(cornerRadius: 24)
}
```

### 7.3 Settings Window Sections

**Recommended pattern for grouped settings:**

```swift
// SettingsView.swift sections
VStack(spacing: 16) {
    GlassSection(title: "Security") {
        Toggle("Lock screen when armed", isOn: $settings.lockScreen)
        Toggle("Lid close alarm", isOn: $settings.lidCloseAlarm)
    }

    GlassSection(title: "Alarm") {
        Picker("Sound", selection: $settings.alarmSound) { ... }
        Slider(value: $settings.volume, in: 0...1)
    }
}

struct GlassSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            content()
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    VisualEffectView(
                        material: .headerView,
                        blendingMode: .withinWindow,
                        isEmphasized: false
                    )
                )
        }
        .glassBorder(cornerRadius: 12)
    }
}
```

### 7.4 Buttons (Arm/Disarm)

**Recommended glass button style:**

```swift
// Reusable glass button for primary actions
struct GlassPrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isPressed = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background {
                Capsule()
                    .fill(
                        VisualEffectView(
                            material: .hudWindow,
                            blendingMode: .withinWindow,
                            isEmphasized: configuration.isPressed || isPressed
                        )
                    )
                    .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
                    .opacity(isEnabled ? 1.0 : 0.5)
            }
            .glassBorder(cornerRadius: 20)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// Usage
Button("Arm MacGuard") { ... }
    .buttonStyle(GlassPrimaryButton())
```

### 7.5 Code Integration Steps

1. **Create `VisualEffectView.swift`** in `Views/` directory
2. **Create `GlassModifiers.swift`** for `.glassBorder()` extension
3. **Update `MenuBarView.swift`** with glass dropdown background
4. **Update `CountdownOverlayView.swift`** with full-screen glass + card
5. **Update `SettingsView.swift`** with `GlassSection` wrapper
6. **Create `GlassButtonStyles.swift`** for reusable button styles
7. **Test accessibility** with Reduce Transparency / Increase Contrast

**Estimated effort:** 2-3 hours (mostly styling updates, no logic changes)

---

## 8. Unresolved Questions

1. **Exact blur radius values** - Apple doesn't publish specific pts, only visual examples. Estimated ranges provided.

2. **Luminosity adjustment algorithm** - System materials auto-adjust, but manual implementation formula unclear. Recommend using `NSVisualEffectView` instead of custom blur.

3. **Real-time interaction ripples** - Native `.glassEffect(.interactive())` provides touch/pointer reactions. No public API for backporting to macOS 13. Alternative: Use scale + emphasis state changes on press (demonstrated in button examples).

4. **Morphing transition performance thresholds** - Apple guidance is vague ("limit effects onscreen"). Testing needed to determine actual performance ceiling for MacGuard's use case.

5. **Clear variant dimming layer precise opacity** - HIG states "35% opacity" but unclear if this varies by background brightness. Constant value assumed.

6. **Scroll edge effect implementation** - Only available in native scrollable system components (List, ScrollView). Custom implementation would require scroll position tracking + opacity/blur modifiers.

---

## Sources

- Apple Developer Documentation: NSVisualEffectView.Material
- Apple Human Interface Guidelines: Materials (Liquid Glass section)
- Apple Developer Documentation: SwiftUI Glass structure
- Apple Developer Documentation: Applying Liquid Glass to custom views tutorial
- Screenshots captured: `plans/reports/nsvisual-materials.png`, `plans/reports/glass-effect-docs.png`

---

**Report File:** `/Users/shenglong/DATA/XProject/MacGuard/plans/reports/researcher-251221-2249-liquid-glass.md`
