#!/bin/sh
# Issue #101. Exercise the same native compiler produced by the existing
# nanoc0 -> nanoc1.c -> ass bootstrap. No host-language compiler model.
set -eu

VASM=${VASM:-vasm6502_oldstyle}
VICE=${VICE:-x64sc}
BUILD_DIR=${BUILD_DIR:-build}
ROOT=$(pwd)
OUT_DIR="$ROOT/$BUILD_DIR/nanoc0-integration"
COMPILER="$OUT_DIR/nanoc1.prg"

if [ ! -f "$COMPILER" ]; then
    echo "FAIL nanoc1 baseline: run scripts/test-nanoc0-integration.sh first" >&2
    exit 1
fi

# A/X returns from the actual compiler are captured by test_nanoc1_compile.
case_source() {
    name=$1
    source=$2
    outcome=$3
    execution=$4
    low=${5:-0}
    high=${6:-0}

    printf '%s' "$source" > "$ROOT/$BUILD_DIR/n1job"
    rm -f "$OUT_DIR/N1OUT.ASM" "$OUT_DIR/n1out.asm"
    compile_timeout=90
    if [ "$name" = n1-ass ]; then
        compile_timeout=360
    fi
    VICE_PRELOAD_PRG="$COMPILER" VICE_TIMEOUT="$compile_timeout" \
        VICE_FS_DIR="$ROOT" VICE_FS_DIR_9="$OUT_DIR" \
        VICE="$VICE" BUILD_DIR="$BUILD_DIR" \
        sh tests/run-test.sh "$BUILD_DIR/test_nanoc1_compile.prg" "$name-compile"

    set -- $(od -An -tu1 -N3 "$BUILD_DIR/$name-compile.result")
    if [ "$#" -lt 3 ] || [ "$3" -ne 0 ]; then
        echo "FAIL $name: invalid compiler high status ${3:-missing}" >&2
        exit 1
    fi
    status=$2
    if [ "$outcome" = reject ]; then
        if [ "$status" -eq 0 ]; then
            echo "FAIL $name: malformed Phase 1 source was accepted" >&2
            exit 1
        fi
        echo "PASS $name: rejected by native nanoc1 (status $status)"
        return
    fi
    if [ "$status" -ne 0 ]; then
        echo "FAIL $name: native nanoc1 returned $status, expected 0" >&2
        exit 1
    fi
    if [ -f "$OUT_DIR/N1OUT.ASM" ]; then
        asm="$OUT_DIR/N1OUT.ASM"
    elif [ -f "$OUT_DIR/n1out.asm" ]; then
        asm="$OUT_DIR/n1out.asm"
    else
        echo "FAIL $name: successful compiler did not produce N1OUT.ASM" >&2
        exit 1
    fi
    cp "$asm" "$OUT_DIR/$name.asm"
    "$VASM" -I"$ROOT/ass" -Fbin -cbm-prg -o "$OUT_DIR/$name.prg" "$asm"
    bytes=$(wc -c < "$OUT_DIR/$name.prg")
    loaded=$((bytes - 2))
    source_bytes=$(wc -c < "$asm")
    echo "PASS $name: compiled and assembled ($source_bytes source bytes; $loaded loaded bytes)"

    if [ "$execution" = run ]; then
        # $0800 code, $4800 BSS. An oversized image cannot safely run.
        if [ "$loaded" -gt 16384 ]; then
            echo "FAIL $name: code exceeds the $0800-$47ff Phase 1 region ($loaded bytes)" >&2
            exit 1
        fi
        (
            cd ass
            "$VASM" -Fbin -cbm-prg \
                -DN1_EXPECT_LOW="$low" -DN1_EXPECT_HIGH="$high" \
                -o "../$BUILD_DIR/test_nanoc1_execution.prg" \
                test_nanoc1_execution.asm
        )
        VICE_PRELOAD_PRG="$OUT_DIR/$name.prg" VICE_TIMEOUT=90 \
            VICE_FS_DIR="$ROOT" VICE_FS_DIR_9="$OUT_DIR" \
            VICE="$VICE" BUILD_DIR="$BUILD_DIR" \
            sh tests/run-test.sh "$BUILD_DIR/test_nanoc1_execution.prg" "$name-execute"
    fi
}

# Exact existing Phase 1 sources: lexical input, declarations, types,
# expressions, 8/16-bit values, arrays, indexed stores, structured statements,
# nested calls, argument staging and I/O.
case_source n1-decls TESTS/NANOC0-SRC/DECLS.C accept run 0 0
case_source n1-expressions TESTS/NANOC0-EXPR/EXPRESSIONS.C accept compile
case_source n1-return8 TESTS/NANOC0-STMT/RETURN8.C accept run 90 0
case_source n1-pointer-index TESTS/NANOC1/POINTER-INDEX.C accept run 90 0
case_source n1-statements TESTS/NANOC0-STMT/STATEMENTS.C accept run 52 18

# #102: the last semantic value must be consumed from A/X, not sent to
# the hardware stack and immediately retrieved. Inspect the *real* emitter
# output after executing it; do not test a private copy of emitter logic.
case_source n1-ax-return TESTS/NANOC1/AX-RETURN.C accept run 90 0
if grep -Eq '^[[:space:]]*(pha|pla)[[:space:]]*$' "$OUT_DIR/n1-ax-return.asm"; then
    echo "FAIL #102: a literal return was needlessly materialised on the stack" >&2
    exit 1
fi
echo "PASS #102: literal-to-return uses A/X without hardware-stack round-trip"

# Check *composed* producer/consumer paths in the real native-emitted source.
# The add result is consumed by a local store, and the equality result by a
# conditional branch. Neither should visit the hardware stack at that boundary.
case_source n1-ax-consumers TESTS/NANOC1/AX-CONSUMERS.C accept run 90 0
if ! awk '
    $1 == "adc" && $2 == "NC_TMP" { add_seen = 1; in_add = 1; next }
    in_add && ($1 == "pha" || $1 == "pla") { bad = 1; exit }
    in_add && $1 == "sta" && index($2, "__v") == 1 {
        store_seen = 1; in_add = 0
    }
    $1 == "jsr" && $2 == "__nc_eq16" { compare_seen = 1; in_cmp = 1; next }
    in_cmp && ($1 == "pha" || $1 == "pla") { bad = 1; exit }
    in_cmp && ($1 == "beq" || $1 == "bne") {
        branch_seen = 1; in_cmp = 0
    }
    END {
        if (bad || !add_seen || !store_seen || !compare_seen || !branch_seen)
            exit 1
    }
' "$OUT_DIR/n1-ax-consumers.asm"; then
    echo "FAIL #102: binary/store or compare/branch crossed the hardware stack" >&2
    exit 1
fi
echo "PASS #102: binary-to-store and comparison-to-branch keep A/X"

case_source n1-ax-nested TESTS/NANOC1/AX-NESTED.C accept run 90 0

rm -f "$OUT_DIR/DTEST" "$OUT_DIR/dtest" "$OUT_DIR/SMOKE.ASM" "$OUT_DIR/smoke.asm"
case_source n1-runtime TESTS/NANOC0-RUNTIME/RUNTIME.C accept run 0 0
if [ -f "$OUT_DIR/DTEST" ]; then dtest="$OUT_DIR/DTEST"; else dtest="$OUT_DIR/dtest"; fi
printf 'Q' | cmp - "$dtest"
if [ -f "$OUT_DIR/SMOKE.ASM" ]; then smoke="$OUT_DIR/SMOKE.ASM"; else smoke="$OUT_DIR/smoke.asm"; fi
grep -Fq '* = $2000' "$smoke"
grep -Fq 'byte $2a' "$smoke"
echo "PASS n1-runtime: device-9 output contents"

# Error-category numbering is internal; rejection is the semantic assertion.
case_source n1-bad-scan TESTS/NANOC0-SRC/BADCHAR.C reject none
case_source n1-undeclared TESTS/NANOC0-STMT/UNDECLARED.C reject none
case_source n1-unsupported TESTS/NANOC0-STMT/FOR.C reject none
case_source n1-call-count TESTS/NANOC0-CALL/CNTBAD.C reject none
case_source n1-call-type TESTS/NANOC0-CALL/TYPBAD.C reject none
case_source n1-forward-call TESTS/NANOC0-CALL/LATBAD.C reject none
case_source n1-control-depth TESTS/NANOC0-STMT/DEPTHBAD.C reject none
case_source n1-operator-depth TESTS/NANOC1/OPERATOR-DEPTH.C reject none

# Whole-program stress: no alternate assembler source and no C rewrite.
case_source n1-ass BOOTSTRAP/ASS.C accept compile
compiler_asm="$OUT_DIR/NANOC1.ASM"
if [ ! -f "$compiler_asm" ]; then compiler_asm="$OUT_DIR/nanoc1.asm"; fi
compiler_source=$(wc -c < "$compiler_asm")
compiler_loaded=$(($(wc -c < "$COMPILER") - 2))
ass_source=$(wc -c < "$OUT_DIR/n1-ass.asm")
ass_loaded=$(($(wc -c < "$OUT_DIR/n1-ass.prg") - 2))
compiler_version=$(git rev-parse HEAD)
compiler_blob=$(git rev-parse HEAD:nanoc1/nanoc1.c)
{
    printf 'nanoc1-repository-commit=%s\n' "$compiler_version"
    printf 'nanoc1-source-blob=%s\n' "$compiler_blob"
    printf 'nanoc1-generated-assembly-bytes=%s\n' "$compiler_source"
    printf 'nanoc1-loaded-bytes=%s\n' "$compiler_loaded"
    printf 'ass.c-generated-assembly-bytes=%s\n' "$ass_source"
    printf 'ass.c-generated-loaded-bytes=%s\n' "$ass_loaded"
    printf 'ass.c-generated-code-limit=16384\n'
    printf 'ass.c-generated-pha-count=%s\n' "$(grep -Ec '^[[:space:]]*pha[[:space:]]*$' "$OUT_DIR/n1-ass.asm" || true)"
    printf 'ass.c-generated-pla-count=%s\n' "$(grep -Ec '^[[:space:]]*pla[[:space:]]*$' "$OUT_DIR/n1-ass.asm" || true)"
} > "$OUT_DIR/nanoc1-baseline.txt"
cat "$OUT_DIR/nanoc1-baseline.txt"

# #101 checks Phase 1 semantics and exact-source compilation. A full
# assembler execution oracle is still required for #37 self-hosting, but its
# 16 KiB program-region fit is the *result* expected from #102's code-generation
# work, not a prerequisite for starting it.
if [ "$ass_loaded" -gt 16384 ]; then
    excess=$((ass_loaded - 16384))
    echo "SIZE DIAGNOSTIC: ass.c generated image exceeds the 16 KiB runtime window by $excess bytes; full native assembler oracle deferred to #37" >&2
else
    echo "SIZE DIAGNOSTIC: ass.c image fits, but native assembler oracle is a separate #37 convergence gate" >&2
fi
echo "PASS #101: exact ass.c compiled by native nanoc1 and assembled; size reported separately"
