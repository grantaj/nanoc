#!/bin/sh
set -eu

VICE=${VICE:-x64sc}
BUILD_DIR=${BUILD_DIR:-build}
VICE_TIMEOUT=${VICE_TIMEOUT:-15}
PRG=$1
NAME=${2:-$(basename "$PRG" .prg)}

MONITOR_FILE="$BUILD_DIR/$NAME.mon"
RESULT_FILE="$BUILD_DIR/$NAME.result"
LOG_FILE="$BUILD_DIR/$NAME.vice.log"
SOURCE_LINE_FILE="$BUILD_DIR/$NAME.source-line"

rm -f "$MONITOR_FILE" "$RESULT_FILE" "$LOG_FILE" "$SOURCE_LINE_FILE"

# A CBM PRG carries its little-endian load address in its first two bytes.
# Start the test there rather than imposing a host-side entry address.
set -- $(od -An -tu1 -N2 "$PRG")
ENTRY=$(printf '%02x%02x' "$2" "$1")

cat > "$MONITOR_FILE" <<EOF
load "$PRG" 0
> 0001 36
watch store 0002
g $ENTRY
EOF

# Integration tests can ask VICE to save ass's current streamed source line when
# a native assembly fails. This is diagnostic only; the C64 result byte remains
# the test authority.
if [ "${TEST_DEBUG_SOURCE_LINE:-0}" -ne 0 ]; then
    echo "bsave \"$SOURCE_LINE_FILE\" 0 3200 3280" >> "$MONITOR_FILE"
fi

cat >> "$MONITOR_FILE" <<EOF
bsave "$RESULT_FILE" 0 0002 000b
quit
EOF

# These are standalone machine-code tests, not BASIC programs. $36 exposes the
# RAM underneath BASIC at $a000-$bfff while leaving KERNAL and I/O mapped in.
# That lets larger native images use the RAM VICE already loaded there without
# hiding KERNAL services needed by the assembler/compiler tests.
#
# -warp removes real-time throttling so native tests run as fast as the host can
# execute them. Tests with filesystem fixtures get two drives. Drive 8 is the
# input side; drive 9 defaults to the same host directory and is available for
# generated output. A test may override VICE_FS_DIR_9 when it needs separation.
if [ -n "${VICE_FS_DIR:-}" ]; then
    VICE_FS_DIR_9=${VICE_FS_DIR_9:-$VICE_FS_DIR}
    if ! timeout "${VICE_TIMEOUT}s" "$VICE" -console -warp +sound \
        -iecdevice8 -device8 1 -fs8 "$VICE_FS_DIR" \
        -iecdevice9 -device9 1 -fs9 "$VICE_FS_DIR_9" \
        -initbreak ready -moncommands "$MONITOR_FILE" >"$LOG_FILE" 2>&1; then
        echo "FAIL $NAME: VICE did not complete the test" >&2
        cat "$LOG_FILE" >&2
        exit 1
    fi
else
    if ! timeout "${VICE_TIMEOUT}s" "$VICE" -console -warp +sound \
        -initbreak ready -moncommands "$MONITOR_FILE" >"$LOG_FILE" 2>&1; then
        echo "FAIL $NAME: VICE did not complete the test" >&2
        cat "$LOG_FILE" >&2
        exit 1
    fi
fi

if [ ! -s "$RESULT_FILE" ]; then
    echo "FAIL $NAME: no result byte produced" >&2
    cat "$LOG_FILE" >&2
    exit 1
fi

RESULT=$(od -An -tu1 -N1 "$RESULT_FILE" | tr -d '[:space:]')

if [ "$RESULT" -eq 255 ]; then
    echo "PASS $NAME"
    exit 0
fi

echo "FAIL $NAME: code $RESULT" >&2
if [ "${TEST_DEBUG_WORKSPACE:-0}" -ne 0 ] || [ "$NAME" = selfhost ]; then
    set -- $(od -An -tu1 -N9 "$RESULT_FILE")
    if [ "$#" -ge 9 ]; then
        persistent_end=$(($2 + 256 * $3))
        persistent_name_end=$(($4 + 256 * $5))
        local_end=$(($6 + 256 * $7))
        local_name_end=$(($8 + 256 * $9))
        echo "symbol workspace: persistent entry-bytes=$((persistent_end - 40960)) name-bytes=$((48128 - persistent_name_end)) free=$((persistent_name_end - persistent_end)); local entry-bytes=$((local_end - 48128)) name-bytes=$((53248 - local_name_end)) free=$((local_name_end - local_end))" >&2
    fi
fi
if [ "${TEST_DEBUG_SOURCE_LINE:-0}" -ne 0 ] && [ -s "$SOURCE_LINE_FILE" ]; then
    printf 'native source line: ' >&2
    tr '\000' '\n' < "$SOURCE_LINE_FILE" | sed -n '1p' >&2
fi
cat "$LOG_FILE" >&2
exit 1
