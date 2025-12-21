# Phase 6: DeviceScannerView Update

**Goal:** Apply liquid glass styling to Bluetooth device scanner modal.

---

## Current State

From scout report (`DeviceScannerView.swift`):
- Window: 350x400
- Header with scan status
- Device list with plain button style
- Signal strength bars (3px width, heights 4-10px)
- Empty state with large icon
- Footer with Cancel/Rescan buttons

---

## 6.1 Changes Overview

| Element | Current | New |
|---------|---------|-----|
| Header background | `Color(nsColor: .windowBackgroundColor)` | `GlassBackground(material: .headerView)` |
| Device rows | Plain list | Glass hover effect |
| Signal bars | Colored rectangles | Same with glass background |
| Empty state icon | `.blue.opacity(0.1)` circle | Glass circle background |
| Footer buttons | System buttons | Glass button styles |

---

## 6.2 Implementation

### Main Structure

```swift
// DeviceScannerView.swift

var body: some View {
    VStack(spacing: 0) {
        headerView
        Divider()
        deviceListOrEmpty
        Divider()
        footerView
    }
    .frame(width: 350, height: 400)
    .background {
        // Window background with subtle glass
        VisualEffectView(
            material: .sidebar,
            blendingMode: .behindWindow
        )
    }
}
```

### Header with Glass

```swift
// MARK: - Header View

private var headerView: some View {
    HStack(spacing: Theme.Spacing.md) {
        // Scanning indicator
        if isScanning {
            ProgressView()
                .scaleEffect(0.7)
        } else {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(Theme.Accent.primary)
        }

        VStack(alignment: .leading, spacing: 2) {
            Text("Bluetooth Devices")
                .font(.headline)

            Text(isScanning ? "Scanning..." : "\(devices.count) devices found")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Spacer()
    }
    .padding(Theme.Spacing.lg)
    .background {
        GlassBackground(
            material: .headerView,
            cornerRadius: 0,
            showBorder: false
        )
    }
}
```

### Device List with Glass Rows

```swift
// MARK: - Device List

private var deviceListOrEmpty: some View {
    Group {
        if devices.isEmpty && !isScanning {
            emptyState
        } else {
            List(devices) { device in
                deviceRow(device)
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Device Row

private func deviceRow(_ device: DiscoveredDevice) -> some View {
    Button(action: { selectDevice(device) }) {
        HStack(spacing: Theme.Spacing.md) {
            // Device icon with glass background
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

                Image(systemName: deviceIcon(device))
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Accent.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(device.identifier.uuidString.prefix(8) + "...")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Signal strength indicator
            signalBars(rssi: device.rssi)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .listRowBackground(
        RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
            .fill(isHovered ? Color.accentColor.opacity(0.1) : .clear)
    )
}

// MARK: - Signal Bars

private func signalBars(rssi: Int) -> some View {
    HStack(spacing: 2) {
        ForEach(0..<4) { index in
            RoundedRectangle(cornerRadius: 1)
                .fill(barColor(for: index, rssi: rssi))
                .frame(width: 3, height: barHeight(for: index))
        }
    }
}

private func barColor(for index: Int, rssi: Int) -> Color {
    let strength = signalStrength(rssi: rssi)
    if index < strength {
        switch strength {
        case 4: return Theme.StateColor.armed
        case 3: return Theme.StateColor.armed
        case 2: return Theme.StateColor.triggered
        default: return Theme.StateColor.alarming
        }
    }
    return .gray.opacity(0.3)
}

private func barHeight(for index: Int) -> CGFloat {
    CGFloat(4 + index * 2)  // 4, 6, 8, 10
}

private func signalStrength(rssi: Int) -> Int {
    switch rssi {
    case -50...0: return 4
    case -60..<(-50): return 3
    case -70..<(-60): return 2
    default: return 1
    }
}
```

### Empty State with Glass

```swift
// MARK: - Empty State

private var emptyState: some View {
    VStack(spacing: Theme.Spacing.lg) {
        ZStack {
            // Glass circle background
            Circle()
                .fill(.clear)
                .background(
                    VisualEffectView(
                        material: .selection,
                        blendingMode: .withinWindow
                    )
                )
                .clipShape(Circle())
                .frame(width: 100, height: 100)

            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Accent.primary.opacity(0.6))
        }

        VStack(spacing: Theme.Spacing.xs) {
            Text("No Devices Found")
                .font(.headline)

            Text("Make sure Bluetooth is enabled and\ndevices are in pairing mode")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(Theme.Spacing.xl)
}
```

### Footer with Glass Buttons

```swift
// MARK: - Footer View

private var footerView: some View {
    HStack(spacing: Theme.Spacing.md) {
        Button("Cancel") {
            dismiss()
        }
        .buttonStyle(GlassSecondaryButtonStyle())

        Spacer()

        Button(action: startScan) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "arrow.clockwise")
                Text("Rescan")
            }
        }
        .buttonStyle(GlassPrimaryButtonStyle())
        .disabled(isScanning)
    }
    .padding(Theme.Spacing.lg)
    .background {
        GlassBackground(
            material: .headerView,
            cornerRadius: 0,
            showBorder: false
        )
    }
}
```

---

## 6.3 Migration Steps

1. Update header background to `GlassBackground`
2. Update device rows with glass icon circles
3. Keep signal bars, update colors to `Theme.StateColor`
4. Update empty state icon to glass circle
5. Update footer buttons to glass button styles
6. Add subtle window background with sidebar material

---

## Verification

- [ ] Header has glass background
- [ ] Device list rows have hover state
- [ ] Device icons have glass circle backgrounds
- [ ] Signal bars show appropriate colors
- [ ] Empty state icon has glass circle
- [ ] Cancel button has secondary glass style
- [ ] Rescan button has primary glass style
- [ ] Scanning indicator visible when active
