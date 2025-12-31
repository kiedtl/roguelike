#!/bin/sh
#
# Download mingw packages for cross-compiling Windows releases
#

LIBPNG_URL="https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-libpng-1.6.53-1-any.pkg.tar.zst"
ZLIB_URL="https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-zlib-1.3.1-1-any.pkg.tar.zst"
SDL2_URL="https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-SDL2-2.28.4-1-any.pkg.tar.zst"
SDL2_URL="https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-SDL2-2.32.10-1-any.pkg.tar.zst"
CURL_URL="https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-curl-8.17.0-1-any.pkg.tar.zst"

[ -d src ] || {
    printf "This must be run from project root\n" >&2
    exit 1
}

[ -d third_party/mingw ] && rm -rf third_party/mingw
mkdir third_party/mingw/
cd third_party/mingw/

wget "$LIBPNG_URL" -O libpng.tar.zst
tar xf libpng.tar.zst
mv mingw64 libpng
rm libpng.tar.zst

wget "$ZLIB_URL" -O zlib.tar.zst
tar xf zlib.tar.zst
mv mingw64 zlib
rm zlib.tar.zst

wget "$SDL2_URL" -O sdl2.tar.zst
tar xf sdl2.tar.zst
mv mingw64 SDL2
rm sdl2.tar.zst

wget "$CURL_URL" -O curl.tar.zst
tar xf curl.tar.zst
mv mingw64 curl
rm curl.tar.zst
