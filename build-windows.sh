#!/usr/bin/env bash
# Cross-compile roguelike.exe (Windows x86-64) from Linux.
#
# Odin refuses to cross-link to Windows on its own (it only supports Android),
# so we do it in three steps:
#   1. fetch the real Windows raylib import libraries from the Odin repo
#      (the copies installed locally are Git-LFS pointer stubs),
#   2. the Odin compiler emits Windows COFF objects (`-build-mode:obj`),
#   3. Zig's bundled MinGW-w64 toolchain links them into a .exe:
#        zig cc -target x86_64-windows-gnu ...
#
# Requirements: odin, zig, ar (binutils), curl.
# Usage: ./build-windows.sh [output.exe]
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

OUT="${1:-roguelike.exe}"
BUILD=".build-windows"
OBJDIR="$BUILD/obj"
LIBDIR="$BUILD/raylib"
STUBDIR="$BUILD/stubs"
mkdir -p "$OBJDIR" "$LIBDIR" "$STUBDIR"

is_archive() { [ "$(head -c7 "$1" 2>/dev/null || true)" = '!<arch>' ]; }

# --- 1. Real Windows raylib import libs -------------------------------------
# The ones shipped with Odin are Git-LFS pointer stubs; fetch the blobs from
# the matching Odin commit (taken from `odin version`, overridable via ODIN_REF).
REF="${ODIN_REF:-$(odin version | sed -E 's/.*:([0-9a-fA-F]{7,})$/\1/')}"
BASE="https://media.githubusercontent.com/media/odin-lang/Odin/$REF/vendor/raylib/windows"

fetch_lib() {
	local name="$1" dest="$LIBDIR/$1"
	if [ -f "$dest" ] && is_archive "$dest" && [ "$(stat -c%s "$dest")" -gt 100000 ]; then
		return
	fi
	echo "==> fetching windows/$name (Odin@$REF)"
	curl -fsSL "$BASE/$name" -o "$dest.tmp"
	mv "$dest.tmp" "$dest"
	if ! is_archive "$dest"; then
		echo "error: $name did not download as an archive" >&2
		exit 1
	fi
}

fetch_lib raylib.lib
fetch_lib raygui.lib

# --- 2. Compile the Odin sources to Windows object files --------------------
# `-build-mode:obj` never links, so the LFS stubs in Odin's vendor dir are fine.
echo "==> compiling Odin objects (windows_amd64)"
rm -f "$OBJDIR"/win-*.obj "$OBJDIR"/win-*.o
odin build . -target:windows_amd64 -build-mode:obj -out:"$OBJDIR/win"

# --- 3. Stub the MSVC-only default libs -------------------------------------
# raylib.lib carries /DEFAULTLIB:MSVCRT / OLDNAMES / uuid directives. The CRT
# symbols resolve via Zig's UCRT import libs, so empty archives satisfy the
# linker's lookups.
ar rcs "$STUBDIR/libMSVCRT.a"
ar rcs "$STUBDIR/libOLDNAMES.a"
ar rcs "$STUBDIR/libuuid.a"

# --- 4. Link ----------------------------------------------------------------
echo "==> linking $OUT"
zig cc -target x86_64-windows-gnu \
	windows_shims.c \
	"$OBJDIR"/win-*.obj \
	"$LIBDIR/raylib.lib" "$LIBDIR/raygui.lib" \
	-L"$STUBDIR" \
	-lwinmm -lgdi32 -luser32 -lshell32 -lbcrypt -ladvapi32 \
	-Wl,--subsystem,windows \
	-o "$OUT"

echo "==> done: $OUT"
