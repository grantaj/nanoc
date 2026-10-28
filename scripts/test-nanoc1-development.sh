#!/bin/sh
# #108 development-only oversize seed. The real native nanoc0 writes assembly,
# but no native assembler is kept resident when the larger compiler is run.
set -eu

VASM=${VASM:-vasm6502_oldstyle}
VICE=${VICE:-x64sc}
BUILD_DIR=${BUILD_DIR:-build-development}
ROOT=$(pwd)
OUT_DIR="$ROOT/$BUILD_DIR/nanoc0-integration"
mkdir -p "$OUT_DIR"

# Compile the production nanoc0 itself and the tiny native development driver.
# Host assembly here is explicitly NOT the strict all-native bootstrap oracle.
(
    cd nanoc0
    "$VASM" -Fbin -cbm-prg -o "../$BUILD_DIR/nanoc0.prg" nanoc0.asm
)
(
    cd ass
    "$VASM" -Fbin -cbm-prg -o "../$BUILD_DIR/test_nanoc0_development.prg" test_nanoc0_development.asm
    "$VASM" -Fbin -cbm-prg -o "../$BUILD_DIR/test_nanoc1_compile.prg" test_nanoc1_development_compile.asm
)
rm -f "$OUT_DIR/NANOC1DEV.ASM" "$OUT_DIR/nanoc1dev.asm"
VICE_PRELOAD_PRG="$ROOT/$BUILD_DIR/nanoc0.prg" \
    VICE_TIMEOUT=360 VICE_FS_DIR="$ROOT" VICE_FS_DIR_9="$OUT_DIR" \
    VICE="$VICE" BUILD_DIR="$BUILD_DIR" \
    sh tests/run-test.sh "$BUILD_DIR/test_nanoc0_development.prg" nanoc0-development

# The driver copies the real nanoc0-reported BSS usage to $05/$06.
set -- $(od -An -tu1 -N5 "$BUILD_DIR/nanoc0-development.result")
if [ "$#" -ne 5 ]; then
    echo "FAIL #108: missing development BSS report" >&2
    exit 1
fi
bss=$(( $4 + 256 * $5 ))
if [ "$bss" -gt 12288 ]; then
    echo "FAIL #108: compiler BSS $bss exceeds $a000-$cfff (12288 B)" >&2
    exit 1
fi
if [ -f "$OUT_DIR/NANOC1DEV.ASM" ]; then
    source="$OUT_DIR/NANOC1DEV.ASM"
else
    source="$OUT_DIR/nanoc1dev.asm"
fi
if [ ! -f "$source" ]; then
    echo "FAIL #108: native nanoc0 did not write development compiler source" >&2
    exit 1
fi

# Only now (in a separate emulator run) build/load the code image. The
# development C code occupies $0800-$9fff, BSS $a000-$cfff, caller $0400.
# None of ass's low-memory symbol/staging arena is alive in this process.
"$VASM" -I"$ROOT/ass" -Fbin -cbm-prg -o "$OUT_DIR/nanoc1.prg" "$source"
set -- $(od -An -tu1 -N2 "$OUT_DIR/nanoc1.prg")
origin=$(( $1 + 256 * $2 ))
if [ "$origin" -ne 2048 ]; then
    echo "FAIL #108: expected compiler origin $0800, got $origin" >&2
    exit 1
fi
loaded=$(($(wc -c < "$OUT_DIR/nanoc1.prg") - 2))
if [ "$loaded" -gt 38912 ]; then
    echo "FAIL #108: compiler code $loaded exceeds $0800-$9fff (38912 B)" >&2
    exit 1
fi
echo "PASS #108: separate development seed code=$loaded/38912 B BSS=$bss/12288 B"

# Reuse the production semantic corpus with the *same* real compiler binary.
# This harness lives at $0400; all user-program execution uses a fresh VICE
# process and the ordinary Phase 1 $0800/$4800 target layout.
VICE="$VICE" VASM="$VASM" BUILD_DIR="$BUILD_DIR" \
    sh scripts/test-nanoc1-baseline.sh

# Also compile the exact compiler source with the new compiler, as a size
# probe; never execute an image whose code/BSS regions overlap.
printf '%s' 'NANOC1/NANOC1.C' > "$ROOT/$BUILD_DIR/n1job"
rm -f "$OUT_DIR/N1OUT.ASM" "$OUT_DIR/n1out.asm"
VICE_PRELOAD_PRG="$OUT_DIR/nanoc1.prg" VICE_TIMEOUT=360 \
    VICE_FS_DIR="$ROOT" VICE_FS_DIR_9="$OUT_DIR" \
    VICE="$VICE" BUILD_DIR="$BUILD_DIR" \
    sh tests/run-test.sh "$BUILD_DIR/test_nanoc1_compile.prg" n1-self-compile
set -- $(od -An -tu1 -N3 "$BUILD_DIR/n1-self-compile.result")
if [ "$#" -lt 3 ] || [ "$2" -ne 0 ] || [ "$3" -ne 0 ]; then
    echo "FAIL #108: compiler could not compile its own exact source" >&2
    exit 1
fi
if [ -f "$OUT_DIR/N1OUT.ASM" ]; then
    next="$OUT_DIR/N1OUT.ASM"
else
    next="$OUT_DIR/n1out.asm"
fi
"$VASM" -I"$ROOT/ass" -Fbin -cbm-prg -o "$OUT_DIR/nanoc2-size.prg" "$next"
second=$(($(wc -c < "$OUT_DIR/nanoc2-size.prg") - 2))
echo "PASS #108: exact-source self-compile; seed=$loaded bytes, next-generation=$second bytes (fit not assumed)"
