#!/bin/sh
set -eu

CC=${CC:-cc}
BUILD_DIR=${BUILD_DIR:-build}
DIAG_DIR="$BUILD_DIR/ass-c-diagnostic"

mkdir -p "$DIAG_DIR"
cp bootstrap/ass_host.c "$DIAG_DIR/ass_host.c"

# Temporarily relax only the candidate's artificial split limits so the real
# source closure can tell us its final symbol/name/fixup counts.  The committed
# ass.c remains the language-design source; this diagnostic copy is not a target
# memory model.
sed \
    -e 's/\[512\]/[1024]/g' \
    -e 's/\[8192\]/[16384]/g' \
    -e 's/>= 512/>= 1024/g' \
    -e 's/> 8192/> 16384/g' \
    bootstrap/ass.c > "$DIAG_DIR/ass.c"

"$CC" \
    -std=c89 \
    -pedantic \
    -Wall \
    -Wextra \
    -Werror \
    -funsigned-char \
    "$DIAG_DIR/ass_host.c" \
    -o "$BUILD_DIR/ass-c"

"$BUILD_DIR/ass-c" \
    ass/ass_4000.asm \
    "$BUILD_DIR/ass-c.prg" \
    ass/

cmp "$BUILD_DIR/ass.prg" "$BUILD_DIR/ass-c.prg"

echo "candidate Phase 1 ass.c reproduces build/ass.prg"
