#!/usr/bin/env arch -x86_64 bash

set -e

printtag() {
    # GitHub Actions tag format
    echo "::$1::${2-}"
}

begingroup() {
    printtag "group" "$1"
}

endgroup() {
    printtag "endgroup"
}

export GITHUB_WORKSPACE=$(pwd)

# directories / files inside the downloaded tar file directory structure
export WINE_CONFIGURE=$GITHUB_WORKSPACE/sources/wine/configure
# export DXVK_BUILDSCRIPT=$GITHUB_WORKSPACE/sources/dxvk/package-release.sh
# build directories
export BUILDROOT=$GITHUB_WORKSPACE/build
# target directory for installation
export INSTALLROOT=$GITHUB_WORKSPACE/install
export PACKAGE_UPLOAD=$GITHUB_WORKSPACE/upload
# artifact names
export WINE_INSTALLATION=wine
# export DXVK_INSTALLATION=dxvk

# Need to ensure Instel brew actually exists
if ! command -v "/usr/local/bin/brew" &>/dev/null; then
    echo "</usr/local/bin/brew> could not be found"
    echo "An Intel brew installation is required"
    exit
fi

# Manually configure $PATH
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Library/Apple/usr/bin"

begingroup "Installing Dependencies"
# build dependencies
brew install \
    bison \
    gcenx/wine/cx-llvm \
    mingw-w64 \
    pkgconfig \
    coreutils

# runtime dependencies for crossover-wine
brew install \
    freetype \
    gnutls@3.7.8 \
    molten-vk \
    sdl2 \
    gettext \
    p11-kit \
    libidn-2 \
    nettle

endgroup

export CC="$(brew --prefix cx-llvm)/bin/clang"
export CXX="${CC}++"
export BISON="$(brew --prefix bison)/bin/bison"

# Xcode12 by default enables '-Werror,-Wimplicit-function-declaration' (49917738)
# this causes wine(64) builds to fail so needs to be disabled.
# https://developer.apple.com/documentation/xcode-release-notes/xcode-12-release-notes
export CFLAGS="-O3 -Wno-implicit-function-declaration -Wno-deprecated-declarations -Wno-format"
export LDFLAGS="-Wl,-rpath,@loader_path/../../"

# avoid weird linker errors with Xcode 10 and later
export MACOSX_DEPLOYMENT_TARGET=10.14

# see https://github.com/Gcenx/macOS_Wine_builds/issues/17#issuecomment-750346843
export CROSSCFLAGS="-s -O3"

export SDL2_CFLAGS="-I$(brew --prefix sdl2)/include -I$(brew --prefix sdl2)/include/SDL2"
export ac_cv_lib_soname_MoltenVK="libMoltenVK.dylib"
export ac_cv_lib_soname_vulkan=""

# if [[ ! -f "${PACKAGE_UPLOAD}/${DXVK_INSTALLATION}.tar.gz" ]]; then
#     begingroup "Applying patches to DXVK"
#     pushd sources/dxvk
#     patch -p1 <${GITHUB_WORKSPACE}/0001-build-macOS-Fix-up-for-macOS.patch
#     patch -p1 <${GITHUB_WORKSPACE}/0002-fix-d3d11-header-for-MinGW-9-1883.patch
#     patch -p1 <${GITHUB_WORKSPACE}/0003-fixes-for-mingw-gcc-12.patch
#     popd
#     endgroup

#     begingroup "Installing dependencies for DXVK"
#     brew install \
#         meson \
#         glslang
#     endgroup

#     begingroup "Build DXVK"
#     ${DXVK_BUILDSCRIPT} master ${INSTALLROOT}/${DXVK_INSTALLATION} --no-package
#     endgroup

#     begingroup "Tar DXVK"
#     pushd ${INSTALLROOT}
#     tar -czf ${DXVK_INSTALLATION}.tar.gz ${DXVK_INSTALLATION}
#     popd
#     endgroup

#     begingroup "Upload DXVK"
#     mkdir -p ${PACKAGE_UPLOAD}
#     cp ${INSTALLROOT}/${DXVK_INSTALLATION}.tar.gz ${PACKAGE_UPLOAD}/
#     endgroup
# fi

echo "#define __HACK_1__ $__HACK_1__" >> $GITHUB_WORKSPACE/sources/wine/dlls/ws2_32/ws2_32_private.h

begingroup "Configure wine64"
mkdir -p ${BUILDROOT}/wine64
pushd ${BUILDROOT}/wine64
${WINE_CONFIGURE} \
    --disable-option-checking \
    --enable-win64 \
    --disable-winedbg \
    --disable-tests \
    --without-alsa \
    --without-capi \
    --with-coreaudio \
    --with-cups \
    --without-dbus \
    --without-fontconfig \
    --with-freetype \
    --with-gettext \
    --without-gettextpo \
    --without-gphoto \
    --with-gnutls \
    --without-gssapi \
    --without-gstreamer \
    --without-inotify \
    --without-krb5 \
    --with-mingw \
    --without-netapi \
    --with-opencl \
    --with-opengl \
    --without-oss \
    --with-pcap \
    --with-pthread \
    --without-pulse \
    --without-sane \
    --with-sdl \
    --without-udev \
    --with-unwind \
    --without-usb \
    --without-v4l2 \
    --with-vulkan \
    --without-x
popd
endgroup

begingroup "Install runtime"
############ Install runtime ##############
echo Installing runtime
mkdir -p "${INSTALLROOT}/${WINE_INSTALLATION}/usr/local/lib"
# rm -rf "${INSTALLROOT}/${WINE_INSTALLATION}/usr/local/runtime"
pushd runtime
node ../analyze-deps.js ${BUILDROOT}/wine64/include/config.h
popd
cp -R runtime/ "${INSTALLROOT}/${WINE_INSTALLATION}/usr/local/lib"
endgroup

begingroup "Build wine64"
pushd ${BUILDROOT}/wine64
make -j$(sysctl -n hw.ncpu 2>/dev/null)
popd
endgroup

begingroup "Configure wine32on64"
mkdir -p ${BUILDROOT}/wine32on64
pushd ${BUILDROOT}/wine32on64
${WINE_CONFIGURE} \
    --disable-option-checking \
    --enable-win32on64 \
    --disable-winedbg \
    --with-wine64=${BUILDROOT}/wine64 \
    --disable-tests \
    --without-alsa \
    --without-capi \
    --with-coreaudio \
    --with-cups \
    --without-dbus \
    --without-fontconfig \
    --with-freetype \
    --with-gettext \
    --without-gettextpo \
    --without-gphoto \
    --with-gnutls \
    --without-gssapi \
    --without-gstreamer \
    --without-inotify \
    --without-krb5 \
    --with-mingw \
    --without-netapi \
    --with-opencl \
    --with-opengl \
    --without-oss \
    --with-pcap \
    --with-pthread \
    --without-pulse \
    --without-sane \
    --with-sdl \
    --without-udev \
    --with-unwind \
    --without-usb \
    --without-v4l2 \
    --without-x \
    --without-vulkan \
    --disable-vulkan_1 \
    --disable-winevulkan
popd
endgroup


begingroup "Build wine32on64"
pushd ${BUILDROOT}/wine32on64
make -k -j$(sysctl -n hw.activecpu 2>/dev/null)
popd
endgroup


begingroup "Install wine32on64"
pushd ${BUILDROOT}/wine32on64
make install-lib DESTDIR="${INSTALLROOT}/${WINE_INSTALLATION}"
popd
endgroup

begingroup "Install wine64"
pushd ${BUILDROOT}/wine64
make install-lib DESTDIR="${INSTALLROOT}/${WINE_INSTALLATION}"
popd
endgroup


begingroup "Tar Wine"
pushd ${INSTALLROOT}/${WINE_INSTALLATION}/usr/local
tar -czvf ${WINE_INSTALLATION}.tar.gz ./
popd
endgroup

begingroup "Upload Wine"
mkdir -p ${PACKAGE_UPLOAD}
cp ${INSTALLROOT}/${WINE_INSTALLATION}/usr/local/${WINE_INSTALLATION}.tar.gz ${PACKAGE_UPLOAD}/
endgroup
