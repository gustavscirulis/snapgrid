#!/bin/bash
set -e

# SnapGrid Release Script
# Builds, signs, notarizes, and publishes a draft GitHub release.
#
# Required .env variables:
#   APPLE_ID                      - Apple ID email for notarization
#   APPLE_APP_SPECIFIC_PASSWORD   - App-specific password
#   APPLE_TEAM_ID                 - Apple Developer Team ID
#   GH_TOKEN                      - GitHub personal access token (repo scope)

# Load .env
if [ -f .env ]; then
  echo "Loading credentials from .env..."
  export $(grep -v '^#' .env | xargs)
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
[ -z "$GH_TOKEN" ] && missing+=("GH_TOKEN")

if [ ${#missing[@]} -gt 0 ]; then
  echo "Error: Missing required environment variables:"
  for var in "${missing[@]}"; do
    echo "  - $var"
  done
  exit 1
fi

# Show version and confirm
VERSION=$(node -p "require('./package.json').version")
echo ""
echo "Publishing SnapGrid v${VERSION} as a draft release..."
echo ""

# Build, sign, notarize, and publish
npm run electron:release
