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
    cp -r zig-out/bin/rl ${pkgname}
    cp -r data           ${pkgname}
    cp -r doc            ${pkgname}
    cp -r prefabs        ${pkgname}
    cp -r run.sh         ${pkgname}
    tar -cf - ${pkgname} | xz -qcT0 > ${pkgname}.tar.xz
    rm -rf ${pkgname}
}

printf "Compiling for host SDL...\n"
zig build -Drelease-safe -Duse-sdl=true
mktarball $(uname -s) $(uname -m) SDL

printf "Compiling for host termbox...\n"
zig build -Drelease-safe -Duse-sdl=false
mktarball $(uname -s) $(uname -m) termbox

#printf "Compiling for x86_64-macos-gnu...\n"
#zig build -Drelease-safe -Dtarget=x86_64-macos-gnu -Duse-sdl=true
#mktarball macOS x86_64 SDL

#printf "Compiling for aarch64-macos-gnu...\n"
#zig build -Drelease-safe -Dtarget=aarch64-macos-gnu -Duse-sdl=true
#mktarball macOS aarch64 SDL
