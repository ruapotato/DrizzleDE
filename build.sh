#!/bin/bash
# DrizzleDE Build Script
# Builds the Wayland compositor GDExtension for Godot 4

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}==================================${NC}"
echo -e "${GREEN}DrizzleDE Build Script${NC}"
echo -e "${GREEN}==================================${NC}"

# Check dependencies
echo -e "\n${YELLOW}Checking dependencies...${NC}"

check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}Error: $1 is not installed${NC}"
        echo "Please install it and try again"
        exit 1
    fi
}

check_pkg_config() {
    if ! pkg-config --exists $1; then
        echo -e "${RED}Error: $1 development package not found${NC}"
        echo "Install with: sudo dnf install $2"
        exit 1
    fi
}

# Check build tools
check_command scons
check_command g++
check_command pkg-config

# Check libraries
check_pkg_config wlroots "wlroots-devel"
check_pkg_config wayland-server "wayland-devel"
check_pkg_config pixman-1 "pixman-devel"

echo -e "${GREEN}✓ All dependencies found${NC}"

# Print versions
echo -e "\n${YELLOW}Dependency versions:${NC}"
echo "  wlroots: $(pkg-config --modversion wlroots)"
echo "  wayland-server: $(pkg-config --modversion wayland-server)"
echo "  pixman: $(pkg-config --modversion pixman-1)"

# Check if godot-cpp is initialized
if [ ! -d "godot-cpp/gdextension" ]; then
    echo -e "\n${RED}Error: godot-cpp submodule not initialized${NC}"
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

echo -e "${GREEN}✓ godot-cpp submodule initialized${NC}"

# Determine build target
TARGET=${1:-template_debug}
JOBS=${2:-$(nproc)}

echo -e "\n${YELLOW}Building with:${NC}"
echo "  Target: $TARGET"
echo "  Jobs: $JOBS"

# Build
echo -e "\n${YELLOW}Starting build...${NC}"
scons platform=linux target=$TARGET -j$JOBS

# Check if build succeeded
if [ -f "addons/wayland_compositor/bin/libwayland_compositor.linux.$TARGET.x86_64.so" ]; then
    echo -e "\n${GREEN}==================================${NC}"
    echo -e "${GREEN}Build successful!${NC}"
    echo -e "${GREEN}==================================${NC}"
    echo -e "\nLibrary built: ${GREEN}addons/wayland_compositor/bin/libwayland_compositor.linux.$TARGET.x86_64.so${NC}"
    echo -e "\nYou can now run the project with Godot 4"
else
    echo -e "\n${RED}Build failed - library not found${NC}"
    exit 1
fi
