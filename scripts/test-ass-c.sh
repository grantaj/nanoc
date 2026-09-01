#!/bin/sh
set -eu

CC=${CC:-cc}
BUILD_DIR=${BUILD_DIR:-build}

mkdir -p "$BUILD_DIR"

"$CC" \
    -std=c89 \
    -pedantic \
    -Wall \
    -Wextra \
    -Werror \
    -Wno-char-subscripts \
    -funsigned-char \
    bootstrap/ass_host.c \
    -o "$BUILD_DIR/ass-c"

"$BUILD_DIR/ass-c" \
    ass/ass_4000.asm \
    "$BUILD_DIR/ass-c.prg" \
    ass/

cmp "$BUILD_DIR/ass.prg" "$BUILD_DIR/ass-c.prg"

echo "candidate Phase 1 ass.c reproduces build/ass.prg"
