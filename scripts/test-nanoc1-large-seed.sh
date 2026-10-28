#!/bin/sh
# #108: run the *real* nanoc0-produced C compiler without inheriting its
# old 24 KiB assembler staging limit. This is a separate DEVELOPMENT rung.
# Only the header include is changed, to a checked non-overlapping memory map.
set -eu

VASM=${VASM:-vasm6502_oldstyle}
VICE=${VICE:-x64sc}
BUILD_DIR=${BUILD_DIR:-build}
ROOT=$(pwd)
OUT_DIR="$ROOT/$BUILD_DIR/nanoc0-integration"
LARGE_DIR="$ROOT/$BUILD_DIR/nanoc1-large-seed"
SEED="$LARGE_DIR/nanoc1-large.asm"
PRG="$LARGE_DIR/nanoc1-large.prg"

mkdir -p "$OUT_DIR" "$LARGE_DIR"
rm -f "$OUT_DIR/NANOC1.ASM" "$OUT_DIR/nanoc1.asm"

# Native ass builds native nanoc0, and native nanoc0 compiles the exact
# nanoc1/nanoc1.c. The resident ass is then released BEFORE assembling
# and running the potentially larger seed.
(
    cd ass
    "$VASM" -DNANOC_SEED_ONLY=1 -Fbin -cbm-prg \
        -o "../$BUILD_DIR/test_nanoc0_seed_only.prg" test_nanoc0_driver.asm
)
TEST_DEBUG_SOURCE_LINE=1 VICE_TIMEOUT=300 VICE_FS_DIR="$ROOT" \
    VICE_FS_DIR_9="$OUT_DIR" VICE="$VICE" BUILD_DIR="$BUILD_DIR" \
    sh tests/run-test.sh "$BUILD_DIR/test_nanoc0_seed_only.prg" nanoc0-seed-only

if [ -f "$OUT_DIR/NANOC1.ASM" ]; then
    source="$OUT_DIR/NANOC1.ASM"
else
    source="$OUT_DIR/nanoc1.asm"
fi
test -s "$source" || { echo "FAIL #108: native nanoc0 emitted no compiler assembly" >&2; exit 1; }
header=$(sed -n '1p' "$source")
case "$header" in
    *'../nanoc0/target/header-compiler.asm"'*) ;;
    *) echo "FAIL #108: unexpected first-generation compiler header" >&2; exit 1 ;;
esac
sed '1s@header-compiler.asm@header-compiler-large.asm@' "$source" > "$SEED"
tail -n +2 "$source" > "$LARGE_DIR/original-body"
tail -n +2 "$SEED" > "$LARGE_DIR/large-body"
cmp "$LARGE_DIR/original-body" "$LARGE_DIR/large-body"

# Static memory safety, checked before ANY load/execution:
#   $0800-$0fff harness, $1000-$3fff compiler BSS, $4000-$cfff code.
#   $d000-$ffff stays I/O/KERNAL. Zero page $fc-$ff stays scratch.
bss_hex=$(sed -n 's/^__nc_bss_end = NC_BSS+[$]\\([[:xdigit:]]*\\)$/\\1/p' "$SEED" | tail -n 1)
[ -n "$bss_hex" ] || { echo "FAIL #108: missing compiler BSS end" >&2; exit 1; }
bss=$((0x$bss_hex))
[ "$bss" -le 12288 ] || { echo 'FAIL #108: compiler BSS extends past $3fff' >&2; exit 1; }

"$VASM" -I"$ROOT/ass" -Fbin -cbm-prg -o "$PRG" "$SEED"
set -- $(od -An -tu1 -N2 "$PRG")
[ "$1" -eq 0 ] && [ "$2" -eq 64 ] || {
    echo 'FAIL #108: seed PRG does not load at $4000' >&2; exit 1;
}
seed_bytes=$(($(wc -c < "$PRG") - 2))
[ "$seed_bytes" -le 36864 ] || {
    echo "FAIL #108: compiled seed is $seed_bytes bytes and extends past cfff" >&2; exit 1;
}
echo "PASS #108: native-produced seed $seed_bytes bytes, BSS $bss bytes, non-overlapping map"

# Run the actual first-generation compiler with a small caller at $0800.
# The original strict all-native bootstrap/semantic tests stay unchanged.
case_compile() {
    name=$1
    path=$2
    timeout=$3
    printf '%s' "$path" > "$ROOT/$BUILD_DIR/n1job"
    rm -f "$OUT_DIR/N1OUT.ASM" "$OUT_DIR/n1out.asm"
    VICE_PRELOAD_PRG="$PRG" VICE_TIMEOUT="$timeout" \
        VICE_FS_DIR="$ROOT" VICE_FS_DIR_9="$OUT_DIR" \
        VICE="$VICE" BUILD_DIR="$BUILD_DIR" \
        sh tests/run-test.sh "$BUILD_DIR/test_nanoc1_compile.prg" "$name"
    set -- $(od -An -tu1 -N3 "$BUILD_DIR/$name.result")
    [ "$#" -ge 3 ] && [ "$2" -eq 0 ] && [ "$3" -eq 0 ] || {
        echo "FAIL #108: native compiler status for $name: ${2:-missing}/${3:-missing}" >&2
        exit 1
    }
    if [ -f "$OUT_DIR/N1OUT.ASM" ]; then
        cp "$OUT_DIR/N1OUT.ASM" "$LARGE_DIR/$name.asm"
    else
        cp "$OUT_DIR/n1out.asm" "$LARGE_DIR/$name.asm"
    fi
    echo "PASS #108: oversized seed compiled $path on the 6510"
}

case_compile large-index TESTS/NANOC1/INDEX-Y-LOOP.C 90
"$VASM" -I"$ROOT/ass" -Fbin -cbm-prg \
    -o "$LARGE_DIR/large-index.prg" "$LARGE_DIR/large-index.asm"
(
    cd ass
    "$VASM" -Fbin -cbm-prg -DN1_EXPECT_LOW=90 -DN1_EXPECT_HIGH=0 \
        -o "../$BUILD_DIR/test_nanoc1_large_execution.prg" test_nanoc1_execution.asm
)
VICE_PRELOAD_PRG="$LARGE_DIR/large-index.prg" VICE_TIMEOUT=90 \
    VICE_FS_DIR="$ROOT" VICE="$VICE" BUILD_DIR="$BUILD_DIR" \
    sh tests/run-test.sh "$BUILD_DIR/test_nanoc1_large_execution.prg" large-seed-execute
echo "PASS #108: real generated program executes on the 6510"

# The first generation now compiles its own *exact* source. The second
# generation's size is an independent measurement, not the size of the seed.
case_compile large-self NANOC1/NANOC1.C 360
self="$LARGE_DIR/large-self.asm"
header=$(sed -n '1p' "$self")
case "$header" in
    *'../nanoc1/target/header.asm"'*) ;;
    *) echo "FAIL #108: self-produced source has unexpected header" >&2; exit 1 ;;
esac
sed '1s@../nanoc1/target/header.asm@../nanoc0/target/header-compiler-large.asm@' \
    "$self" > "$LARGE_DIR/nanoc2-large.asm"
"$VASM" -I"$ROOT/ass" -Fbin -cbm-prg \
    -o "$LARGE_DIR/nanoc2-large.prg" "$LARGE_DIR/nanoc2-large.asm"
second_bytes=$(($(wc -c < "$LARGE_DIR/nanoc2-large.prg") - 2))
echo "PASS #108: exact nanoc1.c self-compilation; seed=$seed_bytes second-generation=$second_bytes bytes"
if [ "$second_bytes" -gt 36864 ]; then
    echo "SIZE DIAGNOSTIC: second generation still exceeds development code map" >&2
fi
