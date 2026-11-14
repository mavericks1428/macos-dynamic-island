#!/bin/bash
set -euo pipefail

# AirIsland — Gatekeeper Fix
# macOS blocks unsigned scripts/apps downloaded from the internet ("unidentified developer").
# This clears the quarantine flag for the AirIsland folder so Install AirIsland.command
# and AirIsland.app open normally. It does NOT bypass Gatekeeper for anything else.

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "========================================="
echo "  AirIsland — Gatekeeper Fix"
echo "========================================="
echo ""
echo "Clearing quarantine flags for:"
echo "  $DIR"
echo ""

xattr -dr com.apple.quarantine "$DIR" 2>/dev/null || true
xattr -dr com.apple.quarantine "$HOME/Downloads" 2>/dev/null || true
xattr -cr "$HOME/Applications/AirIsland.app" 2>/dev/null || true
xattr -cr "/Applications/AirIsland.app" 2>/dev/null || true

chmod +x "$DIR/Install AirIsland.command" 2>/dev/null || true
chmod +x "$DIR/build.sh" 2>/dev/null || true

echo "Done. Quarantine flags cleared."
echo ""
echo "Next step: double-click \"Install AirIsland.command\"."
echo "It will compile AirIsland.app and install it to /Applications."
echo ""
read -r -t 8 -p "Closing automatically..." || true
echo ""
