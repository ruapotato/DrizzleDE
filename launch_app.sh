#!/bin/bash
# Helper script to launch X11 applications in the DrizzleDE nested X server

if [ -z "$1" ]; then
    echo "Usage: $0 <display_number> <command> [args...]"
    echo ""
    echo "Example:"
    echo "  $0 :1 xterm"
    echo "  $0 :1 firefox"
    echo ""
    echo "The compositor will print the display number when it starts."
    echo "Look for: 'Using display number: X'"
    exit 1
fi

DISPLAY_NUM=$1
shift

# Set the DISPLAY environment variable and launch the app
DISPLAY=$DISPLAY_NUM "$@" &

echo "Launched '$*' on display $DISPLAY_NUM (PID: $!)"
