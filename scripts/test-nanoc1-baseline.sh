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

if [ "$ass_loaded" -gt 16384 ]; then
    echo "FAIL #101: exact ass.c exceeds the current nanoc1 $0800-$47ff code region; the bootstrap oracle cannot run" >&2
    exit 1
fi
# Reuse the established native #58 oracle verbatim. It reads its input under
# the fixed ASSFROMC.ASM filename, so temporarily supply nanoc1's generated
# assembly there. Save and restore nanoc0's original generated artifact.
if [ -f "$OUT_DIR/ASSFROMC.ASM" ]; then
    oracle_input="$OUT_DIR/ASSFROMC.ASM"
elif [ -f "$OUT_DIR/assfromc.asm" ]; then
    oracle_input="$OUT_DIR/assfromc.asm"
else
    echo "FAIL #101: missing existing assembler-oracle input" >&2
    exit 1
fi
oracle_saved="$OUT_DIR/nanoc0-assfromc.saved"
cp "$oracle_input" "$oracle_saved"
restore_oracle_input() {
    cp "$oracle_saved" "$oracle_input"
    rm -f "$oracle_saved"
}
trap 'restore_oracle_input' EXIT
cp "$OUT_DIR/n1-ass.asm" "$oracle_input"

# The earlier nanoc0 baseline treats a timeout as non-gating; #101 cannot.
# A missing result byte is an unfinished proof, not a pass.
(
    cd ass
    "$VASM" -Fbin -cbm-prg -o "../$BUILD_DIR/test_nanoc1_ass_from_c.prg" \
        test_nanoc1_ass_from_c.asm
)
VICE_TIMEOUT=360 VICE_FS_DIR="$ROOT" VICE="$VICE" BUILD_DIR="$BUILD_DIR" \
    sh tests/run-test.sh "$BUILD_DIR/test_nanoc1_ass_from_c.prg" nanoc1-ass-oracle
restore_oracle_input
trap - EXIT
echo "PASS #101: native ass bootstrap/oracle matched for nanoc1-generated ass.c"
