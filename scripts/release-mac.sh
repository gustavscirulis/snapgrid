#!/bin/bash
set -e

# SnapGrid Mac App Release Script
# Builds, signs, notarizes, and publishes a draft GitHub release for the native Mac app.
#
# Usage:
#   ./scripts/release-mac.sh           - Build, notarize, and publish to GitHub
#   ./scripts/release-mac.sh --local   - Build and notarize only (no upload)
#
# Required .env variables:
#   APPLE_ID                      - Apple ID email for notarization
#   APPLE_APP_SPECIFIC_PASSWORD   - App-specific password
#   APPLE_TEAM_ID                 - Apple Developer Team ID
#   GH_TOKEN                      - GitHub personal access token (repo scope, not needed for --local)
#
# Prerequisites:
#   - Xcode 16+
#   - xcodegen (`brew install xcodegen`)
#   - Sparkle EdDSA private key in Keychain (run `generate_keys` once)

LOCAL_ONLY=false
if [ "$1" = "--local" ]; then
  LOCAL_ONLY=true
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../SnapGrid" && pwd)"
BUILD_DIR="$SCRIPT_DIR/../build/mac"

# Load .env
if [ -f "$SCRIPT_DIR/../.env" ]; then
  echo "Loading credentials from .env..."
  export $(grep -v '^#' "$SCRIPT_DIR/../.env" | xargs)
else
  echo "Error: .env file not found."
  echo ""
  echo "Create a .env file with:"
  echo "  APPLE_ID=your@email.com"
  echo "  APPLE_APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx"
  echo "  APPLE_TEAM_ID=XXXXXXXXXX"
  echo "  GH_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  exit 1
fi

# Validate required variables
missing=()
[ -z "$APPLE_ID" ] && missing+=("APPLE_ID")
[ -z "$APPLE_APP_SPECIFIC_PASSWORD" ] && missing+=("APPLE_APP_SPECIFIC_PASSWORD")
[ -z "$APPLE_TEAM_ID" ] && missing+=("APPLE_TEAM_ID")
[ "$LOCAL_ONLY" = false ] && [ -z "$GH_TOKEN" ] && missing+=("GH_TOKEN")

if [ ${#missing[@]} -gt 0 ]; then
  echo "Error: Missing required environment variables:"
  for var in "${missing[@]}"; do
    echo "  - $var"
  done
  exit 1
fi

# Read version from project.yml
VERSION=$(grep 'MARKETING_VERSION:' "$PROJECT_DIR/project.yml" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
BUILD_NUMBER=$(grep 'CURRENT_PROJECT_VERSION:' "$PROJECT_DIR/project.yml" | head -1 | sed 's/.*: *\([0-9]*\)/\1/')

if [ -z "$VERSION" ]; then
  echo "Error: Could not read MARKETING_VERSION from project.yml"
  exit 1
fi

echo ""
if [ "$LOCAL_ONLY" = true ]; then
  echo "Building SnapGrid Mac v${VERSION} (${BUILD_NUMBER}) locally (no upload)..."
else
  echo "Publishing SnapGrid Mac v${VERSION} (${BUILD_NUMBER}) as a draft release..."
fi
echo ""

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Regenerate Xcode project
echo "Regenerating Xcode project..."
cd "$PROJECT_DIR"
xcodegen generate

# Build archive
echo "Building archive..."
xcodebuild archive \
  -project "$PROJECT_DIR/SnapGrid.xcodeproj" \
  -scheme SnapGrid \
  -archivePath "$BUILD_DIR/SnapGrid.xcarchive" \
  -configuration Release \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  CODE_SIGN_STYLE=Manual \
  | tail -1

# Export .app
echo "Exporting app..."
xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/SnapGrid.xcarchive" \
  -exportPath "$BUILD_DIR/export" \
  -exportOptionsPlist "$SCRIPT_DIR/ExportOptions.plist" \
  | tail -1

APP_PATH="$BUILD_DIR/export/SnapGrid.app"
DMG_NAME="SnapGrid-Mac-${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

if [ ! -d "$APP_PATH" ]; then
  echo "Error: App export failed. $APP_PATH not found."
  exit 1
fi

# Create DMG
echo "Creating DMG..."
hdiutil create \
  -volname "SnapGrid" \
  -srcfolder "$APP_PATH" \
  -ov -format UDZO \
  "$DMG_PATH"

# Notarize DMG
echo "Notarizing DMG..."
xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

# Sign with Sparkle EdDSA key
echo "Generating Sparkle EdDSA signature..."
SPARKLE_BIN=$(find "$PROJECT_DIR/SnapGrid.xcodeproj" -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" 2>/dev/null | head -1)

if [ -z "$SPARKLE_BIN" ]; then
  # Fallback: look in DerivedData
  SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" 2>/dev/null | head -1)
fi

if [ -z "$SPARKLE_BIN" ]; then
  echo "Warning: Could not find Sparkle sign_update tool. Skipping EdDSA signing."
  echo "You may need to build the project in Xcode first to download Sparkle artifacts."
  EDDSA_ATTRS=""
else
  EDDSA_OUTPUT=$("$SPARKLE_BIN" "$DMG_PATH")
  echo "EdDSA signature: $EDDSA_OUTPUT"
  EDDSA_ATTRS="$EDDSA_OUTPUT"
fi

# Generate release notes from git log
generate_release_notes() {
  local prev_tag
  prev_tag=$(git tag -l "mac-v*" --sort=-version:refname | head -1 2>/dev/null || echo "")

  if [ -z "$prev_tag" ]; then
    echo "No previous mac release tag found, skipping release notes."
    return 1
  fi

  echo "Generating release notes from ${prev_tag} to HEAD..."

  local bugs=""
  local improvements=""

  while IFS= read -r msg; do
    if echo "$msg" | grep -qiE '^bump version'; then
      continue
    fi

    clean=$(echo "$msg" | sed 's/ (#[0-9]*)$//')

    if echo "$clean" | grep -qiE '^(fix|disable)'; then
      entry=$(echo "$clean" | sed -E 's/^[Ff]ix(ed|es)?:?[[:space:]]*//' | sed -E 's/^[Dd]isable[ds]?:?[[:space:]]*//')
      entry="$(echo "${entry:0:1}" | tr '[:lower:]' '[:upper:]')${entry:1}"
      bugs="${bugs}- ${entry}\n"
    else
      entry=$(echo "$clean" | sed -E 's/^[Ff]eature:?[[:space:]]*//' \
        | sed -E 's/^[Ii]mprove[ds]?:?[[:space:]]*//' \
        | sed -E 's/^[Aa]dd(ed|s)?:?[[:space:]]*//' \
        | sed -E 's/^[Uu]pdate[ds]?:?[[:space:]]*//' \
        | sed -E 's/^[Ee]nable[ds]?:?[[:space:]]*//')
      entry="$(echo "${entry:0:1}" | tr '[:lower:]' '[:upper:]')${entry:1}"
      improvements="${improvements}- ${entry}\n"
    fi
  done < <(git log "${prev_tag}..HEAD" --first-parent --format="%s")

  local notes=""
  if [ -n "$bugs" ]; then
    notes+="**Bug Fixes**\n${bugs}\n"
  fi
  if [ -n "$improvements" ]; then
    notes+="**Improvements**\n${improvements}"
  fi

  if [ -z "$notes" ]; then
    echo "No notable changes found."
    return 1
  fi

  RELEASE_NOTES="$notes"
  return 0
}

RELEASE_NOTES=""
cd "$SCRIPT_DIR/.."
if generate_release_notes; then
  echo ""
  echo "Release notes preview:"
  echo "---"
  echo -e "$RELEASE_NOTES"
  echo "---"
  echo ""
fi

# Update appcast.xml
APPCAST_FILE="$SCRIPT_DIR/../appcast.xml"
DMG_SIZE=$(stat -f%z "$DMG_PATH")
PUB_DATE=$(date -R)
DOWNLOAD_URL="https://github.com/gustavscirulis/snapgrid/releases/download/mac-v${VERSION}/${DMG_NAME}"

# Build the new item XML
NEW_ITEM="    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <enclosure url=\"${DOWNLOAD_URL}\" length=\"${DMG_SIZE}\" type=\"application/octet-stream\" ${EDDSA_ATTRS} />
    </item>"

# Insert new item before </channel>
if [ -f "$APPCAST_FILE" ]; then
  sed -i '' "s|  </channel>|${NEW_ITEM}\n  </channel>|" "$APPCAST_FILE"
  echo "Updated appcast.xml with version ${VERSION}"
fi

if [ "$LOCAL_ONLY" = true ]; then
  echo ""
  echo "Done! SnapGrid Mac v${VERSION} build is in $BUILD_DIR"
  echo "DMG: $DMG_PATH"
  exit 0
fi

# Upload to GitHub Releases
echo "Creating GitHub release..."
TAG="mac-v${VERSION}"

if ! git tag -l "$TAG" | grep -q .; then
  git tag "$TAG"
  git push origin "$TAG"
  echo "Tagged $TAG"
fi

NOTES_ARG=""
if [ -n "$RELEASE_NOTES" ]; then
  NOTES_ARG="--notes $(echo -e "$RELEASE_NOTES")"
fi

gh release create "$TAG" \
  "$DMG_PATH" \
  --title "SnapGrid Mac v${VERSION}" \
  --draft \
  ${NOTES_ARG:+--notes "$(echo -e "$RELEASE_NOTES")"}

# Commit updated appcast
git add "$APPCAST_FILE"
git commit -m "Update appcast.xml for Mac v${VERSION}"
git push

echo ""
echo "Done! SnapGrid Mac v${VERSION} draft release is ready on GitHub."
echo "Remember to publish the draft release on GitHub when ready."
