#!/bin/bash
# Oliver Epper <oliver.epper@gmail.com>

set -e
env -i

if [ $# -eq 0 ]
then
    echo "sh ./start.sh <absolute path>"
    exit 1
fi

PREFIX=$1
PJPROJECT_VERSION=2.13
IOS_ARM64_INSTALL_PREFIX="${PREFIX}/ios-arm64"
IOS_ARM64_SIMULATOR_INSTALL_PREFIX="${PREFIX}/ios-arm64-simulator"
IOS_X86_64_SIMULATOR_INSTALL_PREFIX="${PREFIX}/ios-x86_64-simulator"
IOS_ARM64_X86_64_SIMULATOR_INSTALL_PREFIX="${PREFIX}/ios-arm64_x86_64-simulator"

MACOS_ARM64_INSTALL_PREFIX="${PREFIX}/macos-arm64"
MACOS_X86_64_INSTALL_PREFIX="${PREFIX}/macos-x86_64"
MACOS_ARM64_X86_64_INSTALL_PREFIX="${PREFIX}/macos-arm64_x86_64"
 
UPDATEPATCH="TRUE"

if [ -d pjproject ]
then
    pushd pjproject
    git reset --hard "${PJPROJECT_VERSION}"
    popd
else
    git -c advice.detachedHead=false clone --depth 1 --branch "${PJPROJECT_VERSION}" https://github.com/pjsip/pjproject # > /dev/null 2>&1
fi

#
# helper function
#
function createLib {
    pushd "$1"
    EXTRA_LIBS=()
    if [ -d "${OPUS_LATEST}" ]; then
        EXTRA_LIBS+=("${OPUS_LATEST}/lib/libopus.a")
        unset OPUS
        unset OPUS_LATEST
    fi
    if [[ -d "${SDL_LATEST}" ]]; then
        EXTRA_LIBS+=("${SDL_LATEST}/lib/libSDL2.a")
        unset SDL
        unset SDL_LATEST
    fi
    libtool -static -o libpjproject.a ./*.a "${EXTRA_LIBS[@]}"
    ranlib libpjproject.a
    popd
}

#
# create base configuration for pjproject build
#
pushd pjproject
cat << EOF > pjlib/include/pj/config_site.h
#define PJ_HAS_SSL_SOCK 1
#undef PJ_SSL_SOCK_IMP
#define PJ_SSL_SOCK_IMP PJ_SSL_SOCK_IMP_APPLE
#define PJSIP_MAX_TSX_COUNT		((64*1024)-1)
#define PJSIP_MAX_TSX_COUNT		((64*1024)-1)
#define PJSIP_MAX_DIALOG_COUNT	((64*1024)-1)
#define PJSIP_UDP_SO_SNDBUF_SIZE	(512*1024)
#define PJSIP_UDP_SO_RCVBUF_SIZE	(512*1024)
#include <pj/config_site_sample.h>
EOF
popd

function prepare {
    local WANTS_IPHONE=$1
    local WANTS_VIDEO=$2

    git reset --hard
    git clean -fxd

    cat << EOF > pjlib/include/pj/config_site.h
#define PJ_HAS_SSL_SOCK 1
#undef PJ_SSL_SOCK_IMP
#define PJ_SSL_SOCK_IMP PJ_SSL_SOCK_IMP_APPLE
#define PJSIP_MAX_TSX_COUNT		((64*1024)-1)
#define PJSIP_MAX_TSX_COUNT		((64*1024)-1)
#define PJSIP_MAX_DIALOG_COUNT	((64*1024)-1)
#define PJSIP_UDP_SO_SNDBUF_SIZE	(512*1024)
#define PJSIP_UDP_SO_RCVBUF_SIZE	(512*1024)
#include <pj/config_site_sample.h>
EOF

    if [[ "${WANTS_IPHONE}" = "YES" ]]; then
        echo "🔧 adding iPhone support"
        sed -i '' -e '1i\
#define PJ_CONFIG_IPHONE 1
' pjlib/include/pj/config_site.h
    fi

    if [[ "${WANTS_VIDEO}" = "YES" ]]; then
        echo "🔧 adding video support"
        sed -i '' -e '1i\
#define PJMEDIA_HAS_VIDEO 1 \
#define PJMEDIA_HAS_VID_TOOLBOX_CODEC 1
' pjlib/include/pj/config_site.h
    fi
}

### 增加3pcc等逻辑 以及sip dtmf 第三种方式
if [ "$UPDATEPATCH" = "TRUE" ]; then
    git am --show-current-patch=diff ./patch/0001-.patch
    git am --show-current-patch=diff ./patch/0002-update.patch
    git am --show-current-patch=diff ./patch/0003-3pcc-dtmf.patch
    git am --show-current-patch=diff ./patch/0004-SBC.patch
fi


#
# build for iOS on arm64
#
rm -rf "${IOS_ARM64_INSTALL_PREFIX}"
pushd pjproject
prepare YES YES

OPUS=(/opt/homebrew/Cellar/opus-apple-platforms/*/ios-arm64)
OPUS_LATEST=${OPUS[${#OPUS[@]} - 1]}
if [[ -d "${OPUS_LATEST}" ]]
then
    CONFIGURE_EXTRA_PARAMS+=("--with-opus=${OPUS_LATEST}")
fi

SDKPATH=$(xcrun -sdk iphoneos --show-sdk-path)
ARCH="arm64"
CFLAGS="-isysroot $SDKPATH -miphoneos-version-min=13 -DPJ_SDK_NAME=\"\\\"$(basename "$SDKPATH")\\\"\" -arch $ARCH" \
LDFLAGS="-isysroot $SDKPATH -framework AudioToolbox -framework Foundation -framework Network -framework Security -arch $ARCH" \
./aconfigure --prefix="${IOS_ARM64_INSTALL_PREFIX}" --host="${ARCH}"-apple-darwin_ios "${CONFIGURE_EXTRA_PARAMS[@]}" --disable-sdl

make dep && make clean
make
make install

createLib "${IOS_ARM64_INSTALL_PREFIX}/lib"
popd


#
# build for iOS simulator on arm64
#
rm -rf "${IOS_ARM64_SIMULATOR_INSTALL_PREFIX}"
pushd pjproject
prepare YES YES

OPUS=(/opt/homebrew/Cellar/opus-apple-platforms/*/ios-arm64-simulator)
OPUS_LATEST=${OPUS[${#OPUS[@]} - 1]}
if [[ -d "${OPUS_LATEST}" ]]
then
    CONFIGURE_EXTRA_PARAMS+=("--with-opus=${OPUS_LATEST}")
fi

SDKPATH=$(xcrun -sdk iphonesimulator --show-sdk-path)
ARCH="arm64"
CFLAGS="-isysroot $SDKPATH -miphonesimulator-version-min=13 -DPJ_SDK_NAME=\"\\\"$(basename "$SDKPATH")\\\"\" -arch $ARCH" \
LDFLAGS="-isysroot $SDKPATH -framework AudioToolbox -framework Foundation -framework Network -framework Security -arch $ARCH" \
./aconfigure --prefix="${IOS_ARM64_SIMULATOR_INSTALL_PREFIX}" --host="${ARCH}"-apple-darwin_ios "${CONFIGURE_EXTRA_PARAMS[@]}" --disable-sdl

make dep && make clean
make
make install

createLib "${IOS_ARM64_SIMULATOR_INSTALL_PREFIX}/lib"
popd


#
# build for iOS simulator on x86_64
#
rm -rf "${IOS_X86_64_SIMULATOR_INSTALL_PREFIX}"
pushd pjproject
prepare YES YES

OPUS=(/opt/homebrew/Cellar/opus-apple-platforms/*/ios-x86_64-simulator)
OPUS_LATEST=${OPUS[${#OPUS[@]} - 1]}
if [[ -d "${OPUS_LATEST}" ]]
then
    CONFIGURE_EXTRA_PARAMS+=("--with-opus=${OPUS_LATEST}")
fi

SDKPATH=$(xcrun -sdk iphonesimulator --show-sdk-path)
ARCH="x86_64"
CFLAGS="-isysroot $SDKPATH -miphonesimulator-version-min=13 -DPJ_SDK_NAME=\"\\\"$(basename "$SDKPATH")\\\"\" -arch $ARCH" \
LDFLAGS="-isysroot $SDKPATH -framework AudioToolbox -framework Foundation -framework Network -framework Security -arch $ARCH" \
./aconfigure --prefix="${IOS_X86_64_SIMULATOR_INSTALL_PREFIX}" --host="${ARCH}"-apple-darwin_ios "${CONFIGURE_EXTRA_PARAMS[@]}" --disable-sdl

make dep && make clean
make
make install

createLib "${IOS_X86_64_SIMULATOR_INSTALL_PREFIX}/lib"
popd


#
# build fat lib for simulator
#
mkdir -p "${IOS_ARM64_X86_64_SIMULATOR_INSTALL_PREFIX}/lib"
lipo -create \
    "${IOS_ARM64_SIMULATOR_INSTALL_PREFIX}/lib/libpjproject.a" \
    "${IOS_X86_64_SIMULATOR_INSTALL_PREFIX}/lib/libpjproject.a" \
    -output \
    "${IOS_ARM64_X86_64_SIMULATOR_INSTALL_PREFIX}/lib/libpjproject.a"

 

#
# build SDL for the mac
#
THIRD_PARTY="$(pwd)/third_party_bin"
sh ./sdl.sh ${THIRD_PARTY}
#

#
# build for macOS on arm64
#
rm -rf "${MACOS_ARM64_INSTALL_PREFIX}"
pushd pjproject
prepare NO YES

OPUS=(/opt/homebrew/Cellar/opus-apple-platforms/*/macos-arm64)
OPUS_LATEST=${OPUS[${#OPUS[@]} - 1]}
if [[ -d "${OPUS_LATEST}" ]]
then
    CONFIGURE_EXTRA_PARAMS+=("--with-opus=${OPUS_LATEST}")
fi

SDL=("${THIRD_PARTY}/macos-arm64")
SDL_LATEST=${SDL[${#SDL[@]} - 1]}
if [[ -d "${SDL_LATEST}" ]]; then
    CONFIGURE_EXTRA_PARAMS+=("--with-sdl=${SDL_LATEST}")
fi

SDKPATH=$(xcrun -sdk macosx --show-sdk-path)
ARCH="arm"
CFLAGS="-isysroot $SDKPATH -mmacosx-version-min=11 -DPJ_SDK_NAME=\"\\\"$(basename "$SDKPATH")\\\"\"" \
LDFLAGS="-isysroot $SDKPATH -framework AudioToolbox -framework Foundation -framework Network -framework Security" \
./aconfigure --prefix="${MACOS_ARM64_INSTALL_PREFIX}" --host="${ARCH}"-apple-darwin "${CONFIGURE_EXTRA_PARAMS[@]}"

make dep && make clean
make
make install

createLib "${MACOS_ARM64_INSTALL_PREFIX}/lib"
popd


#
# build for macOS on x86_64
#
rm -rf "${MACOS_X86_64_INSTALL_PREFIX}"
pushd pjproject
prepare NO YES

OPUS=(/opt/homebrew/Cellar/opus-apple-platforms/*/macos-x86_64)
OPUS_LATEST=${OPUS[${#OPUS[@]} - 1]}
if [[ -d "${OPUS_LATEST}" ]]
then
    CONFIGURE_EXTRA_PARAMS+=("--with-opus=${OPUS_LATEST}")
fi

SDL=("${THIRD_PARTY}/macos-x86_64")
SDL_LATEST=${SDL[${#SDL[@]} - 1]}
if [[ -d "${SDL_LATEST}" ]]; then
    CONFIGURE_EXTRA_PARAMS+=("--with-sdl=${SDL_LATEST}")
fi

SDKPATH=$(xcrun -sdk macosx --show-sdk-path)
ARCH="x86_64"
CFLAGS="-isysroot $SDKPATH -mmacosx-version-min=11 -DPJ_SDK_NAME=\"\\\"$(basename "$SDKPATH")\\\"\" -arch ${ARCH}" \
LDFLAGS="-isysroot $SDKPATH -framework AudioToolbox -framework Foundation -framework Network -framework Security -arch ${ARCH}" \
./aconfigure --prefix="${MACOS_X86_64_INSTALL_PREFIX}" --host="${ARCH}"-apple-darwin "${CONFIGURE_EXTRA_PARAMS[@]}"

make dep && make clean
arch -arch x86_64 make
make install

createLib "${MACOS_X86_64_INSTALL_PREFIX}/lib"
popd
 
#
# build fat lib for macos
#
mkdir -p "${MACOS_ARM64_X86_64_INSTALL_PREFIX}/lib"
lipo -create \
    "${MACOS_ARM64_INSTALL_PREFIX}/lib/libpjproject.a" \
    "${MACOS_X86_64_INSTALL_PREFIX}/lib/libpjproject.a" \
    -output \
    "${MACOS_ARM64_X86_64_INSTALL_PREFIX}/lib/libpjproject.a"

 
#
# create xcframework
#
mkdir -p "$PREFIX"/lib
XCFRAMEWORK="$PREFIX/lib/libpjproject.xcframework"
rm -rf "$XCFRAMEWORK"
xcodebuild -create-xcframework \
-library "${IOS_ARM64_INSTALL_PREFIX}/lib/libpjproject.a" \
-headers "${IOS_ARM64_INSTALL_PREFIX}/include" \
-library "${IOS_ARM64_X86_64_SIMULATOR_INSTALL_PREFIX}/lib/libpjproject.a" \
-headers "${IOS_ARM64_SIMULATOR_INSTALL_PREFIX}/include" \
-library "${MACOS_ARM64_X86_64_INSTALL_PREFIX}/lib/libpjproject.a" \
-headers "${MACOS_ARM64_INSTALL_PREFIX}/include" \
-output "${XCFRAMEWORK}"

#
# install the system version
#
cp -a "${PREFIX}/macOS-$(arch)/include" "${PREFIX}"
cp -a "${PREFIX}/macOS-$(arch)/lib" "${PREFIX}"

#
# create a sane pkg-config
#
PCFILE="${PREFIX}/lib/pkgconfig/libpjproject.pc"
cat << 'EOF' > "${PCFILE}"
Name: libpjproject
Description: Multimedia communication library
URL: http://www.pjsip.org
EOF

cat << EOF >> "${PCFILE}"
Version: ${PJPROJECT_VERSION}

Libs: -L/opt/homebrew/lib -lpjproject -framework Carbon -framework AppKit -framework Security -framework Network -framework AVFoundation -framework CoreMedia -framework CoreAudio -framework CoreVideo -framework AudioToolbox -framework VideoToolbox -framework Metal -framework IOKit
Cflags: -I/opt/homebrew/include -DPJ_AUTOCONF=1  -DPJ_IS_BIG_ENDIAN=0 -DPJ_IS_LITTLE_ENDIAN=1
EOF

#
# clean-up for now
#
rm -rf "${IOS_ARM64_X86_64_SIMULATOR_INSTALL_PREFIX}"
rm -rf "${MACOS_ARM64_X86_64_INSTALL_PREFIX}"
pushd "${PREFIX}"
find . -not -path "./lib/*" -type d -name pkgconfig | xargs rm -rf
popd
