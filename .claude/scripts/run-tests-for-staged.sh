#!/bin/bash
# Run tests for staged files before committing.
# Called by Claude Code PreToolUse hook on Bash commands containing "git commit".
# Exits non-zero if tests fail, which blocks the commit.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Check which directories have staged changes
STAGED=$(git diff --cached --name-only 2>/dev/null || true)

if [ -z "$STAGED" ]; then
  exit 0
fi

MAC_CHANGED=$(echo "$STAGED" | grep -c '^SnapGrid/' || true)
IOS_CHANGED=$(echo "$STAGED" | grep -c '^ios/' || true)

FAILED=0

if [ "$MAC_CHANGED" -gt 0 ]; then
  echo "Running Mac app tests..."
  (cd SnapGrid && xcodegen generate -q 2>/dev/null && \
    xcodebuild test -project SnapGrid.xcodeproj -scheme SnapGrid \
      -destination 'platform=macOS' -quiet 2>&1) || FAILED=1

  if [ "$FAILED" -eq 1 ]; then
    echo "Mac app tests FAILED"
    exit 1
  fi
  echo "Mac app tests passed"
fi

if [ "$IOS_CHANGED" -gt 0 ]; then
  echo "Running iOS app tests..."
  xcodebuild test -project ios/SnapGrid/SnapGrid.xcodeproj -scheme SnapGrid \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    -quiet 2>&1 || FAILED=1

  if [ "$FAILED" -eq 1 ]; then
    echo "iOS app tests FAILED"
    exit 1
  fi
  echo "iOS app tests passed"
fi
