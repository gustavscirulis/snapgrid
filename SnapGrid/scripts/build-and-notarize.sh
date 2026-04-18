#!/bin/bash
set -euo pipefail

# SnapGrid Mac App — Build, Sign, Notarize, and Package
#
# Prerequisites:
#   1. "Developer ID Application" certificate in Keychain
#   2. Store notarization credentials once:
#      xcrun notarytool store-credentials "SnapGrid" \
#        --apple-id "your@email.com" \
#        --team-id "HJ4HYUU2Y6" \
#        --password "app-specific-password"
#   3. Xcode command line tools selected:
#      sudo xcode-select -s /Applications/Xcode.app
#
# Usage:
#   ./scripts/build-and-notarize.sh                    # full build + notarize
#   ./scripts/build-and-notarize.sh --skip-notarize    # build + sign only (no notarization)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/SnapGrid.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_DIR="$BUILD_DIR/dmg"
KEYCHAIN_PROFILE="SnapGrid"
SKIP_NOTARIZE=false

for arg in "$@"; do
  case $arg in
    --skip-notarize) SKIP_NOTARIZE=true ;;
  esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

step() { echo -e "\n${BLUE}▸ $1${NC}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }

# ---------------------------------------------------------------------------
# 1. Preflight checks
# ---------------------------------------------------------------------------
step "Preflight checks"

if ! command -v xcodegen &>/dev/null; then
  fail "XcodeGen not found. Install with: brew install xcodegen"
fi

if ! command -v xcbeautify &>/dev/null; then
  warn "xcbeautify not found — raw xcodebuild output will be shown"
  BEAUTIFY=false
else
  BEAUTIFY=true
fi

# Verify Developer ID certificate exists
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  fail "No 'Developer ID Application' certificate found in Keychain"
fi
success "Developer ID Application certificate found"

# Verify notarytool credentials (unless skipping)
if [ "$SKIP_NOTARIZE" = false ]; then
  if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" &>/dev/null 2>&1; then
    echo ""
    warn "Keychain profile '$KEYCHAIN_PROFILE' not found."
    echo "  Store credentials first with:"
    echo "    xcrun notarytool store-credentials \"$KEYCHAIN_PROFILE\" \\"
    echo "      --apple-id \"your@email.com\" \\"
    echo "      --team-id \"HJ4HYUU2Y6\" \\"
    echo "      --password \"app-specific-password\""
    echo ""
    fail "Notarization credentials not configured"
  fi
  success "Notarization credentials verified"
fi

# ---------------------------------------------------------------------------
# 2. Generate Xcode project
# ---------------------------------------------------------------------------
step "Generating Xcode project with XcodeGen"
cd "$PROJECT_DIR"
xcodegen generate
success "Project generated"

# ---------------------------------------------------------------------------
# 3. Clean previous build artifacts
# ---------------------------------------------------------------------------
step "Cleaning previous build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ---------------------------------------------------------------------------
# 4. Archive
# ---------------------------------------------------------------------------
step "Building archive (Release)"

ARCHIVE_CMD=(
  xcodebuild archive
  -project SnapGrid.xcodeproj
  -scheme SnapGrid
  -configuration Release
  -archivePath "$ARCHIVE_PATH"
  -allowProvisioningUpdates
)

if [ "$BEAUTIFY" = true ]; then
  "${ARCHIVE_CMD[@]}" 2>&1 | xcbeautify --quiet
else
  "${ARCHIVE_CMD[@]}"
fi
success "Archive created at $ARCHIVE_PATH"

# ---------------------------------------------------------------------------
# 5. Export archive
# ---------------------------------------------------------------------------
step "Exporting archive"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$PROJECT_DIR/ExportOptions.plist" \
  -allowProvisioningUpdates \
  2>&1 | if [ "$BEAUTIFY" = true ]; then xcbeautify --quiet; else cat; fi

APP_PATH="$EXPORT_DIR/SnapGrid.app"
if [ ! -d "$APP_PATH" ]; then
  fail "Export failed — SnapGrid.app not found in $EXPORT_DIR"
fi
success "Exported SnapGrid.app"

# Extract version for DMG naming
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist")
success "Version: $VERSION (build $BUILD)"

# ---------------------------------------------------------------------------
# 6. Verify code signing
# ---------------------------------------------------------------------------
step "Verifying code signature"
codesign --verify --deep --strict "$APP_PATH" 2>&1
codesign -dv --verbose=2 "$APP_PATH" 2>&1 | grep -E "Authority|TeamIdentifier|Signature"
success "Code signature valid"

# ---------------------------------------------------------------------------
# 7. Create DMG
# ---------------------------------------------------------------------------
step "Creating DMG"

DMG_NAME="SnapGrid-${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
mkdir -p "$DMG_DIR"
cp -R "$APP_PATH" "$DMG_DIR/"

# Create a symlink to /Applications for drag-install
ln -s /Applications "$DMG_DIR/Applications"

hdiutil create \
  -volname "SnapGrid" \
  -srcfolder "$DMG_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

# Sign the DMG itself
codesign --force --sign "Developer ID Application" "$DMG_PATH"
success "DMG created: $DMG_PATH"

# ---------------------------------------------------------------------------
# 8. Notarize
# ---------------------------------------------------------------------------
if [ "$SKIP_NOTARIZE" = true ]; then
  warn "Skipping notarization (--skip-notarize)"
else
  step "Submitting to Apple notary service"
  echo "  This may take a few minutes..."

  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

  step "Stapling notarization ticket"
  xcrun stapler staple "$DMG_PATH"
  success "Notarization complete and stapled"

  step "Verifying notarization"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH" 2>&1
  success "DMG passes Gatekeeper"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Build complete!${NC}"
echo -e "${GREEN}  App:     $APP_PATH${NC}"
echo -e "${GREEN}  DMG:     $DMG_PATH${NC}"
echo -e "${GREEN}  Version: $VERSION (build $BUILD)${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
