#!/bin/sh
#
# make-dists.sh: Create some tarballs for various platforms.
#
# (c) Kiëd Llaentenn <kiedtl@tilde.team>
# See the COPYING file for copyright information.

VERSION=$(cat RELEASE)

set -e

[ -d src ] || {
    printf "error: must be run from root source directory\n" >&2
    exit 1
}

mktarball() {
    pkgname="oathbreaker-${1}-${2}-${3}-${VERSION}"
    [ -d ${pkgname} ] && rm -rf ${pkgname}
    mkdir ${pkgname}

    cp -r data           ${pkgname}
    #cp -r doc            ${pkgname}

    if [ ${1} = "windows" ]; then
        cp -r zig-out/bin/rl.exe ${pkgname}
        cp -r zig-out/bin/rl.pdb ${pkgname}
        cp -r zig-out/bin/libpng16-16.dll ${pkgname}
        cp -r zig-out/bin/SDL2.dll ${pkgname}
        cp -r zig-out/bin/zlib1.dll ${pkgname}
    else
        cp -r run.sh         ${pkgname}
        cp -r zig-out/bin/rl ${pkgname}
    fi

    if [ ${1} = "windows" ]; then
        zip -qr ${pkgname}.zip ${pkgname}
    else
        tar -cf - ${pkgname} | xz -qcT0 > ${pkgname}.tar.xz
    fi

    rm -rf ${pkgname}
}

printf "Compiling for x86_64 Linux SDL...\n"
zig build -Doptimize=ReleaseSafe -Dcpu=baseline -Duse-sdl=true
mktarball linux x86_64 SDL

# oathbreaker-termbox crashes with illegal instruction if build with
# release-safe, so build in debug mode.

# printf "Compiling for x86_64 Linux termbox...\n"
# zig build -Doptimize=Debug      -Dtarget=x86_64-linux-gnu   -Duse-sdl=false
# mktarball linux x86_64 termbox

printf "Compiling for x86_64 Windows SDL...\n"
zig build -Doptimize=ReleaseSafe -Dcpu=baseline -Duse-sdl=true -Dtarget=x86_64-windows-gnu
mktarball windows x86_64 SDL
