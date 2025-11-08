#!/bin/bash
# Helper script to launch Wayland clients connected to DrizzleDE compositor
#
# Usage: ./launch_client.sh <socket_name> <command>
# Example: ./launch_client.sh wayland-1 foot

if [ $# -lt 2 ]; then
    echo "Usage: $0 <wayland_socket> <command> [args...]"
    echo "Example: $0 wayland-1 foot"
    echo ""
    echo "Common Wayland terminals:"
    echo "  - foot"
    echo "  - alacritty"
    echo "  - kitty"
    echo "  - weston-terminal"
    exit 1
fi

SOCKET_NAME=$1
shift

# Check if socket exists
if [ ! -S "/run/user/$(id -u)/$SOCKET_NAME" ]; then
    echo "Error: Wayland socket not found: /run/user/$(id -u)/$SOCKET_NAME"
    echo "Make sure the DrizzleDE compositor is running first!"
    exit 1
fi

echo "Launching $@ with WAYLAND_DISPLAY=$SOCKET_NAME"
WAYLAND_DISPLAY=$SOCKET_NAME "$@"
