# Phase 3: Release Automation

## Tasks

### 3.1 Create Initial appcast.xml

**New File:** `appcast.xml` (repo root)

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>MacGuard Updates</title>
    <link>https://github.com/shenglong209/MacGuard</link>
    <description>MacGuard anti-theft alarm for macOS</description>
    <language>en</language>

    <!-- Latest release will be added here by release script -->

  </channel>
</rss>
```

### 3.2 Create Release Script

**New File:** `scripts/release.sh`

```bash
#!/bin/bash
# release.sh - Automate MacGuard release with Sparkle signing
# Usage: ./scripts/release.sh VERSION
# Example: ./scripts/release.sh 1.2.0

set -e

VERSION=$1
if [ -z "$VERSION" ]; then
  echo "Usage: ./scripts/release.sh VERSION"
  echo "Example: ./scripts/release.sh 1.2.0"
  exit 1
fi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DMG_PATH="$PROJECT_DIR/dist/MacGuard-${VERSION}.dmg"
APPCAST_PATH="$PROJECT_DIR/appcast.xml"
SPARKLE_BIN="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin"

echo "=== MacGuard Release v${VERSION} ==="

# Step 1: Verify DMG exists
if [ ! -f "$DMG_PATH" ]; then
  echo "❌ DMG not found: $DMG_PATH"
  echo "Run create-dmg.sh first"
  exit 1
fi

# Step 2: Sign the DMG
echo "📝 Signing DMG with EdDSA..."
SIGNATURE=$("$SPARKLE_BIN/sign_update" "$DMG_PATH")
echo "Signature: $SIGNATURE"

# Extract signature and length from output
# Format: sparkle:edSignature="xxx" length="yyy"
ED_SIGNATURE=$(echo "$SIGNATURE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
FILE_LENGTH=$(echo "$SIGNATURE" | sed -n 's/.*length="\([^"]*\)".*/\1/p')

if [ -z "$ED_SIGNATURE" ]; then
  echo "❌ Failed to extract signature"
  exit 1
fi

echo "✅ EdDSA Signature: ${ED_SIGNATURE:0:20}..."
echo "✅ File Length: $FILE_LENGTH bytes"

# Step 3: Get current date in RFC 822 format
PUB_DATE=$(date -R)

# Step 4: Create new appcast item
ITEM="    <item>
      <title>Version ${VERSION}</title>
      <link>https://github.com/shenglong209/MacGuard/releases/tag/v${VERSION}</link>
      <sparkle:version>${VERSION//./}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h3>What's New in ${VERSION}</h3>
        <p>See release notes on GitHub.</p>
      ]]></description>
      <pubDate>${PUB_DATE}</pubDate>
      <enclosure
        url=\"https://github.com/shenglong209/MacGuard/releases/download/v${VERSION}/MacGuard-${VERSION}.dmg\"
        sparkle:edSignature=\"${ED_SIGNATURE}\"
        length=\"${FILE_LENGTH}\"
        type=\"application/octet-stream\"
      />
    </item>"

# Step 5: Insert item into appcast (after <language> line)
echo "📄 Updating appcast.xml..."

# Use awk to insert after </language> line
awk -v item="$ITEM" '
  /<\/language>/ {
    print
    print ""
    print item
    next
  }
  { print }
' "$APPCAST_PATH" > "$APPCAST_PATH.tmp"
mv "$APPCAST_PATH.tmp" "$APPCAST_PATH"

echo "✅ appcast.xml updated"

# Step 6: Create GitHub release
echo "🚀 Creating GitHub release..."
gh release create "v${VERSION}" \
  "$DMG_PATH" \
  --title "MacGuard v${VERSION}" \
  --notes "## MacGuard v${VERSION}

### Changes
- See commit history for details

### Installation
1. Download MacGuard-${VERSION}.dmg
2. Open DMG and drag MacGuard to Applications
3. Launch from Applications folder

### Auto-Update
If you have a previous version installed, use Check for Updates in Settings."

echo "✅ GitHub release created"

# Step 7: Commit updated appcast
echo "📦 Committing appcast..."
git add "$APPCAST_PATH"
git commit -m "chore: update appcast for v${VERSION}"
git push

echo ""
echo "=== Release Complete ==="
echo "✅ DMG signed and uploaded"
echo "✅ appcast.xml updated and pushed"
echo "✅ GitHub release: https://github.com/shenglong209/MacGuard/releases/tag/v${VERSION}"
echo ""
echo "Users will receive update notification on next app launch."
```

Make executable:
```bash
chmod +x scripts/release.sh
```

### 3.3 Update create-dmg.sh for Release Workflow

Ensure `scripts/create-dmg.sh` outputs to `dist/MacGuard-${VERSION}.dmg` format.

Current script already does this - verify version is passed correctly.

### 3.4 GitHub Actions Workflow (Optional)

**New File:** `.github/workflows/release.yml`

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: macos-14

    steps:
      - uses: actions/checkout@v4

      - name: Build Release
        run: swift build -c release

      - name: Create DMG
        run: ./scripts/create-dmg.sh ${GITHUB_REF_NAME#v}

      - name: Import Sparkle Key
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: |
          echo "$SPARKLE_PRIVATE_KEY" > sparkle-key.txt
          .build/artifacts/sparkle/Sparkle/bin/generate_keys -f sparkle-key.txt
          rm sparkle-key.txt

      - name: Sign and Release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: ./scripts/release.sh ${GITHUB_REF_NAME#v}
```

**Setup Required:**
1. Add `SPARKLE_PRIVATE_KEY` to repo secrets (base64-encoded private key)
2. Enable GitHub Actions in repo settings

## Release Workflow

### Manual Release (Recommended for First Release)

```bash
# 1. Update version in Info.plist and SettingsView.swift
# CFBundleVersion: 2
# CFBundleShortVersionString: 1.2.0

# 2. Build release
swift build -c release

# 3. Create DMG
./scripts/create-dmg.sh 1.2.0

# 4. Run release script
./scripts/release.sh 1.2.0

# 5. Create PR for appcast update (or merge directly)
```

### Automated Release (After CI Setup)

```bash
# Just push a version tag
git tag v1.2.0
git push origin v1.2.0
# GitHub Actions handles the rest
```

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `appcast.xml` | Create | Update feed (repo root) |
| `scripts/release.sh` | Create | Signing and release automation |
| `.github/workflows/release.yml` | Create (optional) | CI/CD automation |

## Verification Checklist

- [ ] appcast.xml created and committed
- [ ] release.sh works with test DMG
- [ ] Signature extracted correctly
- [ ] appcast.xml updated with new item
- [ ] GitHub release created with DMG attached
- [ ] App can fetch appcast.xml from raw.githubusercontent.com
- [ ] End-to-end update test passes

## Testing Update Flow

1. Install current version (e.g., 1.1.0)
2. Create new release (1.2.0) using release.sh
3. Launch old version
4. Go to Settings → Check for Updates
5. Verify update dialog appears with version 1.2.0
6. Click Update → DMG downloads → App updates

## Notes

- First release with Sparkle requires manual EdDSA key setup (Phase 1)
- GitHub Actions secret must contain exported private key
- appcast.xml should be committed to main branch for raw.githubusercontent.com URL
- Keep old release items in appcast for delta update generation (future)
