#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
engine_dir="$repo_dir/Vendor/gnubg"

if [ ! -d "$engine_dir" ]; then
    echo "error: Vendor/gnubg is not initialized; run git submodule update --init" >&2
    exit 1
fi

cd "$engine_dir"

if [ ! -f configure ]; then
    ./autogen.sh
fi

# The checked-in parser sources are enough for an already prepared checkout.
# A clean upstream checkout needs Bison 3.x to regenerate them.
if [ ! -f sgf_y.c ] || [ ! -f external_y.c ]; then
    bison_command=${GNUBG_BISON:-bison}
    if ! command -v "$bison_command" >/dev/null 2>&1; then
        echo "error: GNU Bison 3.x is required; set GNUBG_BISON to its executable" >&2
        exit 1
    fi

    bison_version=$(
        "$bison_command" --version |
            sed -n '1s/.* \([0-9][0-9]*\)\..*/\1/p'
    )
    if [ -z "$bison_version" ] || [ "$bison_version" -lt 3 ]; then
        echo "error: GNU Bison 3.x is required to regenerate the parser sources" >&2
        echo "       detected: $bison_command" >&2
        exit 1
    fi
fi

if [ ! -f Makefile ]; then
    ./configure \
        --with-gtk=no \
        --with-board3d=no \
        --with-python=no \
        --with-sqlite=no
fi

if [ -n "${GNUBG_BUILD_JOBS:-}" ]; then
    jobs=$GNUBG_BUILD_JOBS
else
    jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)
    jobs=${jobs:-4}
fi
make -j"$jobs"

architecture=$(file -b ./gnubg)
case "$architecture" in
    *"Mach-O"*"arm64"*) ;;
    *)
        echo "error: expected an arm64 macOS executable, got: $architecture" >&2
        exit 1
        ;;
esac

./gnubg --version
