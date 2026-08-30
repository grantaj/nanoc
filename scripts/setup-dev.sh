#!/bin/sh
set -eu

VICE_VERSION=3.7.1
VASM_COMMIT=a13e7e728a3dd5a9ba468bf479119e0bc23e70fd
SETUP_TMP=${TMPDIR:-/tmp}/nanoc-setup

if [ ! -r /etc/os-release ]; then
    echo "nanoc make setup currently supports Ubuntu 24.04 only." >&2
    exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release
if [ "${ID:-}" != "ubuntu" ] || [ "${VERSION_ID:-}" != "24.04" ]; then
    echo "nanoc make setup currently supports Ubuntu 24.04 only." >&2
    echo "This machine reports ${ID:-unknown} ${VERSION_ID:-unknown}." >&2
    echo "See docs/getting-started.md for the required tools on other hosts." >&2
    exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
    SUDO=
elif command -v sudo >/dev/null 2>&1; then
    SUDO=sudo
else
    echo "make setup needs root privileges (directly or through sudo)." >&2
    exit 1
fi

$SUDO apt-get update
$SUDO apt-get install -y build-essential cc65 git subversion vice

rm -rf "$SETUP_TMP"
mkdir -p "$SETUP_TMP"

svn export \
    "https://svn.code.sf.net/p/vice-emu/code/tags/v${VICE_VERSION}/vice/data" \
    "$SETUP_TMP/vice-data"
$SUDO mkdir -p /usr/share/vice
$SUDO cp -a "$SETUP_TMP/vice-data/." /usr/share/vice/

git clone https://github.com/StarWolf3000/vasm-mirror.git "$SETUP_TMP/vasm"
git -C "$SETUP_TMP/vasm" checkout "$VASM_COMMIT"
make -C "$SETUP_TMP/vasm" CPU=6502 SYNTAX=oldstyle
$SUDO install -m 0755 "$SETUP_TMP/vasm/vasm6502_oldstyle" /usr/local/bin/vasm6502_oldstyle

rm -rf "$SETUP_TMP"

for tool in make cl65 vasm6502_oldstyle x64sc timeout od; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "setup completed, but required command '$tool' is not on PATH." >&2
        exit 1
    fi
done

echo "nanoc development environment is ready."
