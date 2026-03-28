#!/bin/bash
set -e

TARGET_REF="${COMMIT_HASH:-master}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
OUT_DIR="$OUTPUT_DIR/Emu/ARCADE"

echo "=== Building AdvanceMAME ${TARGET_REF} for aarch64 ==="

if [ ! -d "advancemame" ]; then
    git clone https://github.com/amadvance/advancemame.git advancemame
fi

cd advancemame
echo ">>> Checking out to: $TARGET_REF"
git checkout "$TARGET_REF"

# Apply patch
for dir in /patches/common /patches/; do
    if [ -d "$dir" ] && ls "$dir"/*.patch 1>/dev/null 2>&1; then
        for patch in "$dir"/*.patch; do
            echo "Applying: $(basename "$patch")"
            patch -p1 < "$patch"
        done
    fi
done

# --- Cross Compile & ccache Setup ---
export CCACHE_DIR="${CCACHE_DIR:-/ccache}"
export CC="ccache aarch64-linux-gnu-gcc"
export CXX="ccache aarch64-linux-gnu-g++"
export AR="aarch64-linux-gnu-ar"
export STRIP="aarch64-linux-gnu-strip"
export PKG_CONFIG_PATH="/usr/lib/aarch64-linux-gnu/pkgconfig"
export PKG_CONFIG_LIBDIR="/usr/lib/aarch64-linux-gnu/pkgconfig"

# Initialize ccache stats
ccache -M 5G
ccache -z

# --- Configure ---
aclocal && automake --add-missing --copy --foreign || true
autoheader && autoconf
./configure --host=aarch64-linux-gnu

# --- Build ---
echo ">>> Starting Build with $(nproc) cores using ccache..."
# Pass CC/CXX to make to ensure ccache is used
make -j$(nproc) CC="$CC" CXX="$CXX"

# Show ccache stats
echo ">>> ccache stats:"
ccache -s

# --- Output ---
echo ">>> Preparing Output..."
mkdir -p "$OUT_DIR/bin" "$OUT_DIR/doc" "$OUT_DIR/lib" "$OUT_DIR/share"

# Check common binary locations
if [ -f "advmame" ]; then
    cp advmame "$OUT_DIR/bin/advmame.64"
    $STRIP "$OUT_DIR/bin/advmame.64"
elif [ -f "obj/mame/linux/blend/advmame" ]; then
    cp obj/mame/linux/blend/advmame "$OUT_DIR/bin/advmame.64"
    $STRIP "$OUT_DIR/bin/advmame.64"
else
    echo "Error: advmame binary not found!"
    exit 1
fi

cd "$OUTPUT_DIR"
echo ">>> Packaging..."
rm -f advmame.64.7z
7z a -t7z -m0=lzma2 -mx=9 advmame.64.7z Emu/

echo "=== Build complete: ${OUTPUT_DIR}/advmame.64.7z ==="