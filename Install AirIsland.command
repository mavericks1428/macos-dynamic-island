#!/bin/bash
set -euo pipefail

# AirIsland — macOS Application Installer
# First run: macOS Gatekeeper blocks unsigned download scripts. See FIRST RUN below,
# or use "Fix Gatekeeper.command" which clears the quarantine flag for you.

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

# Clear the download quarantine flag on this folder's scripts so future double-clicks
# are not blocked again (harmless if they are already clean).
xattr -dr com.apple.quarantine "$DIR" 2>/dev/null || true

clear
echo "========================================="
echo "  AirIsland — macOS Application Installer"
echo "========================================="
echo ""
echo "If macOS ever says \"unidentified developer\":"
echo "  right-click this file -> Open -> Open,"
echo "  or run: xattr -dr com.apple.quarantine \"$DIR\""
echo "  (or use the included \"Fix Gatekeeper.command\")"
echo ""

if ! command -v swiftc >/dev/null 2>&1 || [[ -z "$(xcrun --show-sdk-path 2>/dev/null || true)" ]]; then
  echo "Apple Command Line Tools are required to compile AirIsland.app."
  echo "Launching the Apple installer popup now..."
  xcode-select --install 2>/dev/null || true
  echo ""
  echo "Once Apple Command Line Tools finish installing, double-click this file again!"
  read -r -p "Press Return to close..." || true
  exit 1
fi

chmod +x build.sh
./build.sh app

SIGNING_FLAGS=(--force --deep --sign -)
if codesign --force --deep --sign - AirIsland.app >/dev/null 2>&1; then
  echo "Ad-hoc signed AirIsland.app"
fi

echo ""
echo "Installing /Applications/AirIsland.app..."
pkill -x AirIsland 2>/dev/null || true
sleep 0.3
rm -rf /Applications/AirIsland.app
cp -R AirIsland.app /Applications/AirIsland.app

# Strip quarantine + re-sign in place so Launch Services trusts the installed copy
xattr -cr /Applications/AirIsland.app 2>/dev/null || true
codesign --force --deep --sign - /Applications/AirIsland.app >/dev/null 2>&1 || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f /Applications/AirIsland.app >/dev/null 2>&1 || true

echo "Launching AirIsland.app..."
open /Applications/AirIsland.app

echo ""
echo "Done! AirIsland.app is installed in /Applications and running."
echo ""
echo "Look at the top-center of your screen (or the right side of the Menu Bar)."
read -r -t 6 -p "Closing automatically..." || true
echo ""
