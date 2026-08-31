#!/bin/sh
set -eu

VASM=${VASM:-vasm6502_oldstyle}
VICE=${VICE:-x64sc}
BUILD_DIR=${BUILD_DIR:-build}
ROOT=$(pwd)
OUT_DIR="$ROOT/$BUILD_DIR/nanoc0-integration"

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR/NCOUT.ASM" "$OUT_DIR/ncout.asm" "$OUT_DIR/ncout.prg"

# Host vasm is only a fast syntax/size probe here. The first native test below
# independently assembles this exact production source with the project ass.
(
    cd nanoc0
    "$VASM" -Fbin -cbm-prg -o "../$BUILD_DIR/nanoc0.prg" nanoc0.asm
)
bytes=$(wc -c < "$BUILD_DIR/nanoc0.prg")
echo "production nanoc0 loaded image: $((bytes - 2)) bytes"

(
    cd ass
    "$VASM" -Fbin -cbm-prg -o "../$BUILD_DIR/test_nanoc0_driver.prg" test_nanoc0_driver.asm
    "$VASM" -Fbin -cbm-prg -o "../$BUILD_DIR/test_nanoc0_generated.prg" test_nanoc0_generated.asm
)

# current ass -> production nanoc0 -> one real Phase 1 C file -> generated ass
VICE_TIMEOUT=60 VICE_FS_DIR="$ROOT" VICE_FS_DIR_9="$OUT_DIR" \
    VICE="$VICE" BUILD_DIR="$BUILD_DIR" \
    sh tests/run-test.sh "$BUILD_DIR/test_nanoc0_driver.prg" nanoc0-driver

if [ -f "$OUT_DIR/NCOUT.ASM" ]; then
    GENERATED="$OUT_DIR/NCOUT.ASM"
elif [ -f "$OUT_DIR/ncout.asm" ]; then
    GENERATED="$OUT_DIR/ncout.asm"
else
    echo "FAIL nanoc0-driver: generated NCOUT.ASM is missing" >&2
    exit 1
fi

# current ass -> generated ass -> executable 6502 -> zero-argument main result
VICE_TIMEOUT=60 VICE_FS_DIR="$OUT_DIR" VICE="$VICE" BUILD_DIR="$BUILD_DIR" \
    sh tests/run-test.sh "$BUILD_DIR/test_nanoc0_generated.prg" nanoc0-generated

# Size is reported with vasm only as a measurement convenience. The native test
# above is the semantic/assembler authority.
"$VASM" -Fbin -cbm-prg -o "$OUT_DIR/ncout.prg" "$GENERATED"
bytes=$(wc -c < "$OUT_DIR/ncout.prg")
echo "small generated loaded image: $((bytes - 2)) bytes"
