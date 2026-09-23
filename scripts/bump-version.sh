#!/bin/bash
# Bump version in Xcode project
# Usage: ./scripts/bump-version.sh [major|minor|patch]

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="${PROJECT_DIR}/AmpX.xcodeproj/project.pbxproj"

# Get current version
CURRENT_VERSION=$(grep -A 1 "MARKETING_VERSION" "$PROJECT_FILE" | grep -oE "[0-9]+\.[0-9]+(\.[0-9]+)?" | head -n 1)

if [ -z "$CURRENT_VERSION" ]; then
    echo "❌ Could not determine current version"
    exit 1
fi

# Parse version components
IFS='.' read -ra VERSION_PARTS <<< "$CURRENT_VERSION"
MAJOR=${VERSION_PARTS[0]}
MINOR=${VERSION_PARTS[1]}
PATCH=${VERSION_PARTS[2]:-0}

# Determine bump type
BUMP_TYPE=${1:-patch}

case $BUMP_TYPE in
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
        echo "❌ Invalid bump type: $BUMP_TYPE"
        echo "Usage: ./scripts/bump-version.sh [major|minor|patch]"
        exit 1
        ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"

echo "📦 Bumping version: $CURRENT_VERSION -> $NEW_VERSION"

# Update version in project file (both Debug and Release configurations)
# Use platform-appropriate sed command
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/MARKETING_VERSION = ${CURRENT_VERSION};/MARKETING_VERSION = ${NEW_VERSION};/g" "$PROJECT_FILE"
else
    # Linux
    sed -i "s/MARKETING_VERSION = ${CURRENT_VERSION};/MARKETING_VERSION = ${NEW_VERSION};/g" "$PROJECT_FILE"
fi

echo "✅ Version updated to $NEW_VERSION"

