#!/bin/bash
# release.sh - Trigger a new MacGuard release
# Usage: ./scripts/release.sh [patch|minor|major]
# Example: ./scripts/release.sh patch
#
# This script bumps the version and pushes to main.
# GitHub Actions handles the rest (build, sign, release, appcast update).

set -e

BUMP_TYPE="${1:-patch}"
INFO_PLIST="Info.plist"

# Validate bump type
case "$BUMP_TYPE" in
    major|minor|patch) ;;
    *)
        echo "Usage: ./scripts/release.sh [patch|minor|major]"
        echo "  patch: 1.3.2 -> 1.3.3 (default)"
        echo "  minor: 1.3.2 -> 1.4.0"
        echo "  major: 1.3.2 -> 2.0.0"
        exit 1
        ;;
esac

# Ensure working directory is clean
if [ -n "$(git status --porcelain)" ]; then
    echo "❌ Working directory has uncommitted changes. Please commit or stash first."
    exit 1
fi

# Ensure we're on main branch
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo "❌ Not on main branch (currently on: $CURRENT_BRANCH)"
    echo "   Switch to main: git checkout main"
    exit 1
fi

# Pull latest changes
echo "📥 Pulling latest changes..."
git pull --rebase

# Extract current version
CURRENT_VERSION=$(grep -A1 'CFBundleShortVersionString' "$INFO_PLIST" | grep string | sed 's/.*<string>\(.*\)<\/string>.*/\1/')

if [ -z "$CURRENT_VERSION" ]; then
    echo "❌ Could not find version in $INFO_PLIST"
    exit 1
fi

# Parse and bump version
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

case "$BUMP_TYPE" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"

echo ""
echo "=== MacGuard Release ==="
echo "📦 Version: $CURRENT_VERSION -> $NEW_VERSION ($BUMP_TYPE)"
echo ""

# Confirm
read -p "Proceed with release? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Update Info.plist
sed -i '' "s/<string>$CURRENT_VERSION<\/string>/<string>$NEW_VERSION<\/string>/" "$INFO_PLIST"
echo "✅ Version bumped to $NEW_VERSION"

# Commit and push
git add "$INFO_PLIST"
git commit -m "chore: release v$NEW_VERSION"
git push

echo ""
echo "=== Release Triggered ==="
echo "✅ Pushed to main"
echo "🚀 GitHub Actions will build and release v$NEW_VERSION"
echo ""
echo "Monitor: https://github.com/shenglong209/MacGuard/actions"
echo "Release: https://github.com/shenglong209/MacGuard/releases/tag/v$NEW_VERSION (after CI completes)"
