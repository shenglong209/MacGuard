# Phase 3: MenuBarView Update

**Goal:** Apply liquid glass styling to menu bar dropdown.

---

## Current State

From scout report (`MenuBarView.swift`):
- Frame width: 240
- Padding: 14, 8, 6, 10
- Corner radius: 6 (row highlights)
- Colors: `.accentColor.opacity(0.2)` pressed, `.primary.opacity(0.08)` hover
- No blur/material effects
- Status indicator using Circle() with color fills

---

## 3.1 Changes Overview

| Element | Current | New |
|---------|---------|-----|
| Dropdown background | None/clear | `GlassBackground(material: .menu)` |
| Row hover | `.primary.opacity(0.08)` | `VisualEffectView.selection` |
| Row pressed | `.accentColor.opacity(0.2)` | `.selection` + emphasized |
| Status circles | Color fill | Color fill + glass border |
| Container | Plain VStack | VStack + glass + shadow |

---

## 3.2 Implementation

### Main Container Update

```swift
// MenuBarView.swift - body update

var body: some View {
    VStack(spacing: 0) {
        // Existing content sections...
        permissionWarningSection
        stateSection
        deviceSection
        Divider().padding(.horizontal, 8)
        actionsSection
    }
    .padding(.vertical, Theme.Spacing.sm)
    .frame(width: 240)
    .background {
        GlassBackground(
            material: .menu,
            cornerRadius: Theme.CornerRadius.md + 2  // 10pt for menu
        )
        .dropdownShadow()
    }
}
```

### Menu Row Component

Create reusable menu row with glass hover:

```swift
// MARK: - Glass Menu Row

struct GlassMenuRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    var action: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: Theme.Spacing.md) {
                leading()
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                trailing()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background {
                if isHovered || isPressed {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                        .fill(.clear)
                        .background(
                            VisualEffectView(
                                material: .selection,
                                blendingMode: .withinWindow,
                                isEmphasized: isPressed
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// Convenience without trailing
extension GlassMenuRow where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder leading: @escaping () -> Leading,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading
        self.trailing = { EmptyView() }
        self.action = action
    }
}
```

### State Section Update

```swift
// MARK: - State Section

@ViewBuilder
private var stateSection: some View {
    HStack(spacing: Theme.Spacing.md) {
        // Status indicator with glass border
        Circle()
            .fill(stateColor)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .strokeBorder(stateColor.opacity(0.3), lineWidth: 1)
            )

        Text(stateText)
            .font(.subheadline)
            .foregroundStyle(.primary)

        Spacer()

        // Quick arm/disarm button with glass
        Button(action: toggleArm) {
            Text(isArmed ? "Disarm" : "Arm")
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
        }
        .buttonStyle(.plain)
        .background {
            Capsule()
                .fill(.clear)
                .background(
                    VisualEffectView(
                        material: .hudWindow,
                        blendingMode: .withinWindow,
                        isEmphasized: true
                    )
                )
                .clipShape(Capsule())
        }
        .glassCapsuleBorder()
    }
    .padding(.horizontal, Theme.Spacing.lg)
    .padding(.vertical, Theme.Spacing.md)
}

private var stateColor: Color {
    switch alarmManager.state {
    case .idle: return Theme.StateColor.idle
    case .armed: return Theme.StateColor.armed
    case .triggered: return Theme.StateColor.triggered
    case .alarming: return Theme.StateColor.alarming
    }
}
```

### Device Section Update

```swift
// MARK: - Device Section

@ViewBuilder
private var deviceSection: some View {
    if let device = alarmManager.bluetoothManager.trustedDevice {
        GlassMenuRow(
            title: device.name,
            subtitle: rssiText
        ) {
            // Icon with state-based styling
            ZStack {
                Circle()
                    .fill(deviceNearby ? Theme.StateColor.armed.opacity(0.15) : .secondary.opacity(0.1))
                    .frame(width: 32, height: 32)

                Image(systemName: deviceIcon)
                    .font(.system(size: 14))
                    .foregroundStyle(deviceNearby ? Theme.StateColor.armed : .secondary)
            }
        } trailing: {
            // Signal indicator
            Image(systemName: signalIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private var deviceNearby: Bool {
    alarmManager.bluetoothManager.isDeviceNearby
}
```

### Actions Section Update

```swift
// MARK: - Actions Section

private var actionsSection: some View {
    VStack(spacing: 0) {
        GlassMenuRow(title: "Settings...") {
            Image(systemName: "gear")
                .foregroundStyle(.secondary)
        } trailing: {
            Text("⌘,")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } action: {
            openSettings()
        }

        GlassMenuRow(title: "Check for Updates...") {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        } action: {
            checkForUpdates()
        }

        Divider().padding(.horizontal, 8)

        GlassMenuRow(title: "Quit MacGuard") {
            Image(systemName: "power")
                .foregroundStyle(.secondary)
        } trailing: {
            Text("⌘Q")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } action: {
            NSApp.terminate(nil)
        }
    }
}
```

---

## 3.3 Migration Steps

1. Add import for Theme at top of file
2. Update `body` with glass background wrapper
3. Replace individual row implementations with `GlassMenuRow`
4. Update color references to use `Theme.StateColor`
5. Update spacing to use `Theme.Spacing`
6. Test hover/press states work correctly

---

## Verification

- [ ] Dropdown has glass background with blur
- [ ] Shadow visible beneath dropdown
- [ ] Row hover shows glass selection highlight
- [ ] Status indicator colors match alarm state
- [ ] Quick arm/disarm button has glass capsule style
- [ ] Keyboard shortcuts visible on appropriate rows
- [ ] Device section shows signal strength
