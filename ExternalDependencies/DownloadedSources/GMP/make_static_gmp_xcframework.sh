#!/bin/bash

set -e

CLANG=$(xcrun --sdk iphoneos --find clang)
BITCODE_FLAGS=" -fembed-bitcode"

function realpath() {
  [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

prepare() {
  local CURRENT=`pwd`
  local GMP_VERSION="6.2.1"

  if [ ! -d "${CURRENT}/gmp" ]; then
    tar xf "${CURRENT}/gmp_releases/gmp-${GMP_VERSION}.tar.lz"
    mv -v "${CURRENT}/gmp-${GMP_VERSION}" gmp
  else
    echo "GMP already present, please clean"
    exit 1
  fi
}

build() {
  cd gmp

  build_for_macos
  build_for_ios
  build_for_simulator
}

build_for_ios() {
  echo "Building library for iOS..."

  local PREFIX=$(realpath "./lib/iphoneos")
  local ARCH='arm64'
  local TARGET='arm64-apple-darwin'
  local SDK_DEVICE_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
  local MIN_VERSION='-miphoneos-version-min=15.5'

  build_scheme $PREFIX $TARGET $ARCH $SDK_DEVICE_PATH $MIN_VERSION
}


build_for_macos() {

  echo "Building library for macOS..."

  local SDK_DEVICE_PATH=$(xcrun --sdk macosx --show-sdk-path)
  local MIN_VERSION=''

  local ARCH='arm64'
  local TARGET='x86_64-apple-ios15.5-macabi'
  local PREFIX=$(realpath "./lib/macos-arm64")
  build_scheme $PREFIX $TARGET $ARCH $SDK_DEVICE_PATH $MIN_VERSION

  local ARCH='x86_64'
  local TARGET='x86_64-apple-ios15.5-macabi'
  local PREFIX=$(realpath "./lib/macos-x86_64")
  build_scheme $PREFIX $TARGET $ARCH $SDK_DEVICE_PATH $MIN_VERSION
  #build_scheme_test $PREFIX
}


build_for_simulator() {

  echo "Building library for iOS simulator..."
  local SDK_SIMULATOR_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
  local MIN_VERSION='-miphonesimulator-version-min=15.5'

  local PREFIX=$(realpath "./lib/iphonesimulator-arm64")
  local ARCH='arm64'
  local TARGET='arm64-apple-darwin'
  build_scheme $PREFIX $TARGET $ARCH $SDK_SIMULATOR_PATH $MIN_VERSION

  local PREFIX=$(realpath "./lib/iphonesimulator-x86_64")
  local ARCH='x86_64'
  local TARGET='x86_64-apple-darwin'
  build_scheme $PREFIX $TARGET $ARCH $SDK_SIMULATOR_PATH $MIN_VERSION

}


build_scheme() {

  clean

  local PREFIX="$1"
  local TARGET="$2"
  local ARCH="$3"
  local SYS_ROOT="$4"
  local MIN_VERSION="$5"

  #local EXTRAS="--target=${TARGET} -arch ${ARCH} ${MIN_VERSION} -no-integrated-as"
  local EXTRAS="--target=${TARGET} -arch ${ARCH} ${MIN_VERSION}"
  local CFLAGS=" ${EXTRAS} ${BITCODE_FLAGS} -isysroot ${SYS_ROOT} -Wno-error -Wno-implicit-function-declaration -Wno-strict-prototypes"

  if [ ! -e "${PREFIX}" ]; then
    mkdir -p "${PREFIX}"

    ./configure \
      --prefix="${PREFIX}" \
      CC="${CLANG}" \
      CPPFLAGS="${CFLAGS}" \
      --host=arm64-apple-darwin \
      --disable-assembly --enable-static --disable-shared

    make
    make install
  fi
}

create_framework() {
  echo "Merging libraries in XCFramework..."

  local SIMULATOR_PATH="./lib/iphonesimulator"
  local MACOS_PATH="./lib/macos"

  local BUILD_PATH="./build/GMP.xcframework"

  mkdir -p $SIMULATOR_PATH/lib
  mkdir -p $MACOS_PATH/lib

  lipo -create -output ${SIMULATOR_PATH}/lib/libgmp.a \
    -arch arm64 ${SIMULATOR_PATH}-arm64/lib/libgmp.a \
    -arch x86_64 ${SIMULATOR_PATH}-x86_64/lib/libgmp.a

  lipo -create -output ${MACOS_PATH}/lib/libgmp.a \
    -arch arm64 ${MACOS_PATH}-arm64/lib/libgmp.a \
    -arch x86_64 ${MACOS_PATH}-x86_64/lib/libgmp.a

  cp ../module_map/module.modulemap ./lib/iphoneos/include/

  cp ../module_map/module.modulemap ${SIMULATOR_PATH}-arm64/include/

  cp ../module_map/module.modulemap ${MACOS_PATH}-arm64/include/

  xcodebuild -create-xcframework \
    -library ./lib/iphoneos/lib/libgmp.a \
    -headers ./lib/iphoneos/include/ \
    -library ${SIMULATOR_PATH}/lib/libgmp.a \
    -headers ${SIMULATOR_PATH}-arm64/include/ \
    -library ${MACOS_PATH}/lib/libgmp.a \
    -headers ${MACOS_PATH}-arm64/include/ \
    -output $BUILD_PATH

  echo "GMP.xcframework saved to './gmp/build' folder"

}

clean() {
  if [ -e "Makefile" ]; then
      make clean
      make distclean
  fi
}

prepare
build
create_framework
