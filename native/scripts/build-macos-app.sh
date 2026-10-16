#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
engine_dir="$repo_dir/Vendor/gnubg"
build_dir="$repo_dir/.build/macos"
app_dir="$build_dir/GNUbg Apple.app"
mkdir -p "$build_dir" "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources/engine/met"
"$script_dir/build-engine-macos.sh"
cd "$repo_dir"
pkg_cflags=$(pkg-config --cflags glib-2.0 gthread-2.0 gobject-2.0 cairo pango pangocairo libcurl freetype2 libpng)
pkg_libs=$(pkg-config --libs glib-2.0 gthread-2.0 gobject-2.0 cairo pango pangocairo libcurl freetype2 libpng)
# shellcheck disable=SC2086
cc -std=gnu23 -DHAVE_CONFIG_H -DLOCALEDIR=\".\" \
    -I "$engine_dir" -I "$engine_dir/lib" -I "$engine_dir/pixmaps" \
    $pkg_cflags -c native/engine/gnubg_native.c -o "$build_dir/gnubg_native.o"
set -- "$build_dir/gnubg_native.o"
for object in "$engine_dir"/*.o; do
    case "$object" in
        "$engine_dir"/gnubg.o|"$engine_dir"/makebearoff.o|"$engine_dir"/makehyper.o|\
        "$engine_dir"/makeweights.o|"$engine_dir"/bearoffdump.o) ;;
        *) set -- "$@" "$object" ;;
    esac
done
# Recreate rather than retaining stale members from earlier builds.
rm -f "$build_dir/libGNUbgNative.a"
ar rcs "$build_dir/libGNUbgNative.a" "$@"
python3 native/scripts/prepare-swift-overlay.py "$build_dir"
# shellcheck disable=SC2086
swiftc -Xfrontend -warn-long-expression-type-checking -Xfrontend 500 \
    -Xfrontend -warn-long-function-bodies -Xfrontend 1000 -swift-version 5 -parse-as-library -target arm64-apple-macosx15.0 \
    -vfsoverlay "$build_dir/toolchain-overlay.json" \
    -module-cache-path "$build_dir/ModuleCacheClean" -I native/include \
    macos/Sources/*.swift "$build_dir/libGNUbgNative.a" \
    "$engine_dir/lib/.libs/libevent.a" "$engine_dir/lib/.libs/libsimd.a" \
    -framework SwiftUI -framework AppKit -framework AudioUnit -framework CoreServices \
    -framework AudioToolbox -framework CoreAudio $pkg_libs -lreadline -lncurses -lm \
    -o "$app_dir/Contents/MacOS/GNUbgApple"
cp macos/Info.plist "$app_dir/Contents/Info.plist"
cp "$engine_dir/gnubg.wd" "$engine_dir/gnubg_os0.bd" "$engine_dir/gnubg_ts0.bd" \
    "$app_dir/Contents/Resources/engine/"
cp "$engine_dir/met/Kazaross-XG2.xml" "$app_dir/Contents/Resources/engine/met/"
codesign --force --sign - "$app_dir"
echo "Built: $app_dir"
