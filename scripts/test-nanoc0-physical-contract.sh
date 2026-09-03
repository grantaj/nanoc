#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR=${BUILD_DIR:-"$ROOT/build"}
VASM=${VASM:-vasm6502_oldstyle}
VICE=${VICE:-x64sc}

mkdir -p "$BUILD_DIR"
(
    cd "$ROOT/nanoc0"
    "$VASM" -Fbin -cbm-prg -o "$BUILD_DIR/test_nanoc0_physical_contract.prg" test_physical_contract.asm
)

VICE="$VICE" BUILD_DIR="$BUILD_DIR" sh "$ROOT/tests/run-test.sh" \
    "$BUILD_DIR/test_nanoc0_physical_contract.prg" nanoc0-physical-contract
