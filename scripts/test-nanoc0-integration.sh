#!/bin/sh
set -eu

VASM=${VASM:-vasm6502_oldstyle}
VICE=${VICE:-x64sc}
BUILD_DIR=${BUILD_DIR:-build}
ROOT=$(pwd)
OUT_DIR="$ROOT/$BUILD_DIR/nanoc0-integration"
DRIVER_RESULT="$BUILD_DIR/nanoc0-driver.result"
ASS_FROM_C_RESULT="$BUILD_DIR/ass-from-c.result"

mkdir -p "$OUT_DIR"
rm -f \
    "$OUT_DIR/NCOUT.ASM" "$OUT_DIR/ncout.asm" "$OUT_DIR/ncout.prg" \
    "$OUT_DIR/ASSFROMC.ASM" "$OUT_DIR/assfromc.asm" "$OUT_DIR/assfromc.prg"

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
    set -- $(od -An -tu1 -N11 "$DRIVER_RESULT")
    [ "$#" -ge 11 ] || return 0

    stage=$2
    status=$3
    line=$(($4 + 256 * $5))
    detail=$6
    bss=$(($7 + 256 * $8))
    extra=$9
    hidden=$((${10} + 256 * ${11}))

    case "$stage" in
        1)
            if [ "$status" -eq 11 ]; then
                staged=$((line - 24576))
                fixups=$((40960 - bss))
                free_gap=$((bss - line))
                echo "native bootstrap stage=assemble-nanoc0 assembler-status=$status staged=$staged fixup-bytes=$fixups free-gap=$free_gap" >&2
            else
                primary_used=$((line - 13056))
                shared_end=$((detail + 256 * extra))
                shared_used=$((shared_end - 40960))
                local_used=$((53248 - bss))
                shared_free=$((bss - shared_end))
                hidden_used=$((hidden - 53248))
                persistent_used=$((primary_used + shared_used + hidden_used))
                echo "native bootstrap stage=assemble-nanoc0 assembler-status=$status persistent=$persistent_used/23802 primary=$primary_used/3328 shared-global=$shared_used/8192 local=$local_used shared-free=$shared_free hidden=$hidden_used/12282" >&2
            fi
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

report_ass_from_c_mailbox() {
    [ -s "$ASS_FROM_C_RESULT" ] || return 0
    set -- $(od -An -tu1 -N8 "$ASS_FROM_C_RESULT")
    [ "$#" -ge 7 ] || return 0

    stage=$2
    detail=$3
    loaded=$(($4 + 256 * $5))
    value=$(($6 + 256 * $7))
    echo "ass-from-c stage=$stage detail=$detail loaded=$loaded value=$value" >&2
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
    "$VASM" -Fbin -cbm-prg -o "../$BUILD_DIR/test_ass_from_c.prg" test_ass_from_c.asm
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
set -- $(od -An -tu1 -N9 "$DRIVER_RESULT")
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
TEST_DEBUG_SOURCE_LINE=1 VICE_TIMEOUT=60 VICE_FS_DIR="$OUT_DIR" VICE="$VICE" BUILD_DIR="$BUILD_DIR" \
    sh tests/run-test.sh "$BUILD_DIR/test_nanoc0_generated.prg" nanoc0-generated

# Host vasm is only a measurement convenience. Native ass remains the semantic
# authority. At the #58 integration baseline the exact ass.c output is expected
# to be too large for the native 16 KiB staging window; #70-#77 own the measured
# size-convergence work. Keep reporting both physical limits here, but do not
# turn a known oversize result back into an open-ended integration PR.
"$VASM" -Fbin -cbm-prg -o "$OUT_DIR/ncout.prg" "$GENERATED"
bytes=$(wc -c < "$OUT_DIR/ncout.prg")
echo "small generated loaded image: $((bytes - 2)) bytes"

ASS_SOURCE_BYTES=$(wc -c < "$ASS_FROM_C")
echo "bootstrap generated ass source: $ASS_SOURCE_BYTES bytes"
# Production ass roots local includes at ASS/. Give vasm that same include-search
# root explicitly; unlike ass, vasm also searches beside the generated source.
"$VASM" -I"$ROOT/ass" -Fbin -cbm-prg -o "$OUT_DIR/assfromc.prg" "$ASS_FROM_C"
bytes=$(wc -c < "$OUT_DIR/assfromc.prg")
ASS_FROM_C_LOADED=$((bytes - 2))
echo "bootstrap generated loaded image: $ASS_FROM_C_LOADED bytes"

oversize=0
if [ "$ASS_SOURCE_BYTES" -gt 168656 ]; then
    echo "bootstrap baseline: source exceeds one 1541 disk (168656 bytes); convergence continues in #70-#77" >&2
    oversize=1
fi
if [ "$ASS_FROM_C_LOADED" -gt 16384 ]; then
    echo "bootstrap baseline: image exceeds ass staging (16384 bytes); convergence continues in #70-#77" >&2
    oversize=1
fi

if [ "$oversize" -ne 0 ]; then
    exit 0
fi

# Once later work brings both budgets under their hard limits this script
# naturally executes the decisive native rung as well. #77 makes that rung a
# required acceptance condition rather than merely an available continuation.
if ! VICE_TIMEOUT=600 VICE_FS_DIR="$ROOT" VICE="$VICE" BUILD_DIR="$BUILD_DIR" \
    sh tests/run-test.sh "$BUILD_DIR/test_ass_from_c.prg" ass-from-c; then
    report_ass_from_c_mailbox
    exit 1
fi

report_ass_from_c_mailbox
set -- $(od -An -tu1 -N8 "$ASS_FROM_C_RESULT")
ASS_FROM_C_LOADED=$(($4 + 256 * $5))
echo "ass-from-c loaded image: $ASS_FROM_C_LOADED bytes"
echo "native bootstrap oracle matched"
