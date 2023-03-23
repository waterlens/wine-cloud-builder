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
export SRCMVK=$GITHUB_WORKSPACE/moltenvk
export PACKAGE_UPLOAD=$GITHUB_WORKSPACE/upload

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
    cmake \
    python3 \
    ninja

endgroup

# avoid weird linker errors with Xcode 10 and later
export MACOSX_DEPLOYMENT_TARGET=11.0

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

# fi

pushd ${SRCMVK}

begingroup "Build MoltenVK"

./fetchDependencies --macos
make macos

endgroup


begingroup "Tar"

tar -czf MoltenVK.tar.gz ${SRCMVK}/Package/Latest/MoltenVK
mkdir -p ${PACKAGE_UPLOAD}
cp ${SRCMVK}/MoltenVK.tar.gz ${PACKAGE_UPLOAD}/

endgroup

popd

