#!/bin/bash
# ---------------------------------------------------------------------------
# Build Qt 5.9.9 for OnlyOffice — one-time build, cached for reuse.
#
# ONLYOFFICE's build_tools need a pre-built Qt 5.9.9 at:
#   tools/linux/qt_build/Qt-5.9.9/gcc_64/
#
# Their CDN download is broken (issue #916), so we build from the
# official Qt source archive instead.
#
# This script builds Qt inside Docker (same environment as the OO build)
# and caches the result at .cache/qt_build/ for reuse across builds.
#
# Usage:
#   ./build-qt.sh              # Build Qt 5.9.9 (~30 min)
# ---------------------------------------------------------------------------

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Re-running with sudo..."
  exec sudo "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="${SCRIPT_DIR}/.cache"
QT_CACHE="${CACHE_DIR}/qt_build"
QT_VERSION="5.9.9"
QT_SOURCE_URL="https://download.qt.io/new_archive/qt/5.9/${QT_VERSION}/single/qt-everywhere-opensource-src-${QT_VERSION}.tar.xz"
BUILD_DIR="${SCRIPT_DIR}/.build"

# Check if already cached
if [ -d "${QT_CACHE}/Qt-${QT_VERSION}/gcc_64/bin" ]; then
  echo "Qt ${QT_VERSION} already cached at ${QT_CACHE}"
  echo "  qmake: ${QT_CACHE}/Qt-${QT_VERSION}/gcc_64/bin/qmake"
  exit 0
fi

echo "============================================"
echo "  Building Qt ${QT_VERSION} (one-time, ~30 min)"
echo "============================================"
echo ""

# Ensure the builder Docker image exists
if ! docker image inspect onlyoffice-document-editors-builder &>/dev/null; then
  echo "Building the OO builder Docker image first..."
  if [ ! -d "${BUILD_DIR}/build_tools" ]; then
    echo "ERROR: build_tools not found. Run ./build.sh first (it will fail at Qt, but creates the Docker image)."
    exit 1
  fi
  cd "${BUILD_DIR}/build_tools"
  docker build --tag onlyoffice-document-editors-builder .
fi

mkdir -p "$QT_CACHE"

echo "[1/3] Downloading Qt ${QT_VERSION} source from official Qt archive..."
echo "  URL: ${QT_SOURCE_URL}"

# Build Qt inside Docker using the same environment as ONLYOFFICE builds
docker run --rm \
  -v "${QT_CACHE}:/qt_output" \
  onlyoffice-document-editors-builder \
  /bin/bash -c "
    set -e
    cd /tmp

    echo 'Installing build dependencies...'
    apt-get update -qq && apt-get install -yqq \
      xz-utils make g++ perl python3 pkg-config \
      libgl1-mesa-dev libglu1-mesa-dev \
      libxcb1-dev libx11-xcb-dev libxcb-glx0-dev libxcb-util0-dev \
      libxcb-icccm4-dev libxcb-image0-dev libxcb-keysyms1-dev \
      libxcb-randr0-dev libxcb-render-util0-dev libxcb-shape0-dev \
      libxcb-shm0-dev libxcb-sync-dev libxcb-xfixes0-dev libxcb-xkb-dev \
      libxkbcommon-dev libxkbcommon-x11-dev \
      libfontconfig1-dev libfreetype6-dev \
      libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
      > /dev/null 2>&1

    echo '[2/3] Downloading Qt source...'
    wget -q --show-progress -O qt_source.tar.xz '${QT_SOURCE_URL}'
    echo 'Download complete.'

    echo 'Extracting...'
    tar -xf qt_source.tar.xz
    rm qt_source.tar.xz

    cd qt-everywhere-opensource-src-${QT_VERSION}

    echo '[3/3] Configuring and building Qt (this takes ~30 min)...'
    ./configure \
      -opensource \
      -confirm-license \
      -release \
      -shared \
      -accessibility \
      -prefix /qt_output/Qt-${QT_VERSION}/gcc_64 \
      -qt-zlib \
      -qt-libpng \
      -qt-libjpeg \
      -qt-xcb \
      -qt-pcre \
      -no-sql-sqlite \
      -no-qml-debug \
      -gstreamer 1.0 \
      -nomake examples \
      -nomake tests \
      -skip qtenginio \
      -skip qtlocation \
      -skip qtserialport \
      -skip qtsensors \
      -skip qtxmlpatterns \
      -skip qt3d \
      -skip qtwebview \
      -skip qtwebengine

    make -j\$(nproc)
    make install

    echo 'Qt build complete.'
  "

# Verify
if [ -f "${QT_CACHE}/Qt-${QT_VERSION}/gcc_64/bin/qmake" ]; then
  echo ""
  echo "============================================"
  echo "  Qt ${QT_VERSION} built and cached!"
  echo "  Cache: ${QT_CACHE}"
  echo "  qmake: ${QT_CACHE}/Qt-${QT_VERSION}/gcc_64/bin/qmake"
  echo "============================================"
else
  echo "ERROR: Qt build failed — qmake not found at ${QT_CACHE}/Qt-${QT_VERSION}/gcc_64/bin/qmake"
  exit 1
fi
