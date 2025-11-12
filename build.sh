#!/bin/bash
# DrizzleDE Build Script
# Builds the X11 compositor GDExtension for Godot 4

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
        echo "Install with: $2"
        exit 1
    fi
}

# Check build tools
check_command scons
check_command g++
check_command pkg-config

# Check X11 libraries
check_pkg_config x11 "sudo dnf install libX11-devel (Fedora) or sudo apt install libx11-dev (Ubuntu)"
check_pkg_config xcomposite "sudo dnf install libXcomposite-devel (Fedora) or sudo apt install libxcomposite-dev (Ubuntu)"
check_pkg_config xdamage "sudo dnf install libXdamage-devel (Fedora) or sudo apt install libxdamage-dev (Ubuntu)"
check_pkg_config xfixes "sudo dnf install libXfixes-devel (Fedora) or sudo apt install libxfixes-dev (Ubuntu)"
check_pkg_config xrender "sudo dnf install libXrender-devel (Fedora) or sudo apt install libxrender-dev (Ubuntu)"
check_pkg_config xtst "sudo dnf install libXtst-devel (Fedora) or sudo apt install libxtst-dev (Ubuntu)"

# Check for Xvfb
check_command Xvfb

echo -e "${GREEN}✓ All dependencies found${NC}"

# Print versions
echo -e "\n${YELLOW}Dependency versions:${NC}"
echo "  X11: $(pkg-config --modversion x11)"
echo "  Xcomposite: $(pkg-config --modversion xcomposite)"
echo "  Xdamage: $(pkg-config --modversion xdamage)"

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
if [ -f "addons/x11_compositor/bin/libx11_compositor.linux.$TARGET.x86_64.so" ]; then
    echo -e "\n${GREEN}==================================${NC}"
    echo -e "${GREEN}Build successful!${NC}"
    echo -e "${GREEN}==================================${NC}"
    echo -e "\nLibrary built: ${GREEN}addons/x11_compositor/bin/libx11_compositor.linux.$TARGET.x86_64.so${NC}"
    echo -e "\nYou can now run the project with Godot 4"
else
    echo -e "\n${RED}Build failed - library not found${NC}"
    exit 1
fi
