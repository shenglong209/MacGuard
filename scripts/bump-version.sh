#!/bin/bash
# bump-version.sh - Bump version in Info.plist
# Usage: ./scripts/bump-version.sh [major|minor|patch]
# Example: ./scripts/bump-version.sh patch  # 1.3.2 -> 1.3.3

set -e

BUMP_TYPE="${1:-patch}"
INFO_PLIST="Info.plist"

# Extract current version
CURRENT_VERSION=$(grep -A1 'CFBundleShortVersionString' "$INFO_PLIST" | grep string | sed 's/.*<string>\(.*\)<\/string>.*/\1/')

if [ -z "$CURRENT_VERSION" ]; then
    echo "❌ Could not find version in $INFO_PLIST"
    exit 1
fi

# Parse version components
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# Bump based on type
case "$BUMP_TYPE" in
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    patch)
        PATCH=$((PATCH + 1))
        ;;
    *)
        echo "Usage: ./scripts/bump-version.sh [major|minor|patch]"
        echo "  major: 1.3.2 -> 2.0.0"
        echo "  minor: 1.3.2 -> 1.4.0"
        echo "  patch: 1.3.2 -> 1.3.3"
        exit 1
        ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"

# Update Info.plist
sed -i '' "s/<string>$CURRENT_VERSION<\/string>/<string>$NEW_VERSION<\/string>/" "$INFO_PLIST"

echo "✅ Version bumped: $CURRENT_VERSION -> $NEW_VERSION"
echo ""
echo "Next steps:"
echo "  git add Info.plist"
echo "  git commit -m \"chore: bump version to $NEW_VERSION\""
echo "  git push"
echo ""
echo "CI will automatically build and release v$NEW_VERSION"
