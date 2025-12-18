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
  echo "Run: ./scripts/create-dmg.sh $VERSION"
  exit 1
fi

# Step 2: Verify Sparkle tools exist
if [ ! -f "$SPARKLE_BIN/sign_update" ]; then
  echo "❌ Sparkle tools not found. Run 'swift build' first."
  exit 1
fi

# Step 3: Sign the DMG
echo "📝 Signing DMG with EdDSA..."
SIGNATURE=$("$SPARKLE_BIN/sign_update" "$DMG_PATH")
echo "Signature output: $SIGNATURE"

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

# Step 4: Get current date in RFC 822 format (English locale required)
PUB_DATE=$(LC_TIME=C date "+%a, %d %b %Y %H:%M:%S %z")

# Step 5: Calculate build number from version (e.g., 1.2.0 -> 120)
BUILD_NUM=${VERSION//./}

# Step 6: Create new appcast item
ITEM="    <item>
      <title>Version ${VERSION}</title>
      <link>https://github.com/shenglong209/MacGuard/releases/tag/v${VERSION}</link>
      <sparkle:version>${BUILD_NUM}</sparkle:version>
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

# Step 7: Insert item into appcast (after </language> line)
echo "📄 Updating appcast.xml..."

# Write item to temp file (avoids BSD awk multiline string limitation)
ITEM_FILE=$(mktemp)
echo "$ITEM" > "$ITEM_FILE"

# Use sed to insert after </language> line (macOS compatible)
sed -i '' "/<\/language>/r $ITEM_FILE" "$APPCAST_PATH"

# Cleanup temp file
rm -f "$ITEM_FILE"

echo "✅ appcast.xml updated"

# Step 8: Create GitHub release
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

# Step 9: Commit updated appcast
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
