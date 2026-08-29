#!/bin/sh
set -eu

VICE=${VICE:-x64sc}
BUILD_DIR=${BUILD_DIR:-build}
PRG=$1
NAME=${2:-$(basename "$PRG" .prg)}
ENTRY=${3:-c000}

MONITOR_FILE="$BUILD_DIR/$NAME.mon"
RESULT_FILE="$BUILD_DIR/$NAME.result"
LOG_FILE="$BUILD_DIR/$NAME.vice.log"

rm -f "$MONITOR_FILE" "$RESULT_FILE" "$LOG_FILE"

cat > "$MONITOR_FILE" <<EOF
load "$PRG" 0
watch store 0002
g $ENTRY
bsave "$RESULT_FILE" 0 0002 0003
quit
EOF

if ! timeout 15s "$VICE" -console -warp +sound -initbreak ready -moncommands "$MONITOR_FILE" >"$LOG_FILE" 2>&1; then
    echo "FAIL $NAME: VICE did not complete the test" >&2
    cat "$LOG_FILE" >&2
    exit 1
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
