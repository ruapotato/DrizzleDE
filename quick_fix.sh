#!/bin/bash
# Quick fix: Patch wlroots headers to remove C99 VLA syntax
# This allows immediate testing without massive refactoring

set -e

echo "DrizzleDE Quick Fix - Patching wlroots headers"
echo "================================================"
echo ""
echo "This script removes C99 VLA syntax [static N] from wlroots headers"
echo "allowing C++ compilation without errors."
echo ""
echo "WARNING: This modifies system headers. You may need to reinstall"
echo "wlroots-devel to restore them."
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

HEADER="/usr/include/wlr/render/wlr_renderer.h"

if [ ! -f "$HEADER" ]; then
    echo "Error: $HEADER not found"
    exit 1
fi

echo "Backing up original header..."
sudo cp "$HEADER" "$HEADER.backup"

echo "Patching header..."
sudo sed -i 's/\[static \([0-9]*\)\]/[\1]/g' "$HEADER"

echo ""
echo "Done! Header patched successfully."
echo "Backup saved to: $HEADER.backup"
echo ""
echo "To restore: sudo mv $HEADER.backup $HEADER"
echo ""
echo "Now run: ./build.sh"
