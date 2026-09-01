#!/bin/sh
set -eu

VASM=${VASM:-vasm6502_oldstyle}
VICE=${VICE:-x64sc}
BUILD_DIR=${BUILD_DIR:-build}
ROOT=$(pwd)
OUT_DIR="$ROOT/$BUILD_DIR/nanoc0-integration"
DRIVER_RESULT="$BUILD_DIR/nanoc0-driver.result"

mkdir -p "$OUT_DIR"
rm -f \
    "$OUT_DIR/NCOUT.ASM" "$OUT_DIR/ncout.asm" "$OUT_DIR/ncout.prg" \
    "$OUT_DIR/ASSFROMC.ASM" "$OUT_DIR/assfromc.asm"

nanoc_status_name() {
    case "$1" in
        0) echo ok ;;
        1) echo source ;;
        2) echo output ;;
        3) echo scanner ;;
        4) echo parser ;;
        5) echo expression ;;
        6) echo emit ;;
        7) echo layout ;;
        *) echo unknown ;;
    esac
}

report_driver_mailbox() {
    [ -s "$DRIVER_RESULT" ] || return 0
    set -- $(od -An -tu1 -N8 "$DRIVER_RESULT")
    [ "$#" -ge 8 ] || return 0

    stage=$2
    status=$3
    line=$(($4 + 256 * $5))
    detail=$6
    bss=$(($7 + 256 * $8))

    case "$stage" in
        1)
            echo "native bootstrap stage=assemble-nanoc0 assembler-status=$status" >&2
            ;;
        2)
            echo "native bootstrap stage=compile-small status=$(nanoc_status_name "$status")($status) line=$line detail=$detail bss=$bss" >&2
            ;;
        3)
            echo "native bootstrap stage=compile-ass.c status=$(nanoc_status_name "$status")($status) line=$line detail=$detail bss=$bss" >&2
            ;;
        *)
            echo "native bootstrap stage=$stage status=$status line=$line detail=$detail bss=$bss" >&2
            ;;
    esac
}

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

# current ass -> production nanoc0 -> small Phase 1 C -> generated ass, then the
# same native compiler instance -> exact committed bootstrap/ass.c -> ass source.
# If current ass rejects a production compiler line, print its streamed line from
# the native line buffer so CI identifies the exact machine-level incompatibility.
if ! TEST_DEBUG_SOURCE_LINE=1 VICE_TIMEOUT=180 VICE_FS_DIR="$ROOT" VICE_FS_DIR_9="$OUT_DIR" \
    VICE="$VICE" BUILD_DIR="$BUILD_DIR" \
    sh tests/run-test.sh "$BUILD_DIR/test_nanoc0_driver.prg" nanoc0-driver; then
    report_driver_mailbox
    exit 1
fi

report_driver_mailbox
set -- $(od -An -tu1 -N8 "$DRIVER_RESULT")
ASS_C_BSS=$(($7 + 256 * $8))
echo "bootstrap ass.c BSS: $ASS_C_BSS bytes"

if [ -f "$OUT_DIR/NCOUT.ASM" ]; then
    GENERATED="$OUT_DIR/NCOUT.ASM"
elif [ -f "$OUT_DIR/ncout.asm" ]; then
    GENERATED="$OUT_DIR/ncout.asm"
else
    echo "FAIL nanoc0-driver: generated NCOUT.ASM is missing" >&2
    exit 1
fi

if [ -f "$OUT_DIR/ASSFROMC.ASM" ]; then
    ASS_FROM_C="$OUT_DIR/ASSFROMC.ASM"
elif [ -f "$OUT_DIR/assfromc.asm" ]; then
    ASS_FROM_C="$OUT_DIR/assfromc.asm"
else
    echo "FAIL nanoc0-driver: generated ASSFROMC.ASM is missing" >&2
    exit 1
fi

# current ass -> small generated ass -> executable 6502 -> zero-argument main
# result. This keeps a short complete rung before the much larger bootstrap.
VICE_TIMEOUT=60 VICE_FS_DIR="$OUT_DIR" VICE="$VICE" BUILD_DIR="$BUILD_DIR" \
    sh tests/run-test.sh "$BUILD_DIR/test_nanoc0_generated.prg" nanoc0-generated

# Size is reported with vasm only as a measurement convenience. The native test
# above is the semantic/assembler authority for the small program. ass-from-c is
# intentionally retained as text for the next native bootstrap rung and review.
"$VASM" -Fbin -cbm-prg -o "$OUT_DIR/ncout.prg" "$GENERATED"
bytes=$(wc -c < "$OUT_DIR/ncout.prg")
echo "small generated loaded image: $((bytes - 2)) bytes"
echo "bootstrap generated ass source: $(wc -c < "$ASS_FROM_C") bytes"
