# Phase 1: SPM Integration & Key Setup

## Tasks

### 1.1 Add Sparkle Dependency to Package.swift

**File:** `Package.swift`

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacGuard",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MacGuard",
            targets: ["MacGuard"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "MacGuard",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: ".",
            exclude: [
                "Info.plist",
                "MacGuard.entitlements",
                "Package.swift",
                "README.md",
                "plans",
                "scripts",
                "appcast.xml"
            ],
            sources: [
                "MacGuardApp.swift",
                "Managers",
                "Views",
                "Models"
            ],
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
```

**Changes:**
- Added `dependencies` array with Sparkle package
- Added Sparkle to target dependencies
- Added `plans`, `scripts`, `appcast.xml` to exclude list

### 1.2 Verify Build

```bash
cd /Users/shenglong/DATA/XProject/MacGuard
swift build
```

Expected: Build succeeds with Sparkle framework linked.

### 1.3 Generate EdDSA Keypair

```bash
# Locate Sparkle tools after build
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"

# Generate keypair (one-time operation)
$SPARKLE_BIN/generate_keys

# Output shows:
# - Private key stored in Keychain (Access: com.apple.sparkle.private-key.ed25519)
# - Public key (base64 string to copy)
```

**IMPORTANT:**
- Copy the public key immediately
- Export private key to secure backup: `$SPARKLE_BIN/generate_keys -x sparkle-private-key.txt`
- Store backup in password manager or secure vault
- **Never commit private key to repo**

### 1.4 Update Info.plist with Sparkle Config

**File:** `Info.plist`

Add these keys:

```xml
<!-- Sparkle Update Configuration -->
<key>SUFeedURL</key>
<string>https://raw.githubusercontent.com/shenglong209/MacGuard/main/appcast.xml</string>

<key>SUPublicEDKey</key>
<string>YOUR_BASE64_PUBLIC_KEY_HERE</string>

<!-- Enable automatic update checks -->
<key>SUEnableAutomaticChecks</key>
<true/>

<!-- Check interval: 24 hours (default) -->
<key>SUScheduledCheckInterval</key>
<integer>86400</integer>

<!-- Show release notes -->
<key>SUShowReleaseNotes</key>
<true/>
```

### 1.5 Update CFBundleVersion for Sparkle Compatibility

Sparkle requires incrementing integer `CFBundleVersion` for each release.

Current: `<string>1</string>`

For v1.2.0 release, update to: `<string>2</string>`

**Version Convention:**
- `CFBundleVersion`: Integer (1, 2, 3...) - used by Sparkle for comparison
- `CFBundleShortVersionString`: Semantic (1.0.0, 1.1.0...) - user-facing

## Verification Checklist

- [x] Package.swift updated with Sparkle dependency
- [x] `swift build` succeeds (warning about appcast.xml expected)
- [x] EdDSA keypair generated
- [x] Public key added to Info.plist (format valid)
- [x] Private key backed up securely (~/.macguard-keys/)
- [x] SUFeedURL points to correct appcast location
- [x] CFBundleVersion strategy documented and implemented

**Phase Completed:** 2025-12-18 15:44

**Code Review:** ✅ Passed - See `plans/reports/code-reviewer-251218-1540-phase-01-review.md`
- 0 critical issues
- 1 warning (expected appcast.xml absence)
- 2 suggestions (verify keypair origin, update plan with actual excludes)

## Notes

- Sparkle 2.x requires macOS 10.13+, MacGuard requires 13.0+ - compatible
- First update check happens on 2nd app launch (not first)
- LSUIElement=true apps work with Sparkle - dialogs appear as floating windows
