#!/bin/bash
# build-qemu.sh — Cross-compile QEMU 11.0.0 for Android aarch64
#
# Uses Android NDK Clang toolchain (target: aarch64-linux-android, API 21).
# Depends on GLib >= 2.66 (provided by glib-ndk-builder artifact) and libfdt.
# All optional QEMU features are disabled to avoid missing Android/bionic APIs.
set -euo pipefail

# ============================================================
# Configuration
# ============================================================
NDK_VERSION="r28"
QEMU_VERSION="11.0.0"
GLIB_VERSION="2.82.5"
DTC_VERSION="1.7.1"

TARGET_ARCH="aarch64"
TARGET_HOST="${TARGET_ARCH}-linux-android"
TARGET_API="21"
TARGET_TRIPLE="${TARGET_HOST}${TARGET_API}"

JOBS="$(nproc)"

# Directories
ROOT_DIR="$(pwd)"
SRC_DIR="${ROOT_DIR}/src"
PREFIX="${ROOT_DIR}/prefix"
BUILD_DIR="${ROOT_DIR}/build"
OUTPUT_DIR="${ROOT_DIR}/output"

NDK_ZIP="android-ndk-${NDK_VERSION}-linux.zip"
NDK_DIR="${ROOT_DIR}/android-ndk-${NDK_VERSION}"
TOOLCHAIN="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64"

# GLib tarball source
# Priority: GLIB_TARBALL_URL (fine-grained) > construct from GLIB_PAGES_REPO > default
#   GLIB_TARBALL_URL  -- full URL override (e.g. alternate mirror or local cache)
#   GLIB_PAGES_REPO   -- GitHub "owner/repo" hosting the GLib artifact on Pages
GLIB_PAGES_REPO="${GLIB_PAGES_REPO:-zishuowang696/glib-ndk-builder}"
GLIB_PAGES_OWNER="${GLIB_PAGES_REPO%%/*}"
GLIB_PAGES_REPO_NAME="${GLIB_PAGES_REPO#*/}"
GLIB_PAGES_URL="https://${GLIB_PAGES_OWNER}.github.io/${GLIB_PAGES_REPO_NAME}/glib-${GLIB_VERSION}-${TARGET_HOST}.tar.gz"
GLIB_TARBALL_URL="${GLIB_TARBALL_URL:-${GLIB_PAGES_URL}}"

# QEMU target list -- system emulation + user-mode (64-bit + 32-bit)
QEMU_TARGET_LIST="${QEMU_TARGET_LIST:-aarch64-softmmu,aarch64-linux-user,arm-linux-user}"

# ============================================================
# Clean & prepare
# ============================================================
echo "==> Cleaning build directories..."
rm -rf "${SRC_DIR}" "${PREFIX}" "${BUILD_DIR}" "${OUTPUT_DIR}"
mkdir -p "${SRC_DIR}" "${PREFIX}" "${BUILD_DIR}" "${OUTPUT_DIR}"
mkdir -p "${PREFIX}/lib" "${PREFIX}/include"

# ============================================================
# Helper: download with resume
# ============================================================
download() {
    local url="$1"
    local dest="$2"
    if [ ! -f "${dest}" ]; then
        echo "==> Downloading ${dest}..."
        wget -q --show-progress --timeout=60 "${url}" -O "${dest}"
    else
        echo "==> ${dest} already exists, skipping download"
    fi
}

# ============================================================
# Download NDK
# ============================================================
echo ""
echo "========================================"
echo "Downloading Android NDK ${NDK_VERSION}..."
echo "========================================"
download "https://dl.google.com/android/repository/${NDK_ZIP}" "${SRC_DIR}/${NDK_ZIP}"

# ============================================================
# Download GLib tarball (from glib-ndk-builder)
# ============================================================
echo ""
echo "========================================"
echo "Downloading GLib ${GLIB_VERSION} for Android..."
echo "========================================"
echo "  URL: ${GLIB_TARBALL_URL}"

# Quick connectivity check (don't waste time downloading on error)
if ! wget -q --spider --timeout=15 "${GLIB_TARBALL_URL}" 2>/dev/null; then
    echo ""
    echo "ERROR: GLib tarball not reachable at:"
    echo "  ${GLIB_TARBALL_URL}"
    echo ""
    echo "Build it first from: https://github.com/zishuowang696/glib-ndk-builder"
    echo "Then set an override URL:"
    echo "  GLIB_TARBALL_URL=<url>   (full URL)"
    echo "  GLIB_PAGES_REPO=<owner>/<repo>  (auto-construct, default: zishuowang696/glib-ndk-builder)"
    exit 1
fi
download "${GLIB_TARBALL_URL}" "${SRC_DIR}/glib-${GLIB_VERSION}-${TARGET_HOST}.tar.gz"

# ============================================================
# Download libfdt (from dtc project)
# ============================================================
echo ""
echo "========================================"
echo "Downloading dtc ${DTC_VERSION} (libfdt)..."
echo "========================================"
download "https://git.kernel.org/pub/scm/utils/dtc/dtc.git/snapshot/dtc-${DTC_VERSION}.tar.gz" \
         "${SRC_DIR}/dtc-${DTC_VERSION}.tar.gz"

# ============================================================
# Download QEMU
# ============================================================
echo ""
echo "========================================"
echo "Downloading QEMU ${QEMU_VERSION}..."
echo "========================================"
download "https://download.qemu.org/qemu-${QEMU_VERSION}.tar.xz" \
         "${SRC_DIR}/qemu-${QEMU_VERSION}.tar.xz"

# ============================================================
# Extract NDK
# ============================================================
echo ""
echo "========================================"
echo "Extracting NDK..."
echo "========================================"
if [ ! -d "${NDK_DIR}" ]; then
    unzip -q "${SRC_DIR}/${NDK_ZIP}" -d "${ROOT_DIR}"
fi
echo "==> NDK ready at ${NDK_DIR}"

export PATH="${TOOLCHAIN}/bin:${PATH}"

# Toolchain variables
CC="${TOOLCHAIN}/bin/${TARGET_TRIPLE}-clang"
CXX="${TOOLCHAIN}/bin/${TARGET_TRIPLE}-clang++"
LD="${TOOLCHAIN}/bin/ld.lld"
AR="${TOOLCHAIN}/bin/llvm-ar"
RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
STRIP="${TOOLCHAIN}/bin/llvm-strip"
NM="${TOOLCHAIN}/bin/llvm-nm"
OBJCOPY="${TOOLCHAIN}/bin/llvm-objcopy"
READELF="${TOOLCHAIN}/bin/llvm-readelf"
AS="${TOOLCHAIN}/bin/${TARGET_TRIPLE}-clang"

# ============================================================
# Build libfdt (static library, needed by QEMU system emulation)
# ============================================================
echo ""
echo "========================================"
echo "Building libfdt ${DTC_VERSION}..."
echo "========================================"
cd "${BUILD_DIR}"
rm -rf "dtc-${DTC_VERSION}"
tar xf "${SRC_DIR}/dtc-${DTC_VERSION}.tar.gz"
cd "dtc-${DTC_VERSION}"

# Build only libfdt (skip valgrind/yaml tests, python bindings)
make CC="${CC}" AR="${AR}" NO_PYTHON=1 NO_VALGRIND=1 libfdt \
    CFLAGS="-O2 -fPIC"

# Install headers and static library
cp libfdt/fdt.h libfdt/libfdt.h "${PREFIX}/include/"
cp libfdt/libfdt.a "${PREFIX}/lib/"

# Create pkg-config file so QEMU's configure can find libfdt
cat > "${PREFIX}/lib/pkgconfig/libfdt.pc" << EOF
prefix=${PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libfdt
Description: Flat Device Tree manipulation library
Version: ${DTC_VERSION}
Libs: -L\${libdir} -lfdt
Cflags: -I\${includedir}
EOF

echo "==> libfdt built and installed to ${PREFIX}"

# ============================================================
# Extract GLib tarball into PREFIX
# ============================================================
echo ""
echo "========================================"
echo "Extracting GLib ${GLIB_VERSION}..."
echo "========================================"
cd "${ROOT_DIR}"
tar xzf "${SRC_DIR}/glib-${GLIB_VERSION}-${TARGET_HOST}.tar.gz" -C "${PREFIX}"
echo "==> GLib extracted to ${PREFIX}"

# ============================================================
# Configure QEMU
# ============================================================
echo ""
echo "========================================"
echo "Configuring QEMU ${QEMU_VERSION}..."
echo "========================================"

cd "${BUILD_DIR}"
rm -rf "qemu-${QEMU_VERSION}"
tar xf "${SRC_DIR}/qemu-${QEMU_VERSION}.tar.xz"
cd "qemu-${QEMU_VERSION}"

# Export toolchain for QEMU configure (env vars take precedence)
export CC CXX LD AR RANLIB STRIP NM OBJCOPY READELF AS
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="${PREFIX}"
export CFLAGS="-O2 -I${PREFIX}/include"
export CXXFLAGS="-O2 -I${PREFIX}/include"
export LDFLAGS="-L${PREFIX}/lib"

set -x
./configure \
    --cross-prefix="${TARGET_TRIPLE}-" \
    --host-cc="cc" \
    --target-list="${QEMU_TARGET_LIST}" \
    --prefix="" \
    --enable-pixman \
    --enable-fdt \
    --disable-werror \
    --disable-kvm \
    --disable-hvf \
    --disable-whpx \
    --disable-xen \
    --disable-gtk \
    --disable-sdl \
    --disable-opengl \
    --disable-virglrenderer \
    --disable-vnc \
    --disable-seccomp \
    --disable-linux-aio \
    --disable-linux-io-uring \
    --disable-libusb \
    --disable-usb-redir \
    --disable-spice \
    --disable-gnutls \
    --disable-docs \
    --disable-tools \
    --disable-slirp
set +x

# ============================================================
# Build QEMU
# ============================================================
echo ""
echo "========================================"
echo "Building QEMU ${QEMU_VERSION} (${JOBS} jobs)..."
echo "========================================"
make -j"${JOBS}" V=1

# ============================================================
# Install QEMU
# ============================================================
echo ""
echo "========================================"
echo "Installing QEMU..."
echo "========================================"
make install DESTDIR="${BUILD_DIR}/qemu-install"

# ============================================================
# Package QEMU into a relocatable tarball
# ============================================================
echo ""
echo "========================================"
echo "Packaging QEMU..."
echo "========================================"

INSTALL_DIR="${BUILD_DIR}/qemu-install"
OUTPUT_NAME="qemu-${QEMU_VERSION}-${TARGET_HOST}"
OUTPUT_TARBALL="${OUTPUT_DIR}/${OUTPUT_NAME}.tar.gz"

# Copy GLib shared libraries (QEMU links to them at runtime)
GLIB_LIBS_DIR="$(find "${PREFIX}" -type d -name 'glib-2.0' -path '*/lib*' -exec dirname {} \; 2>/dev/null | head -1)"
if [ -n "${GLIB_LIBS_DIR}" ]; then
    mkdir -p "${INSTALL_DIR}/lib"
    cp -v "${GLIB_LIBS_DIR}"/libglib-2.0*.so* "${INSTALL_DIR}/lib/" 2>/dev/null || true
    cp -v "${GLIB_LIBS_DIR}"/libgthread-2.0*.so* "${INSTALL_DIR}/lib/" 2>/dev/null || true
    cp -v "${GLIB_LIBS_DIR}"/libgobject-2.0*.so* "${INSTALL_DIR}/lib/" 2>/dev/null || true
    cp -v "${GLIB_LIBS_DIR}"/libgio-2.0*.so* "${INSTALL_DIR}/lib/" 2>/dev/null || true
    cp -v "${GLIB_LIBS_DIR}"/libgmodule-2.0*.so* "${INSTALL_DIR}/lib/" 2>/dev/null || true
fi

# Strip binaries (save ~30-50% size)
echo "==> Stripping binaries..."
"${STRIP}" "${INSTALL_DIR}/bin/qemu-system-aarch64" 2>/dev/null || true
"${STRIP}" "${INSTALL_DIR}/bin/qemu-aarch64" 2>/dev/null || true
"${STRIP}" "${INSTALL_DIR}/bin/qemu-arm" 2>/dev/null || true

# Create tarball
cd "${BUILD_DIR}/qemu-install"
tar czf "${OUTPUT_TARBALL}" .

echo ""
echo "========================================"
echo "Build complete!"
echo "========================================"
echo "Output: ${OUTPUT_TARBALL}"
echo ""
echo "Contents:"
tar tzf "${OUTPUT_TARBALL}" | head -40
echo "..."
tar tzf "${OUTPUT_TARBALL}" | wc -l | xargs -I{} echo "Total: {} files"
echo "Size: $(du -h "${OUTPUT_TARBALL}" | cut -f1)"
