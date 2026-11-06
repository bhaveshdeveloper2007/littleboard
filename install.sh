#!/bin/sh
# One-command install for Littleboard.
#   curl -fsSL https://raw.githubusercontent.com/bhaveshdeveloper2007/littleboard/main/install.sh | sh
# Re-running the same command updates an existing install. The source is kept
# at ~/Littleboard (override with LITTLEBOARD_DIR=/some/path).
set -eu

DEST="${LITTLEBOARD_DIR:-$HOME/Littleboard}"
REPO="https://github.com/bhaveshdeveloper2007/littleboard.git"

echo "==> Littleboard installer"

if ! command -v git >/dev/null 2>&1; then
  echo "error: git not found. Install the Xcode Command Line Tools first:" >&2
  echo "       xcode-select --install" >&2
  exit 1
fi
if ! command -v swift >/dev/null 2>&1; then
  echo "error: Swift not found. Install Xcode from the App Store (free), then run:" >&2
  echo "       xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
  DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  export DEVELOPER_DIR
fi

if [ -d "$DEST/.git" ]; then
  echo "==> Updating existing install at $DEST"
  git -C "$DEST" pull --ff-only
else
  echo "==> Cloning Littleboard into $DEST"
  rm -rf "$DEST"
  git clone --depth 1 "$REPO" "$DEST"
fi

cd "$DEST"
echo "==> Building (release) — the first build takes a few minutes"
swift build -c release

EXECUTABLE="$DEST/.build/out/Products/Release/Littleboard"
if [ ! -x "$EXECUTABLE" ]; then
  EXECUTABLE="$DEST/.build/arm64-apple-macosx/release/Littleboard"
fi
if [ ! -x "$EXECUTABLE" ]; then
  echo "error: release binary not found after build" >&2
  exit 1
fi

echo "==> Packaging build/Littleboard.app"
"$DEST/scripts/package-app.sh"

echo "==> Opening Littleboard"
open "$DEST/build/Littleboard.app"

echo "==> Installed. Source lives in $DEST — run this command again to update."
