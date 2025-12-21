# Phase 4: SettingsView Update

**Goal:** Apply liquid glass styling to settings window with glass sections.

---

## Current State

From scout report (`SettingsView.swift`):
- Window: 420x680
- Header: 3px animated gradient bar, icon with glow/shadow
- Form with `.formStyle(.grouped)`
- Sections: Permissions, Trusted Device, Security, Behavior, Startup, About
- Colors: RGB gradient (idle), green (armed), various semantic colors

---

## 4.1 Changes Overview

| Element | Current | New |
|---------|---------|-----|
| Header background | `Color(nsColor: .windowBackgroundColor)` | `GlassBackground(material: .headerView)` |
| Gradient bar | Custom RGB gradient | Preserve, add glass border below |
| Form sections | System grouped style | Preserve + subtle glass section wrappers |
| Quick arm button | `.primary.opacity(0.06)` | Glass capsule button |
| Version badge | `.primary.opacity(0.06)` | Glass pill |

---

## 4.2 Implementation

### Header with Glass

```swift
// MARK: - Header View

private var headerView: some View {
    VStack(spacing: 0) {
        // Animated gradient status bar (preserved)
        Rectangle()
            .fill(headerGradient)
            .frame(height: 3)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: gradientOffset)

        // Header content with glass background
        HStack(spacing: Theme.Spacing.lg) {
            // App icon with glow
            appIconView

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("MacGuard")
                        .font(.title2.bold())

                    // Version badge with glass
                    Text("v\(appVersion)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 2)
                        .background {
                            Capsule()
                                .fill(.clear)
                                .background(
                                    VisualEffectView(
                                        material: .hudWindow,
                                        blendingMode: .withinWindow
                                    )
                                )
                                .clipShape(Capsule())
                        }
                        .glassCapsuleBorder()
                }

                // Status with indicator
                HStack(spacing: Theme.Spacing.xs) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)

                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Quick arm/disarm button
            quickArmButton
        }
        .padding(Theme.Spacing.xl)
        .background {
            GlassBackground(
                material: .headerView,
                cornerRadius: 0,
                showBorder: false
            )
        }
    }
}

// MARK: - Quick Arm Button

private var quickArmButton: some View {
    Button(action: toggleArm) {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: isArmed ? "lock.open.fill" : "lock.fill")
            Text(isArmed ? "Disarm" : "Arm")
        }
        .font(.headline)
        .foregroundStyle(.primary)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
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
    .glassCapsuleBorder(prominent: true)
}
```

### Form Sections with Glass Enhancement

Keep `.formStyle(.grouped)` but wrap section content:

```swift
// MARK: - Settings Form

private var settingsForm: some View {
    Form {
        // PERMISSIONS SECTION
        Section {
            permissionRows
        } header: {
            sectionHeader("Permissions", icon: "shield.checkered")
        }

        // TRUSTED DEVICE SECTION
        Section {
            trustedDeviceRows
        } header: {
            sectionHeader("Trusted Device", icon: "iphone.radiowaves.left.and.right")
        }

        // SECURITY SECTION
        Section {
            securityRows
        } header: {
            sectionHeader("Security", icon: "lock.shield")
        }

        // BEHAVIOR SECTION
        Section {
            behaviorRows
        } header: {
            sectionHeader("Behavior", icon: "gearshape.2")
        }

        // STARTUP SECTION
        Section {
            startupRows
        } header: {
            sectionHeader("Startup", icon: "power")
        }

        // ABOUT SECTION
        Section {
            aboutRows
        } header: {
            sectionHeader("About", icon: "info.circle")
        }
    }
    .formStyle(.grouped)
}

// MARK: - Section Header

private func sectionHeader(_ title: String, icon: String) -> some View {
    HStack(spacing: Theme.Spacing.sm) {
        Image(systemName: icon)
            .font(.caption)
            .foregroundStyle(.secondary)

        Text(title.uppercased())
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }
}
```

### Permission Row with Glass Button

```swift
// MARK: - Permission Row

private func permissionRow(
    title: String,
    subtitle: String,
    icon: String,
    iconColor: Color,
    isGranted: Bool,
    action: @escaping () -> Void
) -> some View {
    HStack(spacing: Theme.Spacing.md) {
        // Icon with glass background
        ZStack {
            Circle()
                .fill(.clear)
                .background(
                    VisualEffectView(
                        material: .selection,
                        blendingMode: .withinWindow
                    )
                )
                .clipShape(Circle())
                .frame(width: 32, height: 32)

            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(iconColor)
        }

        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Spacer()

        if isGranted {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.StateColor.armed)
        } else {
            Button("Grant") {
                action()
            }
            .buttonStyle(GlassSecondaryButtonStyle())
        }
    }
}
```

### Trusted Device Row

```swift
// MARK: - Trusted Device Row

private var trustedDeviceRow: some View {
    HStack(spacing: Theme.Spacing.md) {
        // Device icon with glass
        ZStack {
            Circle()
                .fill(.clear)
                .background(
                    VisualEffectView(
                        material: .selection,
                        blendingMode: .withinWindow
                    )
                )
                .clipShape(Circle())
                .frame(width: 40, height: 40)

            Image(systemName: deviceIcon)
                .font(.system(size: 16))
                .foregroundStyle(Theme.Accent.primary)
        }

        VStack(alignment: .leading, spacing: 2) {
            Text(device?.name ?? "No device configured")
                .font(.body)

            if let device, let rssi = device.lastRSSI {
                Text(rssiDescription(rssi))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Spacer()

        if device != nil {
            Button(action: removeDevice) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }

        Button(device == nil ? "Scan..." : "Change...") {
            showDeviceScanner = true
        }
        .buttonStyle(GlassSecondaryButtonStyle())
    }
}
```

---

## 4.3 Button Styles (Preview)

```swift
// Glass secondary button for settings actions
struct GlassSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .foregroundStyle(.primary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs + 2)
            .background {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                    .fill(.clear)
                    .background(
                        VisualEffectView(
                            material: .hudWindow,
                            blendingMode: .withinWindow,
                            isEmphasized: configuration.isPressed
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm))
            }
            .glassBorder(cornerRadius: Theme.CornerRadius.sm)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
```

---

## 4.4 Migration Steps

1. Update header background to use `GlassBackground`
2. Update version badge to glass capsule
3. Update quick arm button to glass capsule
4. Keep Form with `.formStyle(.grouped)` - already has nice macOS styling
5. Add glass icon backgrounds to permission/device rows
6. Update action buttons to use `GlassSecondaryButtonStyle`
7. Replace hardcoded colors with `Theme.StateColor`

---

## Verification

- [ ] Header has glass background
- [ ] Gradient status bar still animates
- [ ] Version badge has glass pill appearance
- [ ] Quick arm button has glass capsule style
- [ ] Permission row icons have glass circles
- [ ] Grant/Change buttons have glass style
- [ ] Form sections maintain grouped appearance
- [ ] All state colors match (idle/armed)
