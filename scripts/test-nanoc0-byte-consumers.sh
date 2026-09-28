#!/bin/sh
set -eu

OUT=${1:-tests/nanoc0-stmt/RET8OUT.ASM}
if [ ! -f "$OUT" ]; then
    lower=$(printf '%s' "$OUT" | tr '[:upper:]' '[:lower:]')
    [ -f "$lower" ] && OUT=$lower
fi
if [ ! -f "$OUT" ]; then
    echo "FAIL byte-consumer-shape: generated source is missing" >&2
    exit 1
fi

body() {
    awk -v label="__c_$1:" '
        $0 == label { inside=1; next }
        inside && $0 ~ /^__c_[A-Za-z0-9_]+:$/ { exit }
        inside { print }
    ' "$OUT"
}

require() {
    fn=$1
    pattern=$2
    if ! body "$fn" | grep -Eq "$pattern"; then
        echo "FAIL byte-consumer-shape: $fn missing $pattern" >&2
        body "$fn" >&2
        exit 1
    fi
}

forbid() {
    fn=$1
    pattern=$2
    if body "$fn" | grep -Eq "$pattern"; then
        echo "FAIL byte-consumer-shape: $fn unexpectedly contains $pattern" >&2
        body "$fn" >&2
        exit 1
    fi
}

# A char destination observes only the low byte. Semantic C promotion still
# exists in the parser/type state, but target code must not manufacture X merely
# to throw it away at this boundary.
require byte_return_sub '^[[:space:]]*sbc #\$20$'
forbid  byte_return_sub '^[[:space:]]*sbc #\$00$'

require byte_assignment_add '^[[:space:]]*adc #\$0A$'
forbid  byte_assignment_add '^[[:space:]]*(adc #\$00|ldx #\$00)$'

# Literal *3 has a shorter direct spelling than a helper call.
for fn in byte_assignment_mul3 byte_initializer_mul3 byte_argument_mul3 byte_indexed_mul3; do
    require "$fn" '^[[:space:]]*asl NC_TMP$'
    require "$fn" '^[[:space:]]*adc NC_TMP$'
    forbid  "$fn" '^[[:space:]]*jsr __nc_mul(8|16)$'
done

# Arbitrary byte-observed multiplication uses only the low-product helper.
require byte_variable_mul '^[[:space:]]*jsr __nc_mul8$'
forbid  byte_variable_mul '^[[:space:]]*jsr __nc_mul16$'
require word_variable_mul '^[[:space:]]*jsr __nc_mul16$'
forbid  word_variable_mul '^[[:space:]]*jsr __nc_mul8$'

# The same source operation must remain 16-bit when a later C operation can see
# the high byte. Grouping must not leak an outer byte consumer into the multiply.
for fn in word_mul3 nested_word_mul3 word_argument_mul3 byte_argument_nested_word; do
    require "$fn" '^[[:space:]]*jsr __nc_mul16$'
done

# Exact >> 8 leaves the old high byte in A. Zero-extension into X is deferred
# until a real word consumer asks for it.
require byte_shift8 '^[[:space:]]*txa$'
forbid  byte_shift8 '^[[:space:]]*ldx #\$00$'
require word_shift8 '^[[:space:]]*txa$'
require word_shift8 '^[[:space:]]*ldx #\$00$'

echo "PASS byte-consumer-shape"
