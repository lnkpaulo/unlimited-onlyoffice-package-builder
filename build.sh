#!/bin/bash
# ---------------------------------------------------------------------------
# OnlyOffice Document Server — Unlimited Build
#
# Builds OnlyOffice Document Server from official ONLYOFFICE source with the
# LICENSE_CONNECTIONS limit removed (changed from 20 to 999999).
#
# This is permitted under AGPL v3:
#   https://github.com/ONLYOFFICE/DocumentServer/issues/3017
#
# Requirements:
#   - Docker (with 16GB+ RAM available)
#   - ~50GB free disk space
#   - ~2.5 hours build time
#
# Usage:
#   ./build.sh                          # Build latest version (9.2.1.8)
#   ./build.sh 9.2.1 8                  # Build specific version
#   ./build.sh 9.2.1 8 --docker         # Build and create Docker image
# ---------------------------------------------------------------------------

set -e

# btactic's deb builder requires root (it manages Docker containers internally)
if [ "$EUID" -ne 0 ]; then
  echo "Re-running with sudo (build requires root for Docker)..."
  exec sudo "$0" "$@"
fi

PRODUCT_VERSION="${1:-9.2.1}"
BUILD_NUMBER="${2:-8}"
BUILD_DOCKER="${3:-}"
TAG_SUFFIX="-unlimited"
UPSTREAM_TAG="v${PRODUCT_VERSION}.${BUILD_NUMBER}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/.build"
CACHE_DIR="${SCRIPT_DIR}/.cache"
OUTPUT_DIR="${SCRIPT_DIR}/output"
QT_CACHE="${CACHE_DIR}/qt_build"
DOCKER_IMAGE="trendaiq/onlyoffice-ds"

echo "============================================"
echo "  OnlyOffice Unlimited Builder"
echo "  Version: ${PRODUCT_VERSION}.${BUILD_NUMBER}"
echo "  Tag: ${UPSTREAM_TAG}"
echo "============================================"
echo ""

# ── Step 1: Clone/update repos and apply patches ──────────────────────────

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "[1/4] Preparing ONLYOFFICE repositories and applying patches..."

# Helper: clone or reset a repo to the upstream tag
prepare_repo() {
  local repo_name="$1"
  local repo_url="$2"
  local dir="$3"

  if [ -d "$dir/.git" ]; then
    echo "  Reusing existing ${repo_name} clone (resetting to ${UPSTREAM_TAG})..."
    cd "$dir"
    git config user.name 'Unlimited Builder'
    git config user.email 'builder@localhost'
    git checkout -f master 2>/dev/null || git checkout -f main 2>/dev/null || true
    git branch -D "${UPSTREAM_TAG}-unlimited" 2>/dev/null || true
    git tag --delete "${UPSTREAM_TAG}" 2>/dev/null || true
    git fetch --all --tags
    git checkout "tags/${UPSTREAM_TAG}" -b "${UPSTREAM_TAG}-unlimited"
  else
    echo "  Cloning ${repo_url}..."
    git clone "$repo_url" "$dir"
    cd "$dir"
    git fetch --all --tags
    git checkout "tags/${UPSTREAM_TAG}" -b "${UPSTREAM_TAG}-unlimited"
    git config user.name 'Unlimited Builder'
    git config user.email 'builder@localhost'
  fi
}

# --- server repo: patch LICENSE_CONNECTIONS ---
prepare_repo "server" "https://github.com/ONLYOFFICE/server.git" "${BUILD_DIR}/server"

# Remove directories created by previous build runs (not in git, cause conflicts)
rm -rf AdminPanel node_modules

echo "  Patching constants.js (LICENSE_CONNECTIONS=999999, LICENSE_USERS=999999)..."
sed -i 's/exports\.LICENSE_CONNECTIONS\s*=\s*[0-9]*/exports.LICENSE_CONNECTIONS = 999999/' Common/sources/constants.js
sed -i 's/exports\.LICENSE_USERS\s*=\s*[0-9]*/exports.LICENSE_USERS = 999999/' Common/sources/constants.js

echo "  Patching package.json (npm ci → npm install, remove AdminPanel install scripts)..."
sed -i 's/npm ci/npm install/g' package.json
# AdminPanel is cloned and built separately by build_server.py via pkg.
# Removing these scripts prevents npm from trying to install a non-existent directory.
python3 -c "
import json
with open('package.json') as f:
    pkg = json.load(f)
scripts = pkg.get('scripts', {})
scripts.pop('install:AdminPanel/server', None)
scripts.pop('install:AdminPanel/client', None)
with open('package.json', 'w') as f:
    json.dump(pkg, f, indent=2)
print('  Removed AdminPanel install scripts from package.json')
"

echo "  Verifying patch..."
grep "LICENSE_CONNECTIONS" Common/sources/constants.js
grep "LICENSE_USERS" Common/sources/constants.js

git add -A
git commit -m "feat: remove connection limit (LICENSE_CONNECTIONS=999999)"
git tag --delete "${UPSTREAM_TAG}" 2>/dev/null || true
git tag -a "${UPSTREAM_TAG}" -m "${UPSTREAM_TAG}"

cd "$BUILD_DIR"

# --- web-apps repo: enable mobile editing ---
prepare_repo "web-apps" "https://github.com/ONLYOFFICE/web-apps.git" "${BUILD_DIR}/web-apps"

echo "  Patching mobile editors (enable edit features)..."
for patch_file in \
  apps/documenteditor/mobile/src/lib/patch.jsx \
  apps/presentationeditor/mobile/src/lib/patch.jsx \
  apps/spreadsheeteditor/mobile/src/lib/patch.jsx; do
  if [ -f "$patch_file" ]; then
    sed -i 's/return false/return true/g' "$patch_file"
    sed -i 's/=> false/=> true/g' "$patch_file"
    echo "    Patched: $patch_file"
  fi
done

git add -A
git commit -m "feat: enable mobile editing" || echo "  (no mobile patch changes needed)"
git tag --delete "${UPSTREAM_TAG}" 2>/dev/null || true
git tag -a "${UPSTREAM_TAG}" -m "${UPSTREAM_TAG}"

cd "$BUILD_DIR"

# --- build_tools repo (shallow clone, no patches needed) ---
if [ -d "build_tools/.git" ]; then
  echo "  Reusing existing build_tools clone..."
else
  echo "  Cloning ONLYOFFICE/build_tools..."
  git clone \
    --depth=1 \
    --recursive \
    --branch "${UPSTREAM_TAG}" \
    https://github.com/ONLYOFFICE/build_tools.git \
    build_tools
fi

# ── Step 2: Ensure Qt 5.9.9 is cached ──────────────────────────────────────

cd "$BUILD_DIR/build_tools"
mkdir -p out

# Build the Docker build environment image
docker build --tag onlyoffice-document-editors-builder .

if [ ! -d "${QT_CACHE}/Qt-5.9.9/gcc_64/bin" ]; then
  echo ""
  echo "[2/4] Building Qt 5.9.9 (one-time, ~30 min)..."
  echo "  ONLYOFFICE's Qt CDN is broken (issue #916), building from official Qt source."
  echo ""
  "${SCRIPT_DIR}/build-qt.sh"
else
  echo ""
  echo "[2/4] Qt 5.9.9 found in cache — skipping."
fi

# ── Step 3: Build binaries ─────────────────────────────────────────────────

echo ""
echo "[3/4] Building OnlyOffice binaries (this takes ~2 hours)..."
echo "  Source: official ONLYOFFICE repos"
echo "  Patches: LICENSE_CONNECTIONS=999999, mobile editing enabled"
echo ""

# Run the build inside Docker, mounting our patched repos and cached Qt.
# The qt_build mount makes automate.py skip Qt download/build entirely
# (it checks: if not base.is_dir("./qt_build"))
#
# We also install ninja-build inside the container because V8's depot_tools
# can no longer find its bundled ninja (ONLYOFFICE build_tools issue).
# Generate the container init script (runs before automate.py)
cat > /tmp/oo-build-init.sh <<'INIT_SCRIPT'
set -e

# ── Fix 1: Install Node.js 20 before deps.py runs ─────────────────────
# The builder image has Node.js 10.19. deps.py tries to upgrade via
# NodeSource but fails silently (sudo issues inside Docker).
# We install Node.js 20 directly, then patch deps.py to skip its
# own Node.js install (which would downgrade back to 10.19).
apt-get update -qq
apt-get install -yqq ninja-build curl ca-certificates gnupg > /dev/null 2>&1
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -yqq nodejs > /dev/null 2>&1
echo "Pre-installed Node.js: $(node -v)  npm: $(npm -v)"

# Patch deps.py: skip its Node.js install (apt-get install nodejs)
# and skip the NodeSource reinstall. We already have Node.js 20.
# Replace the nodejs install + version check block with a pass-through.
python3 -c "
import re
with open('/build_tools/tools/linux/deps.py', 'r') as f:
    content = f.read()
# Remove the nodejs apt-get install and the version check/reinstall block
# Replace from '# nodejs' to the npm install lines
content = re.sub(
    r'  # nodejs.*?base\.cmd\(\"sudo\", \[\"npm\", \"install\", \"-g\", \"@yao-pkg/pkg\"\]\)',
    '  # nodejs — already installed by init script\n'
    '  base.cmd(\"sudo\", [\"npm\", \"install\", \"-g\", \"yarn\"], True)\n'
    '  base.cmd(\"sudo\", [\"npm\", \"install\", \"-g\", \"grunt-cli\"])\n'
    '  base.cmd(\"sudo\", [\"npm\", \"install\", \"-g\", \"@yao-pkg/pkg\"])',
    content,
    flags=re.DOTALL
)
with open('/build_tools/tools/linux/deps.py', 'w') as f:
    f.write(content)
print('Patched deps.py — skipping Node.js install')
"

# ── Fix 2: Replace npm ci with npm install ──────────────────────────────
# npm ci fails with old lockfileVersion in npm-shrinkwrap.json files.
sed -i 's/\["ci"\]/["install"]/g' /build_tools/scripts/build_server.py 2>/dev/null || true
sed -i 's/\["ci"\]/["install"]/g' /build_tools/scripts/build_js.py 2>/dev/null || true

# ── Fix 3: Remove AdminPanel install scripts from server/package.json ────
# The build script (run-p install:*) tries to npm install AdminPanel/server
# and AdminPanel/client, but AdminPanel is cloned separately by build_server.py
# and doesn't exist yet at this stage — causing ENOENT errors.
python3 -c "
import json
with open('/server/package.json') as f:
    pkg = json.load(f)
scripts = pkg.get('scripts', {})
removed = []
for key in ['install:AdminPanel/server', 'install:AdminPanel/client']:
    if key in scripts:
        del scripts[key]
        removed.append(key)
with open('/server/package.json', 'w') as f:
    json.dump(pkg, f, indent=2)
print('Removed AdminPanel install scripts:', removed)
"

cd /build_tools/tools/linux
python3 ./automate.py --branch=tags/$UPSTREAM_TAG
INIT_SCRIPT

docker run \
  -e "PRODUCT_VERSION=${PRODUCT_VERSION}" \
  -e "BUILD_NUMBER=${BUILD_NUMBER}" \
  -e "UPSTREAM_TAG=${UPSTREAM_TAG}" \
  -e "NODE_ENV=production" \
  -v "$(pwd)/out:/build_tools/out" \
  -v "${BUILD_DIR}/server:/server" \
  -v "${BUILD_DIR}/web-apps:/web-apps" \
  -v "${QT_CACHE}:/build_tools/tools/linux/qt_build" \
  -v "${QT_CACHE}:/qt_output" \
  -v "/tmp/oo-build-init.sh:/tmp/oo-build-init.sh:ro" \
  onlyoffice-document-editors-builder \
  /bin/bash /tmp/oo-build-init.sh

# ── Step 3b: Build .deb package ────────────────────────────────────────────

echo ""
echo "  Building .deb package..."

# Clone btactic's deb builder (only the deb packaging part)
if [ ! -d "${BUILD_DIR}/deb_build" ]; then
  git clone https://github.com/btactic-oo/unlimited-onlyoffice-package-builder.git \
    "${BUILD_DIR}/btactic-builder"
  cp -r "${BUILD_DIR}/btactic-builder/deb_build" "${BUILD_DIR}/deb_build"
fi

cd "${BUILD_DIR}/deb_build"
docker build --tag onlyoffice-deb-builder . -f Dockerfile-manual-debian-11

docker run \
  --env "PRODUCT_VERSION=${PRODUCT_VERSION}" \
  --env "BUILD_NUMBER=${BUILD_NUMBER}" \
  --env "TAG_SUFFIX=${TAG_SUFFIX}" \
  --env "UNLIMITED_ORGANIZATION=ONLYOFFICE" \
  --env "DEBIAN_PACKAGE_SUFFIX=${TAG_SUFFIX}" \
  -v "$(pwd):/usr/local/unlimited-onlyoffice-package-builder:ro" \
  -v "$(pwd):/root:rw" \
  -v "${BUILD_DIR}/build_tools:/root/build_tools:ro" \
  onlyoffice-deb-builder \
  /bin/bash -c "/usr/local/unlimited-onlyoffice-package-builder/onlyoffice-deb-builder.sh \
    --product-version ${PRODUCT_VERSION} \
    --build-number ${BUILD_NUMBER} \
    --tag-suffix ${TAG_SUFFIX} \
    --unlimited-organization ONLYOFFICE \
    --debian-package-suffix ${TAG_SUFFIX}"

# ── Step 4: Collect output ─────────────────────────────────────────────────

echo ""
echo "[4/4] Collecting build artifacts..."

mkdir -p "$OUTPUT_DIR"

DEB_FILE=$(find "${BUILD_DIR}" -name "onlyoffice-documentserver*.deb" -type f | head -1)

if [ -z "$DEB_FILE" ]; then
  echo "ERROR: No .deb package found after build."
  echo "Check the build logs in ${BUILD_DIR}/"
  exit 1
fi

cp "$DEB_FILE" "$OUTPUT_DIR/"
DEB_NAME=$(basename "$DEB_FILE")
echo "Build artifact: ${OUTPUT_DIR}/${DEB_NAME}"

# ── Optional: Build Docker image ───────────────────────────────────────────

if [ "$BUILD_DOCKER" = "--docker" ]; then
  echo ""
  echo "Building Docker image ${DOCKER_IMAGE}:${PRODUCT_VERSION}..."

  # Copy .deb to Docker context
  cp "${OUTPUT_DIR}/${DEB_NAME}" "${SCRIPT_DIR}/docker/"

  docker build \
    --build-arg "DEB_PACKAGE=${DEB_NAME}" \
    -t "${DOCKER_IMAGE}:${PRODUCT_VERSION}" \
    -t "${DOCKER_IMAGE}:latest" \
    "${SCRIPT_DIR}/docker/"

  # Clean up
  rm -f "${SCRIPT_DIR}/docker/${DEB_NAME}"

  echo "Docker image built:"
  echo "  ${DOCKER_IMAGE}:${PRODUCT_VERSION}"
  echo "  ${DOCKER_IMAGE}:latest"
fi

echo ""
echo "============================================"
echo "  Build complete!"
echo "  .deb: ${OUTPUT_DIR}/${DEB_NAME}"
if [ "$BUILD_DOCKER" = "--docker" ]; then
  echo "  Docker: ${DOCKER_IMAGE}:${PRODUCT_VERSION}"
fi
echo "============================================"
