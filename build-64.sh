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

# --- Output Preparation ---
echo ">>> Preparing Output: Emu/ARCADE/"
mkdir -p "$OUT_DIR"

# 1. advmame: Copy, Strip, and Compress into advmame.7z
if [ -f obj/mame/linux/blend/advmame ]; then
    cp obj/mame/linux/blend/advmame "$OUT_DIR/advmame"
    $STRIP "$OUT_DIR/advmame"
    cd "$OUT_DIR"
    # Create internal zip/7z with original name
    7z a -t7z -m0=lzma2 -mx=9 advmame.7z advmame
    rm advmame
    cd -
fi

# 2. advj: Copy and Strip to ARCADE (Original Name)
if [ -f obj/j/linux/blend/advj ]; then
    cp obj/j/linux/blend/advj "$OUT_DIR/advj"
    $STRIP "$OUT_DIR/advj"
fi

# 3. DAT files: Copy to ARCADE
for dat_file in event.dat hiscore.dat history.dat cheat.dat; do
    [ -f "support/$dat_file" ] && cp "support/$dat_file" "$OUT_DIR/"
done

# 4. Final Packaging
cd "$OUTPUT_DIR"
echo ">>> Packaging everything into advmame.64.7z..."
rm -f advmame.64.7z
7z a -t7z -m0=lzma2 -mx=9 advmame.64.7z Emu/

echo "=== Build complete: ${OUTPUT_DIR}/advmame.64.7z ==="
