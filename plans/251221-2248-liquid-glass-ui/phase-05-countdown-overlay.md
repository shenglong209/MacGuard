# Phase 5: CountdownOverlayView Update

**Goal:** Apply liquid glass styling to fullscreen countdown/alarm overlay.

---

## Current State

From scout report (`CountdownOverlayView.swift`):
- Full-screen dark gradient overlay (`Color.black.opacity(0.95)` → `0.85`)
- Red pulse circle when alarming (300x300, blur 60)
- Icon with glow effect (blur 20)
- Countdown ring (160x160, lineWidth 8)
- PIN overlay: `.ultraThinMaterial` + white border
- Hardcoded colors and sizes throughout

---

## 5.1 Changes Overview

| Element | Current | New |
|---------|---------|-----|
| Background | Dark gradient | `FullScreenGlass` |
| Countdown card | None | `GlassCard` with HUD material |
| PIN overlay | `.ultraThinMaterial` | `GlassBackground(material: .hudWindow)` |
| Auth buttons | Custom styled | Glass button style |
| Pulse effect | Red circle + blur | Preserve with adjusted opacity |

---

## 5.2 Implementation

### Main Overlay Structure

```swift
// CountdownOverlayView.swift

var body: some View {
    GeometryReader { geometry in
        ZStack {
            // Full-screen glass background
            FullScreenGlass()

            // Additional dark gradient for depth (less opaque than before)
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.60), location: 0.0),
                    .init(color: .black.opacity(isAlarming ? 0.40 : 0.50), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Pulsing red circle (alarming only)
            if isAlarming {
                pulseCircle
            }

            // Main content card
            countdownCard
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
}
```

### Countdown Card with Glass

```swift
// MARK: - Countdown Card

private var countdownCard: some View {
    VStack(spacing: Theme.Spacing.xxl) {
        // Warning icon with glow
        warningIcon

        // Title
        Text(titleText)
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .tracking(2)

        // Countdown ring (triggered state)
        if state == .triggered {
            countdownRing
        }

        // Auth options
        authButtons
    }
    .padding(Theme.Spacing.xxxl + 16)  // 48pt
    .background {
        GlassBackground(
            material: .hudWindow,
            cornerRadius: Theme.CornerRadius.xxxl
        )
        .intenseShadow()
    }
}
```

### Warning Icon with Glass Glow

```swift
// MARK: - Warning Icon

private var warningIcon: some View {
    ZStack {
        // Glow effect
        Image(systemName: iconName)
            .font(.system(size: 90))
            .foregroundStyle(iconColor.opacity(0.6))
            .blur(radius: 25)

        // Main icon
        Image(systemName: iconName)
            .font(.system(size: 80))
            .foregroundStyle(iconColor)
            .scaleEffect(iconScale)
            .animation(
                .easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                value: iconScale
            )
    }
}

private var iconName: String {
    switch state {
    case .triggered: return "exclamationmark.triangle.fill"
    case .alarming: return "speaker.wave.3.fill"
    default: return "lock.shield.fill"
    }
}

private var iconColor: Color {
    switch state {
    case .triggered: return Theme.StateColor.triggered
    case .alarming: return Theme.StateColor.alarming
    default: return Theme.StateColor.armed
    }
}
```

### Countdown Ring

```swift
// MARK: - Countdown Ring

private var countdownRing: some View {
    ZStack {
        // Background ring
        Circle()
            .stroke(Color.white.opacity(0.2), lineWidth: 8)
            .frame(width: 160, height: 160)

        // Progress ring
        Circle()
            .trim(from: 0, to: ringProgress)
            .stroke(
                LinearGradient(
                    colors: [Theme.StateColor.alarming, Theme.StateColor.triggered],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: StrokeStyle(lineWidth: 8, lineCap: .round)
            )
            .frame(width: 160, height: 160)
            .rotationEffect(.degrees(-90))
            .animation(.linear(duration: 1), value: ringProgress)

        // Countdown number
        Text("\(countdown)")
            .font(.system(size: 72, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
    }
}
```

### Auth Buttons with Glass

```swift
// MARK: - Auth Buttons

private var authButtons: some View {
    VStack(spacing: Theme.Spacing.lg) {
        // Touch ID button (if available)
        if canUseBiometrics {
            Button(action: attemptBiometricAuth) {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "touchid")
                        .font(.title2)
                    Text("Touch ID")
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.xxl)
                .padding(.vertical, Theme.Spacing.lg)
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

        // PIN button
        Button(action: { showPINEntry = true }) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "rectangle.and.pencil.and.ellipsis")
                    .font(.title3)
                Text("Enter PIN")
                    .font(.headline)
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.md)
        }
        .buttonStyle(.plain)
        .background {
            Capsule()
                .fill(.clear)
                .background(
                    VisualEffectView(
                        material: .selection,
                        blendingMode: .withinWindow
                    )
                )
                .clipShape(Capsule())
        }
        .glassCapsuleBorder()
    }
}
```

### PIN Entry Overlay with Glass

```swift
// MARK: - PIN Entry Overlay

private var pinEntryOverlay: some View {
    ZStack {
        // Dimming layer
        Color.black.opacity(0.4)
            .ignoresSafeArea()
            .onTapGesture {
                showPINEntry = false
            }

        // PIN entry card
        VStack(spacing: Theme.Spacing.lg) {
            Text("Enter PIN")
                .font(.headline)
                .foregroundStyle(.white)

            SecureField("PIN", text: $pinEntry)
                .textFieldStyle(.plain)
                .font(.system(size: 24, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(width: 150)
                .padding(Theme.Spacing.md)
                .background {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .fill(Color.white.opacity(0.1))
                }
                .glassBorder(cornerRadius: Theme.CornerRadius.md)
                .offset(x: shakeOffset)

            if showError {
                Text("Incorrect PIN")
                    .font(.caption)
                    .foregroundStyle(Theme.StateColor.alarming)
            }

            HStack(spacing: Theme.Spacing.lg) {
                Button("Cancel") {
                    pinEntry = ""
                    showPINEntry = false
                }
                .buttonStyle(GlassSecondaryButtonStyle())

                Button("Verify") {
                    verifyPIN()
                }
                .buttonStyle(GlassPrimaryButtonStyle())
            }
        }
        .padding(Theme.Spacing.xxxl)
        .background {
            GlassBackground(
                material: .hudWindow,
                cornerRadius: Theme.CornerRadius.xxl
            )
            .modalShadow()
        }
    }
}
```

### Pulse Circle (Alarming)

```swift
// MARK: - Pulse Circle

private var pulseCircle: some View {
    Circle()
        .fill(Theme.StateColor.alarming.opacity(pulseOpacity))
        .frame(width: 350, height: 350)
        .blur(radius: 80)
        .opacity(pulseOpacity)
        .scaleEffect(pulseScale)
        .animation(
            .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
            value: pulseOpacity
        )
}
```

---

## 5.3 Migration Steps

1. Replace dark gradient background with `FullScreenGlass()` + lighter overlay gradient
2. Wrap main content in `countdownCard` with `GlassBackground`
3. Update icon glow to use consistent styling
4. Update countdown ring colors to `Theme.StateColor`
5. Replace auth buttons with glass capsule buttons
6. Update PIN overlay to use `GlassBackground`
7. Adjust pulse circle to work with glass background

---

## Verification

- [ ] Full-screen has glass blur effect
- [ ] Countdown card has prominent glass background
- [ ] Icon glow visible and animates
- [ ] Countdown ring shows progress correctly
- [ ] Touch ID button has glass capsule style
- [ ] PIN button has subtle glass style
- [ ] PIN entry modal has glass card appearance
- [ ] Shake animation works on wrong PIN
- [ ] Alarming state shows pulsing red glow
