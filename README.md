# MacGuard

Anti-theft alarm app for macOS. Protects your laptop in public places by triggering a loud alarm when unauthorized access is detected.

## Features

- **Menu Bar App** - Runs silently in the background
- **Input Monitoring** - Detects keyboard, mouse, and trackpad activity
- **Sleep/Power Detection** - Triggers on lid close or power disconnect
- **Bluetooth Proximity** - Auto-disarm when trusted device (iPhone/AirPods) is nearby
- **Touch ID + PIN** - Secure authentication to disarm
- **Loud Alarm** - Plays at maximum volume, unmutes system
- **Auto-Lock** - Locks screen when armed

## Requirements

- macOS 13 Ventura or later
- Accessibility permission (for input monitoring)
- Bluetooth (for proximity detection)

## Installation

### Build from Source

```bash
git clone https://github.com/shenglong209/MacGuard.git
cd MacGuard
swift build -c release
```

The binary will be at `.build/release/MacGuard`

### Run

```bash
.build/debug/MacGuard
```

## Usage

1. **Grant Accessibility Permission**
   - Open Settings from menu bar
   - Click "Grant" next to Accessibility
   - Enable MacGuard in System Preferences → Privacy & Security → Accessibility

2. **Configure Trusted Device** (optional)
   - Click "Scan for Devices..."
   - Select your iPhone, AirPods, or Apple Watch
   - Device will auto-disarm alarm when nearby

3. **Set Backup PIN**
   - Click "Set PIN" in Security section
   - Enter 4-8 digit PIN

4. **Arm MacGuard**
   - Click "Arm MacGuard" from menu bar
   - Screen locks automatically
   - Any input triggers 3-second countdown

5. **Disarm**
   - Touch ID (if available)
   - Enter PIN
   - Trusted device proximity (automatic)

## How It Works

```
┌─────────┐
│  IDLE   │  ← Disarmed, not monitoring
└────┬────┘
     │ arm
     ▼
┌─────────┐
│  ARMED  │  ← Monitoring input, sleep, power
└────┬────┘
     │ input detected
     ▼
┌─────────┐
│TRIGGERED│  ← 3-second countdown
└────┬────┘
     │ timeout
     ▼
┌─────────┐
│ALARMING │  ← Loud alarm at max volume
└─────────┘
```

## Project Structure

```
MacGuard/
├── MacGuardApp.swift           # App entry point
├── Managers/
│   ├── AlarmStateManager.swift      # State machine
│   ├── InputMonitor.swift           # CGEventTap monitoring
│   ├── SleepMonitor.swift           # Lid close detection
│   ├── PowerMonitor.swift           # Power disconnect
│   ├── BluetoothProximityManager.swift  # RSSI scanning
│   ├── AuthManager.swift            # Touch ID + Keychain
│   └── AlarmAudioManager.swift      # Audio playback
├── Views/
│   ├── MenuBarView.swift            # Menu bar dropdown
│   ├── SettingsView.swift           # Settings window
│   ├── CountdownOverlayView.swift   # Fullscreen overlay
│   └── DeviceScannerView.swift      # Bluetooth scanner
├── Models/
│   ├── AlarmState.swift
│   └── TrustedDevice.swift
└── Resources/
    └── alarm.aiff
```

## Permissions

| Permission | Purpose |
|------------|---------|
| Accessibility | Global input monitoring via CGEventTap |
| Bluetooth | Trusted device proximity detection |

## License

MIT License

## Contributing

Pull requests welcome. For major changes, please open an issue first.
