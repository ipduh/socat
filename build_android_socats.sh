#!/bin/bash

BUILD_ANDROID="./build_android.sh"
SDKVS="9 12 13 14 15 16 17 18 19 21 22 23 24 26"
ARCHS="arm arm64 mips mips64 x86 x86_64"

for i in $SDKVS
  do
  for j in $ARCHS
    do
    $BUILD_ANDROID $j $i 'rmbuild' 'verbose'
  done
done

find ./binaries -type f -exec shasum -a 256 {} \; |tee $0.out
