#!/bin/bash
# Automated helper script to download, extract, and analyze package dependencies
# Usage: ./check-dependencies.sh [--auto-update]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$SCRIPT_DIR/build"
PKGBUILD_PATH="$SCRIPT_DIR/PKGBUILD"
AUTO_UPDATE=false

if [ "$1" = "--auto-update" ]; then
    AUTO_UPDATE=true
fi

# Create work directory if it doesn't exist
mkdir -p "$WORK_DIR"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Smart Dependency Checker ===${NC}"
echo -e "${BLUE}Working directory: $WORK_DIR${NC}"
echo ""

# Read PKGBUILD to extract version and source URL
if [ ! -f "$PKGBUILD_PATH" ]; then
    echo -e "${RED}Error: PKGBUILD not found${NC}"
    exit 1
fi

echo "Reading PKGBUILD..."
source "$PKGBUILD_PATH"

ARCHIVE_NAME="lzc-client-desktop_${pkgver}.tar.zst"
SOURCE_URL="${source[0]#*::}"  # Strip the filename:: prefix if present
if [ -z "$SOURCE_URL" ]; then
    SOURCE_URL="${source[0]}"
fi

APP_DIR="lzc-client-desktop"
BINARY_NAME="lzc-client-desktop"

echo -e "  Package: ${GREEN}${pkgname}${NC}"
echo -e "  Version: ${GREEN}${pkgver}${NC}"
echo -e "  Source: ${BLUE}${SOURCE_URL}${NC}"
echo ""

# Work in the build directory
cd "$WORK_DIR"

# Check if archive exists, download if not
if [ ! -f "$ARCHIVE_NAME" ]; then
    echo -e "${YELLOW}Archive not found. Downloading...${NC}"
    curl -L -o "$ARCHIVE_NAME" "$SOURCE_URL"
    echo -e "${GREEN}✓ Download complete${NC}"
    echo ""
else
    echo -e "${GREEN}✓ Archive already exists: $ARCHIVE_NAME${NC}"
    echo ""
fi

# Generate and display checksum
echo -e "${BLUE}=== Generating checksum ===${NC}"
CHECKSUM=$(sha256sum "$ARCHIVE_NAME" | awk '{print $1}')
echo -e "sha256sums=('${GREEN}${CHECKSUM}${NC}')"
echo ""

# Check if already extracted
if [ ! -d "$APP_DIR" ]; then
    echo -e "${YELLOW}Extracting archive...${NC}"
    tar --use-compress-program=unzstd -xf "$ARCHIVE_NAME"
    echo -e "${GREEN}✓ Extraction complete${NC}"
    echo ""
else
    echo -e "${GREEN}✓ Already extracted: $APP_DIR${NC}"
    echo ""
fi

if [ ! -d "$APP_DIR" ]; then
    # Maybe it extracted to current directory
    echo -e "${YELLOW}Note: Archive may have extracted to current directory${NC}"
    APP_DIR="."
fi

echo -e "${BLUE}=== Checking package structure ===${NC}"
echo ""

# Find the main binary
echo "Looking for main binary..."
BINARY_PATH=""
for path in \
    "$APP_DIR/$BINARY_NAME" \
    "$APP_DIR/bin/$BINARY_NAME" \
    "$APP_DIR/usr/bin/$BINARY_NAME" \
    "./$BINARY_NAME"
do
    if [ -f "$path" ]; then
        BINARY_PATH="$path"
        echo -e "${GREEN}✓${NC} Found binary: $path"
        break
    fi
done

if [ -z "$BINARY_PATH" ]; then
    echo -e "${RED}✗ Binary not found!${NC}"
    echo "  Please update PKGBUILD with correct binary path"
else
    # Check if binary is executable
    if [ -x "$BINARY_PATH" ]; then
        echo -e "  Binary is executable: ${GREEN}✓${NC}"
    else
        echo -e "  Binary is NOT executable: ${RED}✗${NC}"
    fi
fi

echo ""

# Find desktop file
echo "Looking for desktop file..."
DESKTOP_FILE=""
for pattern in "$APP_DIR"/*.desktop "$APP_DIR"/share/applications/*.desktop "./*.desktop"; do
    for file in $pattern; do
        if [ -f "$file" ]; then
            DESKTOP_FILE="$file"
            echo -e "${GREEN}✓${NC} Found desktop file: $file"
            echo -e "${YELLOW}--- Content:${NC}"
            cat "$file"
            echo ""
            break 2
        fi
    done
done

if [ -z "$DESKTOP_FILE" ]; then
    echo -e "${RED}✗ Desktop file not found!${NC}"
fi

echo ""

# Find icon
echo "Looking for icon..."
ICON_FILE=""
for ext in png svg; do
    for file in \
        "$APP_DIR"/*.$ext \
        "$APP_DIR"/resources/*.$ext \
        "$APP_DIR"/share/icons/*.$ext \
        "$APP_DIR"/share/pixmaps/*.$ext \
        "./"*.$ext
    do
        if [ -f "$file" ] && [[ ! "$file" =~ /\. ]]; then
            ICON_FILE="$file"
            echo -e "${GREEN}✓${NC} Found icon: $file"
            file "$file" 2>/dev/null || true
            break 2
        fi
    done
done

if [ -z "$ICON_FILE" ]; then
    echo -e "${YELLOW}✗ Icon not found (may not be needed)${NC}"
fi

echo ""

# Find polkit policy
echo "Looking for polkit policy..."
POLICY_FILE=""
for pattern in "$APP_DIR"/*.policy "$APP_DIR"/share/polkit-1/actions/*.policy "./*.policy"; do
    for file in $pattern; do
        if [ -f "$file" ]; then
            POLICY_FILE="$file"
            echo -e "${GREEN}✓${NC} Found polkit policy: $file"
            echo -e "${YELLOW}--- Content:${NC}"
            cat "$file"
            echo ""
            break 2
        fi
    done
done

if [ -z "$POLICY_FILE" ]; then
    echo -e "${YELLOW}✗ Polkit policy not found (may not be needed)${NC}"
fi

echo ""

# Find license
echo "Looking for license file..."
LICENSE_FILE=""
for file in \
    "$APP_DIR"/LICENSE \
    "$APP_DIR"/LICENSE.txt \
    "$APP_DIR"/COPYING \
    "$APP_DIR"/share/doc/*/LICENSE* \
    "./LICENSE" \
    "./LICENSE.txt"
do
    if [ -f "$file" ]; then
        LICENSE_FILE="$file"
        echo -e "${GREEN}✓${NC} Found license: $file"
        break
    fi
done

if [ -z "$LICENSE_FILE" ]; then
    echo -e "${RED}✗ License file not found!${NC}"
fi

echo ""
echo -e "${BLUE}=== Checking dependencies ===${NC}"
echo ""

if [ -n "$BINARY_PATH" ]; then
    echo "Running ldd on $BINARY_PATH..."
    echo ""

    # Run ldd and capture output
    LDD_OUTPUT=$(ldd "$BINARY_PATH" 2>&1)

    echo "$LDD_OUTPUT"
    echo ""

    # Extract library names and find packages
    echo -e "${BLUE}=== Mapping libraries to Arch packages ===${NC}"
    echo ""

    MISSING_LIBS=()
    PACKAGES=()

    while IFS= read -r line; do
        # Extract library path
        if [[ $line =~ =\>\ ([^\ ]+) ]]; then
            LIB_PATH="${BASH_REMATCH[1]}"

            # Skip if not found
            if [ "$LIB_PATH" = "not" ]; then
                LIB_NAME=$(echo "$line" | awk '{print $1}')
                MISSING_LIBS+=("$LIB_NAME")
                continue
            fi

            # Find which package provides this library
            if [ -f "$LIB_PATH" ]; then
                PKG=$(pacman -Qo "$LIB_PATH" 2>/dev/null | awk '{print $5}' || echo "unknown")
                if [ "$PKG" != "unknown" ] && [[ ! " ${PACKAGES[@]} " =~ " ${PKG} " ]]; then
                    PACKAGES+=("$PKG")
                    echo "  $LIB_PATH -> ${GREEN}$PKG${NC}"
                fi
            fi
        fi
    done <<< "$LDD_OUTPUT"

    echo ""

    if [ ${#MISSING_LIBS[@]} -gt 0 ]; then
        echo -e "${RED}⚠ Missing libraries:${NC}"
        for lib in "${MISSING_LIBS[@]}"; do
            echo "  - $lib"
        done
        echo ""
    fi

    echo -e "${BLUE}=== Suggested depends array for PKGBUILD ===${NC}"
    echo ""
    echo "depends=("

    # Core dependencies from original script
    echo "  'zenity'"
    echo "  'libcap'"

    # Add found packages
    for pkg in "${PACKAGES[@]}"; do
        # Skip some obvious base packages
        case "$pkg" in
            glibc|gcc-libs|filesystem|linux-api-headers)
                # Skip base system packages
                ;;
            *)
                echo "  '$pkg'"
                ;;
        esac
    done

    echo ")"
    echo ""

    # Check for common GUI frameworks
    if echo "$LDD_OUTPUT" | grep -q "libgtk-3"; then
        echo -e "${BLUE}Note: GTK3 application detected${NC}"
    fi
    if echo "$LDD_OUTPUT" | grep -q "libQt"; then
        echo -e "${BLUE}Note: Qt application detected${NC}"
    fi
    if echo "$LDD_OUTPUT" | grep -q "libelectron"; then
        echo -e "${BLUE}Note: Electron application detected${NC}"
    fi

else
    echo -e "${RED}Cannot check dependencies: binary not found${NC}"
fi

echo ""
echo -e "${BLUE}=== Complete file listing ===${NC}"
echo ""
if [ "$APP_DIR" = "." ]; then
    find . -maxdepth 2 -type f -o -type l | grep -v "^./.git" | head -50
else
    find "$APP_DIR" -type f -o -type l | head -50
fi

echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo ""
echo "✓ Checksum generated (copy to PKGBUILD):"
echo -e "  ${GREEN}sha256sums=('${CHECKSUM}')${NC}"
echo ""
echo "Next steps:"
echo "1. Copy the checksum above to PKGBUILD"
echo "2. Update depends=() array with suggested packages above"
echo "3. Verify file paths match PKGBUILD expectations"
echo "4. Test build with: ${GREEN}makepkg -si${NC}"
echo ""

# Offer to create a summary file
SUMMARY_FILE="$WORK_DIR/package-analysis.txt"
cat > "$SUMMARY_FILE" <<EOF
Package Analysis for ${pkgname} v${pkgver}
Generated: $(date)

=== CHECKSUM ===
sha256sums=('${CHECKSUM}')

=== FILES FOUND ===
Binary: ${BINARY_PATH:-NOT FOUND}
Desktop: ${DESKTOP_FILE:-NOT FOUND}
Icon: ${ICON_FILE:-NOT FOUND}
Policy: ${POLICY_FILE:-NOT FOUND}
License: ${LICENSE_FILE:-NOT FOUND}

=== DEPENDENCIES ===
$(if [ -n "$BINARY_PATH" ]; then
    echo "depends=("
    echo "  'zenity'"
    echo "  'libcap'"
    for pkg in "${PACKAGES[@]}"; do
        case "$pkg" in
            glibc|gcc-libs|filesystem|linux-api-headers) ;;
            *) echo "  '$pkg'" ;;
        esac
    done
    echo ")"
fi)

=== MISSING LIBRARIES ===
$(for lib in "${MISSING_LIBS[@]}"; do echo "$lib"; done)
EOF

echo -e "${GREEN}✓ Analysis saved to: $SUMMARY_FILE${NC}"
