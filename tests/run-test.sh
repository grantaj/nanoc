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

rm -f "$MONITOR_FILE" "$RESULT_FILE" "$LOG_FILE"

# A CBM PRG carries its little-endian load address in its first two bytes.
# Start the test there rather than imposing a host-side entry address.
set -- $(od -An -tu1 -N2 "$PRG")
ENTRY=$(printf '%02x%02x' "$2" "$1")

cat > "$MONITOR_FILE" <<EOF
load "$PRG" 0
watch store 0002
g $ENTRY
bsave "$RESULT_FILE" 0 0002 0003
quit
EOF

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
cat "$LOG_FILE" >&2
exit 1
