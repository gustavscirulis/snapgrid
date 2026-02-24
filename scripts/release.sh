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

# Generate release notes from git log
generate_release_notes() {
  local prev_tag
  prev_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

  if [ -z "$prev_tag" ]; then
    echo "No previous tag found, skipping release notes."
    return 1
  fi

  echo "Generating release notes from ${prev_tag} to HEAD..."

  local bugs=""
  local improvements=""

  while IFS= read -r msg; do
    # Skip version bump commits
    if echo "$msg" | grep -qiE '^bump version'; then
      continue
    fi

    # Strip PR reference suffix like " (#31)"
    clean=$(echo "$msg" | sed 's/ (#[0-9]*)$//')

    # Categorize by prefix and strip it
    if echo "$clean" | grep -qiE '^(fix|disable)'; then
      entry=$(echo "$clean" | sed -E 's/^[Ff]ix(ed|es)?:?[[:space:]]*//' | sed -E 's/^[Dd]isable[ds]?:?[[:space:]]*//')
      entry="$(echo "${entry:0:1}" | tr '[:lower:]' '[:upper:]')${entry:1}"
      bugs="${bugs}- ${entry}\n"
    else
      entry=$(echo "$clean" | sed -E 's/^[Ff]eature:?[[:space:]]*//' \
        | sed -E 's/^[Ii]mprove[ds]?:?[[:space:]]*//' \
        | sed -E 's/^[Rr]eplace[ds]?:?[[:space:]]*//' \
        | sed -E 's/^[Rr]emove[ds]?:?[[:space:]]*//' \
        | sed -E 's/^[Aa]dd(ed|s)?:?[[:space:]]*//' \
        | sed -E 's/^[Uu]pdate[ds]?:?[[:space:]]*//' \
        | sed -E 's/^[Ee]nable[ds]?:?[[:space:]]*//' \
        | sed -E 's/^[Oo]ptimize[ds]?:?[[:space:]]*//')
      entry="$(echo "${entry:0:1}" | tr '[:lower:]' '[:upper:]')${entry:1}"
      improvements="${improvements}- ${entry}\n"
    fi
  done < <(git log "${prev_tag}..HEAD" --first-parent --format="%s")

  # Build the notes
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
if generate_release_notes; then
  echo ""
  echo "Release notes preview:"
  echo "─────────────────────────"
  echo -e "$RELEASE_NOTES"
  echo "─────────────────────────"
  echo ""
fi

# Build, sign, notarize, and publish
npm run electron:release

# Tag the release
if ! git tag -l "v${VERSION}" | grep -q .; then
  git tag "v${VERSION}"
  git push origin "v${VERSION}"
  echo "Tagged v${VERSION}"
fi

# Update the GitHub release with generated notes
if [ -n "$RELEASE_NOTES" ]; then
  echo "Updating release notes on GitHub..."
  gh release edit "v${VERSION}" --notes "$(echo -e "$RELEASE_NOTES")" 2>/dev/null || \
    echo "Note: Could not update release notes (release may not exist yet). You can manually set them on GitHub."
fi

echo ""
echo "Done! SnapGrid v${VERSION} draft release is ready on GitHub."
