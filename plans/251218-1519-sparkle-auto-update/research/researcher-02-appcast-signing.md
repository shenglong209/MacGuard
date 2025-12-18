# Sparkle Appcast & EdDSA Signing Research

## 1. Appcast.xml Format

### Required Fields

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>MacGuard Changelog</title>
    <link>https://github.com/yourusername/MacGuard</link>
    <description>MacGuard Updates</description>
    <language>en</language>

    <item>
      <title>Version 1.0.1</title>
      <link>https://github.com/yourusername/MacGuard/releases/tag/v1.0.1</link>
      <sparkle:version>1.0.1</sparkle:version>
      <sparkle:shortVersionString>1.0.1</sparkle:shortVersionString>
      <description><![CDATA[
        <h3>Bug Fixes</h3>
        <ul>
          <li>Fixed Bluetooth detection</li>
          <li>Improved menu bar UI</li>
        </ul>
      ]]></description>
      <pubDate>Wed, 18 Dec 2025 10:00:00 +0000</pubDate>
      <enclosure
        url="https://github.com/yourusername/MacGuard/releases/download/v1.0.1/MacGuard-1.0.1.dmg"
        sparkle:edSignature="BASE64_SIGNATURE_HERE"
        length="12345678"
        type="application/octet-stream"
      />
    </item>
  </channel>
</rss>
```

### Critical Fields
- `<sparkle:version>`: CFBundleVersion (must increment)
- `<sparkle:shortVersionString>`: CFBundleShortVersionString (user-facing)
- `<enclosure url="">`: HTTPS download URL (required by ATS)
- `sparkle:edSignature`: EdDSA signature (mandatory for security)
- `length`: File size in bytes
- `<pubDate>`: RFC 822 format

### Optional Advanced Fields
- `<sparkle:releaseNotesLink>`: External HTML changelog
- `<sparkle:minimumSystemVersion>`: e.g., "10.13.0"
- `<sparkle:maximumSystemVersion>`: Restrict to max version
- `<sparkle:criticalUpdate>`: Force install, no skip option
- `<sparkle:minimumAutoupdateVersion>`: Block auto-install, show UI instead
- `<sparkle:phasedRolloutInterval>`: Seconds between rollout groups (7 groups)
- `<sparkle:channel>`: Beta/staged releases (requires delegate)

## 2. EdDSA Key Generation

### One-Time Setup

```bash
# Download Sparkle distribution
curl -LO https://github.com/sparkle-project/Sparkle/releases/latest/download/Sparkle-2.x.x.tar.xz
tar -xf Sparkle-2.x.x.tar.xz

# Generate EdDSA key pair (run once)
./bin/generate_keys

# Output:
# Private key saved to Mac Keychain
# Public key (base64): AbCdEf1234567890...
```

### Add Public Key to Info.plist

```xml
<key>SUPublicEDKey</key>
<string>AbCdEf1234567890...</string>
```

### Key Management Commands

```bash
# Export private key to file
./bin/generate_keys -x private-key.txt

# Import private key from file
./bin/generate_keys -f private-key.txt

# Regenerate to view public key again
./bin/generate_keys
```

**Security**: Store private key in Keychain or secure CI/CD secrets. Never commit to repo.

## 3. Signing DMG Files

### Manual Signing

```bash
# Sign update file
./bin/sign_update MacGuard-1.0.1.dmg

# Output:
# sparkle:edSignature="mc3N8JqZHGzFYLl6..." length="12345678"
```

### Sign with External Key File

```bash
./bin/sign_update MacGuard-1.0.1.dmg -s private-key.txt
```

### Automated Appcast Generation

```bash
# Create updates folder structure
mkdir -p updates_folder
cp MacGuard-1.0.1.dmg updates_folder/

# Optional: Add release notes HTML (same basename)
echo "<h3>Bug Fixes</h3>..." > updates_folder/MacGuard-1.0.1.html

# Generate appcast (auto-signs, creates deltas)
./bin/generate_appcast updates_folder/

# Output:
# - appcast.xml (uses SUFeedURL from Info.plist)
# - .delta files for incremental updates
# - All signatures embedded
```

### Supported Archive Formats

```bash
# ZIP (preserves symlinks)
ditto -c -k --sequesterRsrc --keepParent MacGuard.app MacGuard.zip

# TAR (strips extended attributes)
tar --no-xattrs -cJf MacGuard.tar.xz MacGuard.app

# DMG (APFS + lzfse compression recommended)
# Use Disk Utility or hdiutil
```

## 4. Hosting on GitHub

### Option A: GitHub Releases (Recommended)

```bash
# DMG URL pattern:
https://github.com/USERNAME/REPO/releases/download/v1.0.1/MacGuard-1.0.1.dmg

# Advantages:
# - Native release management
# - Download statistics
# - Asset management UI
```

### Option B: GitHub Pages

```bash
# Appcast URL:
https://USERNAME.github.io/REPO/appcast.xml

# Setup:
# 1. Enable GitHub Pages in repo settings
# 2. Choose branch (e.g., gh-pages or main/docs)
# 3. Upload appcast.xml to published directory
```

### Option C: Raw githubusercontent.com

```bash
# Appcast URL:
https://raw.githubusercontent.com/USERNAME/REPO/main/appcast.xml

# Limitations:
# - No caching control
# - Not recommended for production (use GitHub Pages instead)
```

### Info.plist Configuration

```xml
<key>SUFeedURL</key>
<string>https://raw.githubusercontent.com/USERNAME/REPO/main/appcast.xml</string>
```

## 5. Automating Appcast Generation

### GitHub Actions Workflow Example

```yaml
name: Release

on:
  release:
    types: [published]

jobs:
  build:
    runs-on: macos-latest

    steps:
      - uses: actions/checkout@v4

      - name: Download Sparkle Tools
        run: |
          curl -LO https://github.com/sparkle-project/Sparkle/releases/latest/download/Sparkle-2.6.4.tar.xz
          tar -xf Sparkle-2.6.4.tar.xz

      - name: Import EdDSA Private Key
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: |
          echo "$SPARKLE_PRIVATE_KEY" > private-key.txt
          ./bin/generate_keys -f private-key.txt

      - name: Build DMG
        run: |
          # Your DMG build script
          ./build-dmg.sh

      - name: Sign Update
        run: |
          SIGNATURE=$(./bin/sign_update dist/MacGuard-${{ github.ref_name }}.dmg)
          echo "SIGNATURE=$SIGNATURE" >> $GITHUB_ENV

      - name: Generate Appcast
        run: |
          mkdir -p updates
          cp dist/MacGuard-${{ github.ref_name }}.dmg updates/
          ./bin/generate_appcast updates/ -o appcast.xml

      - name: Upload to Release
        uses: softprops/action-gh-release@v1
        with:
          files: |
            dist/MacGuard-${{ github.ref_name }}.dmg
            appcast.xml

      - name: Update Appcast URL in File
        run: |
          # Update enclosure URL to GitHub release URL
          sed -i '' "s|url=\".*\"|url=\"https://github.com/${{ github.repository }}/releases/download/${{ github.ref_name }}/MacGuard-${{ github.ref_name }}.dmg\"|" appcast.xml

      - name: Commit Updated Appcast
        run: |
          git config user.name github-actions
          git config user.email github-actions@github.com
          git add appcast.xml
          git commit -m "Update appcast for ${{ github.ref_name }}"
          git push
```

### Shell Script Automation

```bash
#!/bin/bash
# release.sh - Automate Sparkle release process

set -e

VERSION=$1
DMG_PATH="dist/MacGuard-${VERSION}.dmg"
UPDATES_DIR="updates"
APPCAST="appcast.xml"

# Validate
if [ -z "$VERSION" ]; then
  echo "Usage: ./release.sh VERSION"
  exit 1
fi

# Setup
mkdir -p "$UPDATES_DIR"
cp "$DMG_PATH" "$UPDATES_DIR/"

# Generate appcast with signatures
./bin/generate_appcast "$UPDATES_DIR/" -o "$APPCAST"

# Upload to GitHub release
gh release create "v${VERSION}" \
  "$DMG_PATH" \
  "$APPCAST" \
  --title "Version ${VERSION}" \
  --notes-file CHANGELOG.md

# Update appcast URL to point to GitHub release
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
sed -i '' "s|url=\".*\\.dmg\"|url=\"https://github.com/${REPO}/releases/download/v${VERSION}/MacGuard-${VERSION}.dmg\"|" "$APPCAST"

# Commit updated appcast to repo
git add "$APPCAST"
git commit -m "Update appcast for v${VERSION}"
git push

echo "✓ Release v${VERSION} published"
echo "✓ Appcast updated at: https://raw.githubusercontent.com/${REPO}/main/appcast.xml"
```

### Makefile Integration

```makefile
SPARKLE_BIN = ./Sparkle/bin
VERSION = $(shell defaults read $(PWD)/MacGuard/Info.plist CFBundleShortVersionString)
DMG = dist/MacGuard-$(VERSION).dmg

.PHONY: release
release: $(DMG)
	mkdir -p updates
	cp $(DMG) updates/
	$(SPARKLE_BIN)/generate_appcast updates/ -o appcast.xml
	@echo "Appcast generated. Upload $(DMG) and appcast.xml"

.PHONY: sign
sign: $(DMG)
	$(SPARKLE_BIN)/sign_update $(DMG)
```

## Unresolved Questions

1. **Delta updates**: How large should app be before delta updates provide benefit? (Sparkle auto-generates for "large apps")
2. **Rollback strategy**: If critical bug in new version, best way to revert appcast to previous version?
3. **Multi-channel testing**: Should beta channel use separate appcast.xml or same file with channel tags?
4. **Key rotation**: Exact process for rotating EdDSA keys when compromised (docs mention support but not procedure)
5. **Phased rollout monitoring**: How to track which user group received update during phased rollout?

## Sources

- [Sparkle Documentation](https://sparkle-project.org/documentation/)
- [Sparkle Publishing Guide](https://sparkle-project.org/documentation/publishing/)
- [Sparkle GitHub Repository](https://github.com/sparkle-project/Sparkle)
