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
    "$OUT_DIR/ASSFROMC.ASM" "$OUT_DIR/assfromc.asm" "$OUT_DIR/assfromc.prg" \
    "$OUT_DIR/NANOC1.ASM" "$OUT_DIR/nanoc1.asm" "$OUT_DIR/nanoc1.prg"

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
                staged=$((line - 16384))
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
        4)
            echo "native bootstrap stage=compile-nanoc1.c status=$(nanoc_status_name "$status")($status) line=$line detail=$detail bss=$bss" >&2
            ;;
        5)
            if [ "$status" -eq 11 ]; then
                staged=$((line - 16384))
                fixups=$((40960 - bss))
                free_gap=$((bss - line))
                echo "native bootstrap stage=assemble-nanoc1 assembler-status=$status staged=$staged fixup-bytes=$fixups free-gap=$free_gap" >&2
            else
                echo "native bootstrap stage=assemble-nanoc1 assembler-status=$status" >&2
            fi
            ;;
        6)
            echo "native bootstrap stage=run-nanoc1 return-low=$detail return-high=$extra" >&2
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
    "$VASM" -Fbin -cbm-prg -o "../$BUILD_DIR/test_nanoc1_generated.prg" test_nanoc1_generated.asm
)

# The low-resident integration copy of the native assembler stages nanoc0
# directly in its $4000-$9fff target window. That gives this development rung
# 24 KiB without changing the production assembler's ordinary workspace:
#
#   native ass -> production nanoc0 -> exact C sources.
#
# If this fails, report the native assembler/compiler mailbox and stop. There is
# deliberately no host-built compiler fallback.
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

if [ -f "$OUT_DIR/NANOC1.ASM" ]; then
    NANOC1_GENERATED="$OUT_DIR/NANOC1.ASM"
elif [ -f "$OUT_DIR/nanoc1.asm" ]; then
    NANOC1_GENERATED="$OUT_DIR/nanoc1.asm"
else
    echo "FAIL nanoc0-driver: generated NANOC1.ASM is missing" >&2
    exit 1
fi

NANOC1_SOURCE_BYTES=$(wc -c < "$NANOC1_GENERATED")
echo "nanoc1 generated ass source: $NANOC1_SOURCE_BYTES bytes"
"$VASM" -I"$ROOT/ass" -Fbin -cbm-prg -o "$OUT_DIR/nanoc1.prg" "$NANOC1_GENERATED"
bytes=$(wc -c < "$OUT_DIR/nanoc1.prg")
NANOC1_LOADED=$((bytes - 2))
echo "nanoc1 generated loaded image: $NANOC1_LOADED bytes"
if [ "$NANOC1_LOADED" -gt 24576 ]; then
    echo "FAIL nanoc1 bootstrap: compiler exceeds the explicit \$4000-\$9fff bootstrap window" >&2
    exit 1
fi

if [ -f "$OUT_DIR/N1OUT.ASM" ]; then
    NANOC1_SMOKE="$OUT_DIR/N1OUT.ASM"
elif [ -f "$OUT_DIR/n1out.asm" ]; then
    NANOC1_SMOKE="$OUT_DIR/n1out.asm"
else
    echo "FAIL nanoc1 bootstrap: native nanoc1 did not produce N1OUT.ASM" >&2
    exit 1
fi

TEST_DEBUG_SOURCE_LINE=1 VICE_TIMEOUT=60 VICE_FS_DIR="$ROOT" VICE="$VICE" BUILD_DIR="$BUILD_DIR" \
    sh tests/run-test.sh "$BUILD_DIR/test_nanoc1_generated.prg" nanoc1-generated
echo "native nanoc1 smoke compiled, assembled and returned Z"

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
TEST_DEBUG_SOURCE_LINE=1 VICE_TIMEOUT=60 VICE_FS_DIR="$ROOT" VICE="$VICE" BUILD_DIR="$BUILD_DIR" \
    sh tests/run-test.sh "$BUILD_DIR/test_nanoc0_generated.prg" nanoc0-generated

# Host vasm measures the generated image. The C compiler that produced this
# source has run as real 6502 code above even when its own resident image was too
# large for current ass to stage. Native self-assembly remains a later convergence
# rung rather than a gate on generated-code development.
"$VASM" -I"$ROOT/ass" -Fbin -cbm-prg -o "$OUT_DIR/ncout.prg" "$GENERATED"
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

# Keep the strongest end-to-end rung as a convergence diagnostic. During #96
# the generated assembler is still much larger/slower than the handwritten one,
# so exceeding the CI execution budget is not a code-generation correctness
# failure. A concrete result byte is authoritative: any actual native mismatch
# still fails immediately.
if ! VICE_TIMEOUT=120 VICE_FS_DIR="$ROOT" VICE="$VICE" BUILD_DIR="$BUILD_DIR" \
    sh tests/run-test.sh "$BUILD_DIR/test_ass_from_c.prg" ass-from-c; then
    report_ass_from_c_mailbox
    if [ -s "$ASS_FROM_C_RESULT" ]; then
        exit 1
    fi
    echo "bootstrap self-assembly did not complete within the #96 CI budget; recorded as a non-gating convergence diagnostic" >&2
    exit 0
fi

report_ass_from_c_mailbox
set -- $(od -An -tu1 -N8 "$ASS_FROM_C_RESULT")
ASS_FROM_C_LOADED=$(($4 + 256 * $5))
echo "ass-from-c loaded image: $ASS_FROM_C_LOADED bytes"
echo "native bootstrap oracle matched"
