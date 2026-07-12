#!/bin/zsh
set -e

cd "$(dirname "$0")"
mkdir -p build
mkdir -p build/module-cache

swiftc \
  -target arm64-apple-macosx14.0 \
  -module-cache-path build/module-cache \
  Sources/*.swift \
  -o build/PikachuPet \
  -framework AppKit \
  -framework CoreGraphics \
  -framework Carbon
exec ./build/PikachuPet
