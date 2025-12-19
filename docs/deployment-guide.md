# MacGuard Deployment Guide

**Version:** 1.3.4 (Build 2)
**Last Updated:** 2025-12-19

## Overview

This guide covers building, releasing, and deploying MacGuard from source code to end-user distribution via DMG and Sparkle auto-updates.

## Prerequisites

### Development Environment
- **macOS:** 13.0 Ventura or later
- **Xcode:** 15.0 or later (for Swift 5.9+)
- **Command Line Tools:** `xcode-select --install`
- **Homebrew:** (optional) For additional tools

### Required Tools
```bash
# Swift (included with Xcode)
swift --version  # Should be 5.9 or later

# Git
git --version

# Optional: EdDSA signing tools (included in Sparkle)
# Located at .build/artifacts/sparkle/Sparkle/bin/
```

### GitHub Repository Access
- Clone URL: `https://github.com/shenglong209/MacGuard.git`
- Write access required for releases

---

## Local Development Build

### 1. Clone Repository
```bash
git clone https://github.com/shenglong209/MacGuard.git
cd MacGuard
```

### 2. Resolve Dependencies
Swift Package Manager automatically resolves dependencies on first build.

```bash
# Fetch dependencies manually (optional)
swift package resolve

# Dependencies:
# - Sparkle 2.x (auto-update framework)
```

### 3. Debug Build
```bash
# Build in debug mode
swift build

# Output: .build/debug/MacGuard
```

### 4. Run Debug Build
```bash
# Run directly
./.build/debug/MacGuard

# Or use swift run
swift run MacGuard
```

**Note:** Debug builds do not bundle Resources correctly. Use release build for full functionality.

---

## Release Build

### 1. Release Build Command
```bash
# Build in release mode
swift build -c release

# Output: .build/release/MacGuard
```

### 2. Create DMG
```bash
# Run DMG creation script
./scripts/create-dmg.sh 1.3.4

# Output: dist/MacGuard-1.3.4.dmg
```

**Script Details:**
- Builds release binary
- Creates `.app` bundle structure
- Copies Sparkle.framework
- Bundles resources (icons, audio)
- Creates DMG with hdiutil

### 3. Verify DMG
```bash
# Mount DMG
hdiutil attach dist/MacGuard-1.3.4.dmg

# Verify .app structure
ls -R /Volumes/MacGuard/MacGuard.app/

# Unmount
hdiutil detach /Volumes/MacGuard
```

---

## Code Signing (Optional but Recommended)

Code signing preserves Accessibility permission across updates and improves first-launch UX.

### Prerequisites
- **Apple Developer Account** ($99/year)
- **Apple Development Certificate** or **Apple Developer ID Certificate**
- **Keychain Access** to certificate

### 1. Export Certificate for CI
```bash
# Export certificate from Keychain
./scripts/export-certificate.sh

# Output:
# - Signing_Certificate.p12 (password-protected)
# - Base64-encoded string (for GitHub secrets)
```

### 2. Add GitHub Secrets
Navigate to GitHub repository → Settings → Secrets and variables → Actions

Add secrets:
- `SIGNING_CERTIFICATE_P12_BASE64`: Base64-encoded .p12 file
- `SIGNING_CERTIFICATE_PASSWORD`: Password for .p12 file

### 3. Local Code Signing
```bash
# Sign .app bundle
codesign --deep --force --verify --verbose \
  --sign "Apple Development: your.email@example.com" \
  --options runtime \
  --entitlements MacGuard.entitlements \
  dist/MacGuard.app

# Verify signature
codesign --verify --verbose dist/MacGuard.app
spctl --assess --verbose dist/MacGuard.app
```

### 4. Notarization (Optional)
Notarization allows Gatekeeper to verify app without right-click → Open.

```bash
# Create notarization-ready DMG
xcrun notarytool submit dist/MacGuard-1.3.4.dmg \
  --apple-id your.email@example.com \
  --team-id YOUR_TEAM_ID \
  --password YOUR_APP_SPECIFIC_PASSWORD \
  --wait

# Staple notarization ticket to DMG
xcrun stapler staple dist/MacGuard-1.3.4.dmg
```

**Requirements:**
- App-specific password (generate at appleid.apple.com)
- Team ID (found in Apple Developer portal)

---

## Sparkle Appcast Configuration

### 1. Generate EdDSA Keys (One-Time Setup)
```bash
# Generate key pair
./.build/artifacts/sparkle/Sparkle/bin/generate_keys

# Output:
# - Private key: Save to 1Password/Keychain (NEVER commit to Git)
# - Public key: Add to Info.plist (SUPublicEDKey)
```

**Add public key to `Info.plist`:**
```xml
<key>SUPublicEDKey</key>
<string>hOFyiKPFGLs9oXEU5vb9r8jA+LfbgOMRMqgxJm37tnY=</string>
```

### 2. Sign DMG with EdDSA
```bash
# Sign DMG (generates EdDSA signature)
./.build/artifacts/sparkle/Sparkle/bin/sign_update \
  dist/MacGuard-1.3.4.dmg \
  --ed-key-file path/to/private_key

# Output: EdDSA signature (e.g., MC0CFQDg7N...)
```

### 3. Update appcast.xml
Edit `appcast.xml` with new release details:

```xml
<item>
    <title>Version 1.3.4</title>
    <description>
        <![CDATA[
            <h2>What's New in v1.3.4</h2>
            <ul>
                <li>Comprehensive documentation</li>
                <li>Bug fixes and performance improvements</li>
            </ul>
        ]]>
    </description>
    <pubDate>Thu, 19 Dec 2024 10:00:00 +0000</pubDate>
    <enclosure
        url="https://github.com/shenglong209/MacGuard/releases/download/v1.3.4/MacGuard-1.3.4.dmg"
        sparkle:version="1.3.4"
        sparkle:shortVersionString="1.3.4"
        length="15728640"
        type="application/octet-stream"
        sparkle:edSignature="MC0CFQDg7N..." />
</item>
```

### 4. Get DMG File Size
```bash
# Get file size in bytes
stat -f%z dist/MacGuard-1.3.4.dmg
```

### 5. Commit and Push appcast.xml
```bash
git add appcast.xml
git commit -m "chore: update appcast for v1.3.4"
git push origin main
```

---

## Manual Release Process

### 1. Bump Version
Edit `Info.plist`:
```xml
<key>CFBundleShortVersionString</key>
<string>1.3.4</string>
<key>CFBundleVersion</key>
<string>2</string>
```

Update `README.md` version references.

### 2. Build and Create DMG
```bash
swift build -c release
./scripts/create-dmg.sh 1.3.4
```

### 3. Sign DMG (EdDSA)
```bash
./.build/artifacts/sparkle/Sparkle/bin/sign_update \
  dist/MacGuard-1.3.4.dmg \
  --ed-key-file path/to/private_key
```

### 4. Create GitHub Release
Navigate to GitHub repository → Releases → Draft a new release

- **Tag version:** v1.3.4
- **Release title:** MacGuard v1.3.4
- **Description:** Changelog and features
- **Upload DMG:** Attach `dist/MacGuard-1.3.4.dmg`

### 5. Update appcast.xml
Update `appcast.xml` with release details (see above).

### 6. Commit and Push
```bash
git add Info.plist appcast.xml README.md
git commit -m "chore: release v1.3.4"
git tag v1.3.4
git push origin main --tags
```

---

## Automated Release (GitHub Actions)

### Workflow Overview
GitHub Actions automates the entire release process:
1. Trigger on PR merge to `main` or manual workflow_dispatch
2. Bump version based on PR labels
3. Build release binary
4. Create DMG
5. Sign appcast.xml
6. Create GitHub Release
7. Upload DMG
8. Update appcast.xml in repository

### Workflow File
Location: `.github/workflows/release.yml`

### Trigger Automated Release

#### Method 1: PR Merge with Label
1. Create PR with changes
2. Add label to PR:
   - `release:major` - Bump major version (e.g., 1.3.4 → 2.0.0)
   - `release:minor` - Bump minor version (e.g., 1.3.4 → 1.4.0)
   - `release:patch` - Bump patch version (e.g., 1.3.4 → 1.3.5) [default]
3. Merge PR to `main`
4. GitHub Actions automatically builds and releases

#### Method 2: Manual Workflow Dispatch
1. Navigate to GitHub repository → Actions → Release
2. Click "Run workflow"
3. Select branch (usually `main`)
4. Optionally specify version bump type
5. Click "Run workflow"

### GitHub Secrets Configuration

Required secrets (Settings → Secrets and variables → Actions):

| Secret | Description | Required |
|--------|-------------|----------|
| `SPARKLE_PRIVATE_KEY` | EdDSA private key for appcast signing | Yes |
| `SIGNING_CERTIFICATE_P12_BASE64` | Base64-encoded code signing certificate | No (optional) |
| `SIGNING_CERTIFICATE_PASSWORD` | Password for P12 certificate | No (optional) |

### Workflow Steps Explained

```yaml
# 1. Checkout repository
- uses: actions/checkout@v4

# 2. Setup certificate (optional)
- name: Setup certificate
  if: env.SIGNING_CERTIFICATE_P12_BASE64 != ''
  run: ./scripts/setup-certificate.sh

# 3. Build release
- name: Build release
  run: swift build -c release

# 4. Create DMG
- name: Create DMG
  run: ./scripts/create-dmg.sh ${{ env.VERSION }}

# 5. Sign appcast
- name: Sign appcast
  run: |
    echo "${{ secrets.SPARKLE_PRIVATE_KEY }}" > private_key
    ./.build/artifacts/sparkle/Sparkle/bin/sign_update \
      dist/MacGuard-${{ env.VERSION }}.dmg \
      --ed-key-file private_key

# 6. Create GitHub Release
- uses: softprops/action-gh-release@v1
  with:
    tag_name: v${{ env.VERSION }}
    files: dist/MacGuard-${{ env.VERSION }}.dmg

# 7. Update appcast.xml
- name: Update appcast
  run: |
    # Update appcast.xml with new release
    git add appcast.xml
    git commit -m "chore: update appcast for v${{ env.VERSION }}"
    git push
```

### Monitoring Workflow
1. Navigate to GitHub repository → Actions
2. Select "Release" workflow
3. View logs for each step
4. Download artifacts if needed

---

## Distribution

### GitHub Releases
- **URL:** https://github.com/shenglong209/MacGuard/releases
- **Format:** DMG files attached to releases
- **Versioning:** Semantic versioning (v1.3.4)

### Sparkle Auto-Update
- **Feed URL:** https://raw.githubusercontent.com/shenglong209/MacGuard/main/appcast.xml
- **Update Check:** Daily (86400 seconds)
- **Delivery:** Automatic download and installation

### Direct Download
Users can download DMG directly from GitHub Releases:
1. Navigate to https://github.com/shenglong209/MacGuard/releases
2. Download `MacGuard-{version}.dmg`
3. Open DMG
4. Drag MacGuard.app to Applications folder
5. First launch: Right-click → Open (if unsigned)

---

## Installation Instructions for Users

### Standard Installation (DMG)
1. Download `MacGuard-1.3.4.dmg` from [GitHub Releases](https://github.com/shenglong209/MacGuard/releases)
2. Open the DMG file
3. Drag `MacGuard.app` to the `Applications` folder
4. **First launch (unsigned apps only):**
   - Right-click `MacGuard.app` → Click "Open"
   - Click "Open" in the dialog
   - **Alternative:** Run `xattr -cr /Applications/MacGuard.app` in Terminal

### Grant Permissions
1. Launch MacGuard
2. Click menu bar icon → Settings
3. Grant Accessibility permission:
   - Click "Grant" button
   - Enable MacGuard in System Preferences → Privacy & Security → Accessibility
4. (Optional) Grant Bluetooth permission for proximity auto-disarm
5. (Optional) Grant Administrator permission for lid close alarm

### Auto-Update Setup
MacGuard automatically checks for updates daily. Manual check:
1. Click menu bar icon → Settings
2. Scroll to "About" section
3. Click "Check for Updates"

---

## Build Scripts Reference

### scripts/create-dmg.sh
**Purpose:** Create distributable DMG from release binary

**Usage:**
```bash
./scripts/create-dmg.sh <version>
```

**Example:**
```bash
./scripts/create-dmg.sh 1.3.4
```

**Output:**
- `dist/MacGuard-1.3.4.dmg`

**Steps:**
1. Build release binary (`swift build -c release`)
2. Create `dist/MacGuard.app` bundle structure
3. Copy executable to `MacOS/`
4. Copy Sparkle.framework to `Frameworks/`
5. Copy resources (icons, audio) to `Resources/`
6. Copy `Info.plist` and entitlements
7. Create DMG with hdiutil
8. Compress DMG (UDZO format)

---

### scripts/release.sh
**Purpose:** Manual release trigger (bumps version, commits, tags)

**Usage:**
```bash
./scripts/release.sh <version>
```

**Example:**
```bash
./scripts/release.sh 1.4.0
```

**Steps:**
1. Update `Info.plist` with new version
2. Update `README.md` version references
3. Commit changes
4. Create git tag
5. Push to main with tags

**Note:** Does NOT build or create DMG. Use for version bumping only.

---

### scripts/setup-certificate.sh
**Purpose:** CI certificate setup (import P12 from GitHub secrets)

**Usage (GitHub Actions):**
```yaml
- name: Setup certificate
  if: env.SIGNING_CERTIFICATE_P12_BASE64 != ''
  env:
    SIGNING_CERTIFICATE_P12_BASE64: ${{ secrets.SIGNING_CERTIFICATE_P12_BASE64 }}
    SIGNING_CERTIFICATE_PASSWORD: ${{ secrets.SIGNING_CERTIFICATE_PASSWORD }}
  run: ./scripts/setup-certificate.sh
```

**Steps:**
1. Decode base64 P12 from environment variable
2. Create temporary keychain
3. Import certificate to keychain
4. Set keychain as default for codesign

---

### scripts/export-certificate.sh
**Purpose:** Export developer certificate for CI (run locally)

**Usage:**
```bash
./scripts/export-certificate.sh
```

**Steps:**
1. Export Apple Development certificate from Keychain
2. Generate password-protected P12 file
3. Encode P12 as base64
4. Print base64 string (copy to GitHub secrets)

**Output:**
- `Signing_Certificate.p12` (local file, DO NOT commit)
- Base64 string (printed to console)

---

## Troubleshooting

### Build Failures

#### "Cannot find module 'Sparkle'"
**Cause:** Dependencies not resolved
**Solution:**
```bash
swift package resolve
swift build -c release
```

#### "Code signing failed"
**Cause:** Certificate not found or expired
**Solution:**
1. Verify certificate in Keychain Access
2. Update certificate if expired
3. Re-export and update GitHub secrets

---

### DMG Creation Failures

#### "hdiutil: create failed - Resource busy"
**Cause:** DMG already mounted
**Solution:**
```bash
# Unmount all volumes
hdiutil detach /Volumes/MacGuard

# Retry
./scripts/create-dmg.sh 1.3.4
```

#### "Missing resources in .app bundle"
**Cause:** Resources/ directory not copied correctly
**Solution:**
1. Verify `Resources/` directory exists
2. Check `create-dmg.sh` script for correct paths
3. Rebuild DMG

---

### Sparkle Update Failures

#### "Update signature verification failed"
**Cause:** EdDSA signature mismatch or missing
**Solution:**
1. Re-sign DMG with correct private key
2. Update appcast.xml with new signature
3. Verify public key in Info.plist matches private key

#### "Update download failed"
**Cause:** DMG URL not accessible or GitHub Release not created
**Solution:**
1. Verify DMG uploaded to GitHub Release
2. Check URL in appcast.xml (should be `https://github.com/shenglong209/MacGuard/releases/download/v1.3.4/MacGuard-1.3.4.dmg`)
3. Test URL in browser

---

### Permission Issues

#### "Accessibility permission lost after update"
**Cause:** App not code-signed (bundle identifier changed)
**Solution:**
1. Code sign all releases
2. Use same certificate for all builds
3. Users may need to re-grant permission (one-time)

---

## Testing Checklist

### Pre-Release Testing
- [ ] Debug build runs without crashes
- [ ] Release build runs without crashes
- [ ] DMG mounts and .app launches correctly
- [ ] All monitors function (input, sleep, power, Bluetooth)
- [ ] State transitions work correctly (idle → armed → triggered → alarming)
- [ ] Authentication works (Touch ID + PIN)
- [ ] Audio playback at max volume
- [ ] Settings persist across restarts
- [ ] Sparkle update check works (manual)
- [ ] No console errors or warnings

### Post-Release Testing
- [ ] DMG downloads from GitHub Release
- [ ] First launch UX acceptable (right-click → Open if unsigned)
- [ ] Permissions grant correctly (Accessibility, Bluetooth)
- [ ] Auto-update detects new version (wait 24 hours or adjust interval)
- [ ] Auto-update downloads and installs correctly
- [ ] Accessibility permission preserved after update (if code-signed)

---

## Performance Benchmarks

### Build Times
| Build Type | Time (M1 MacBook Pro) |
|------------|----------------------|
| Debug build | ~10 seconds |
| Release build | ~15 seconds |
| DMG creation | ~30 seconds |

### Binary Sizes
| Artifact | Size |
|----------|------|
| Debug binary | ~20 MB |
| Release binary | ~12 MB |
| MacGuard.app bundle | ~25 MB (with Sparkle) |
| DMG (compressed) | ~15 MB |

---

## Best Practices

### Version Numbering
- **Major:** Breaking changes, major redesigns (1.0.0 → 2.0.0)
- **Minor:** New features, non-breaking changes (1.3.4 → 1.4.0)
- **Patch:** Bug fixes, minor improvements (1.3.4 → 1.3.5)

### Changelog Maintenance
Update `appcast.xml` release notes with:
- New features
- Bug fixes
- Breaking changes
- Known issues

### Code Signing
- Always code sign releases for production
- Use same certificate for all builds (preserve permissions)
- Test unsigned builds locally before signing

### Sparkle Security
- Never commit EdDSA private key to Git
- Store private key in 1Password/Keychain
- Rotate keys if compromised
- Verify signatures before releasing

---

## Resources

### Documentation
- [Sparkle Documentation](https://sparkle-project.org/documentation/)
- [Apple Code Signing Guide](https://developer.apple.com/documentation/xcode/code-signing-overview)
- [Swift Package Manager](https://www.swift.org/documentation/package-manager/)

### Tools
- [Xcode](https://developer.apple.com/xcode/)
- [Sparkle Framework](https://github.com/sparkle-project/Sparkle)
- [GitHub Actions](https://github.com/features/actions)

### Support
- [GitHub Issues](https://github.com/shenglong209/MacGuard/issues)
- [GitHub Discussions](https://github.com/shenglong209/MacGuard/discussions)
