#!/bin/bash
# Generate Wayland protocol headers needed by wlroots

set -e

PROTOCOLS_DIR="protocols"
mkdir -p "$PROTOCOLS_DIR"

echo "Generating Wayland protocol headers..."

# Find wayland-scanner
SCANNER=$(which wayland-scanner)
if [ -z "$SCANNER" ]; then
    echo "Error: wayland-scanner not found"
    echo "Install with: sudo apt install libwayland-dev"
    exit 1
fi

# XDG Shell protocol
XDG_SHELL_XML="/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml"

if [ ! -f "$XDG_SHELL_XML" ]; then
    echo "Error: xdg-shell.xml not found"
    echo "Install with: sudo apt install wayland-protocols"
    exit 1
fi

echo "Generating xdg-shell protocol headers..."
$SCANNER server-header "$XDG_SHELL_XML" "$PROTOCOLS_DIR/xdg-shell-protocol.h"
$SCANNER private-code "$XDG_SHELL_XML" "$PROTOCOLS_DIR/xdg-shell-protocol.c"

echo "✓ Protocol headers generated in $PROTOCOLS_DIR/"
echo ""
echo "Generated files:"
ls -lh "$PROTOCOLS_DIR/"
