#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
engine_dir="$repo_dir/Vendor/gnubg"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/gnubg-native.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

"$script_dir/build-engine-macos.sh"

cd "$repo_dir"

common_flags="-DHAVE_CONFIG_H -DLOCALEDIR=\".\" -I$engine_dir -I$engine_dir/lib -I$engine_dir/pixmaps -I$repo_dir/native/include"
pkg_cflags=$(pkg-config --cflags glib-2.0 gthread-2.0 gobject-2.0 cairo pango pangocairo libcurl freetype2 libpng)
pkg_libs=$(pkg-config --libs glib-2.0 gthread-2.0 gobject-2.0 cairo pango pangocairo libcurl freetype2 libpng)

# shellcheck disable=SC2086
cc -std=gnu23 $common_flags $pkg_cflags \
    -c native/engine/gnubg_native.c -o "$tmp_dir/gnubg_native.o"
cc -std=gnu23 -I native/include \
    -c native/tests/gnubg_native_smoke.c -o "$tmp_dir/gnubg_native_smoke.o"

set --
for object in "$engine_dir"/*.o; do
    case "$object" in
        "$engine_dir"/gnubg.o|"$engine_dir"/makebearoff.o|\
        "$engine_dir"/makehyper.o|"$engine_dir"/makeweights.o|\
        "$engine_dir"/bearoffdump.o) ;;
        *) set -- "$@" "$object" ;;
    esac
done

# shellcheck disable=SC2086
cc "$tmp_dir/gnubg_native.o" "$tmp_dir/gnubg_native_smoke.o" "$@" \
    "$engine_dir/lib/.libs/libevent.a" "$engine_dir/lib/.libs/libsimd.a" \
    -framework AudioUnit -framework CoreServices -framework AudioToolbox \
    -framework CoreAudio $pkg_libs -lreadline -lncurses -lm \
    -o "$tmp_dir/gnubg-native-smoke"

GNUBG_NATIVE_DATA_DIR="$engine_dir" "$tmp_dir/gnubg-native-smoke"

# Internal fixtures exercise states unreachable through the current public API.
# shellcheck disable=SC2086
cc -std=gnu23 $common_flags $pkg_cflags \
    -c native/tests/gnubg_native_regression.c -o "$tmp_dir/regression.o"
# shellcheck disable=SC2086
cc "$tmp_dir/regression.o" "$@" \
    "$engine_dir/lib/.libs/libevent.a" "$engine_dir/lib/.libs/libsimd.a" \
    -framework AudioUnit -framework CoreServices -framework AudioToolbox \
    -framework CoreAudio $pkg_libs -lreadline -lncurses -lm \
    -o "$tmp_dir/gnubg-native-regression"
GNUBG_NATIVE_DATA_DIR="$engine_dir" "$tmp_dir/gnubg-native-regression"
