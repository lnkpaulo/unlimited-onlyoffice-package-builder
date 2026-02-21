#!/bin/bash
# ---------------------------------------------------------------------------
# Apply all build fixes to lnkpaulo forks so GitHub Actions can build v9.2.1.8
#
# Fixes applied:
#   server/package.json      — remove install:AdminPanel/* scripts (ENOENT fix)
#   build_tools/deps.py      — install Node.js 20 (not broken v16 NodeSource URL)
#   build_tools/build_server.py — npm ci → npm install
#   build_tools/build_js.py  — npm ci → npm install
#
# Run as: sudo ./apply-fixes-to-forks.sh
# ---------------------------------------------------------------------------
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Re-running with sudo..."
  exec sudo "$0" "$@"
fi

GITHUB_USER="lnkpaulo"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
BUILD_DIR="$(cd "$(dirname "$0")" && pwd)/.build"

if [ -z "$GITHUB_TOKEN" ]; then
  read -rsp "GitHub token (PAT with repo+workflow scope): " GITHUB_TOKEN
  echo ""
fi

if [ -z "$GITHUB_TOKEN" ]; then
  echo "ERROR: no token provided, aborting."
  exit 1
fi

REMOTE_URL_SERVER="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/server.git"
REMOTE_URL_BUILD_TOOLS="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/build_tools.git"

echo "============================================"
echo "  Applying build fixes to lnkpaulo forks"
echo "============================================"
echo ""

# ── 1. server repo: amend patch commit to also fix AdminPanel ──────────────
echo "[1/2] Patching lnkpaulo/server (add AdminPanel fix to existing commit)..."
cd "${BUILD_DIR}/server"

git config user.name 'Unlimited Builder'
git config user.email 'builder@localhost'

# Ensure we are on the unlimited-patch branch at the right commit
git checkout unlimited-patch 2>/dev/null || true

python3 - <<'PYEOF'
import json
with open("package.json") as f:
    pkg = json.load(f)
scripts = pkg.get("scripts", {})
removed = []
for key in ["install:AdminPanel/server", "install:AdminPanel/client"]:
    if key in scripts:
        del scripts[key]
        removed.append(key)
with open("package.json", "w") as f:
    json.dump(pkg, f, indent=2)
if removed:
    print("  Removed AdminPanel scripts:", removed)
else:
    print("  (AdminPanel scripts already removed)")
PYEOF

if git diff --quiet package.json; then
  echo "  (no change needed in package.json)"
else
  git add package.json
  git commit --amend --no-edit
fi

SERVER_COMMIT=$(git rev-parse HEAD)
echo "  Server commit: ${SERVER_COMMIT}"

git remote set-url lnkpaulo "${REMOTE_URL_SERVER}" 2>/dev/null || \
  git remote add lnkpaulo "${REMOTE_URL_SERVER}"
git push lnkpaulo unlimited-patch --force
echo "  Pushed lnkpaulo/server"
echo ""

# ── 2. build_tools repo: create patch commit with all build fixes ──────────
echo "[2/2] Patching lnkpaulo/build_tools..."
cd "${BUILD_DIR}"

if [ ! -d "build_tools/.git" ]; then
  echo "  Cloning ONLYOFFICE/build_tools v9.2.1.8..."
  git clone \
    --depth=1 \
    --recursive \
    --branch v9.2.1.8 \
    https://github.com/ONLYOFFICE/build_tools.git \
    build_tools
fi

cd build_tools
git config user.name 'Unlimited Builder'
git config user.email 'builder@localhost'

git remote add lnkpaulo "${REMOTE_URL_BUILD_TOOLS}" 2>/dev/null || \
  git remote set-url lnkpaulo "${REMOTE_URL_BUILD_TOOLS}"
git fetch origin --tags --force
git fetch lnkpaulo --tags --force 2>/dev/null || true

# Reset to clean v9.2.1.8 state from upstream
git checkout -f tags/v9.2.1.8 2>/dev/null || true
git clean -fd
git branch -D v9.2.1.8-unlimited 2>/dev/null || true
git checkout -b v9.2.1.8-unlimited

# ── Fix 1: Dockerfile — install Node.js 20 at image build time ─────────────
# deps.py tries to install Node.js at runtime but fails inside Docker
# (no dbus, sudo -E bash pipe fails silently). Bake Node.js 20 into the image.
echo "  Patching Dockerfile (install Node.js 20 at build time)..."
cat > /tmp/dockerfile-nodejs.patch <<'PATCH'
RUN apt-get -y update && \
    apt-get -y install curl ca-certificates gnupg && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get -y install nodejs && \
    npm install -g yarn grunt-cli @yao-pkg/pkg && \
    node -v && npm -v

PATCH

# Insert the Node.js install block just before ADD . /build_tools
python3 - <<'PYEOF'
with open("Dockerfile") as f:
    content = f.read()
nodejs_block = (
    "RUN apt-get -y update && \\\n"
    "    apt-get -y install curl ca-certificates gnupg ninja-build && \\\n"
    "    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \\\n"
    "    apt-get -y install nodejs && \\\n"
    "    npm install -g yarn grunt-cli @yao-pkg/pkg && \\\n"
    "    node -v && npm -v\n\n"
)
if "nodesource" not in content:
    content = content.replace("ADD . /build_tools", nodejs_block + "ADD . /build_tools")
    with open("Dockerfile", "w") as f:
        f.write(content)
    print("  Dockerfile patched with Node.js 20 install")
else:
    print("  (Dockerfile already has Node.js install)")
PYEOF

# ── Fix 2: deps.py — skip Node.js install (already done in Dockerfile) ──────
echo "  Patching tools/linux/deps.py (skip Node.js install)..."
python3 - <<'PYEOF'
import re
with open("tools/linux/deps.py") as f:
    content = f.read()
# Replace the entire nodejs block with a no-op comment
patched = re.sub(
    r'  # nodejs\n.*?base\.cmd\("sudo", \["npm", "install", "-g", "@yao-pkg/pkg"\]\)',
    '  # nodejs — already installed in Docker image (Node.js 20)\n'
    '  pass  # skip: node, yarn, grunt-cli, pkg already installed',
    content,
    flags=re.DOTALL
)
if patched != content:
    with open("tools/linux/deps.py", "w") as f:
        f.write(patched)
    print("  deps.py patched (nodejs block skipped)")
else:
    print("  (deps.py nodejs block already patched or pattern not found)")
PYEOF

# ── Fix 3: automate.py — use correct Qt filename (qt_binary_5.9.9_gcc_64.7z) ─
# The original automate.py downloads qt_binary_linux_amd64.7z which is 404.
# thomisus uses qt_binary_5.9.9_gcc_64.7z which exists in ONLYOFFICE-data LFS.
echo "  Patching tools/linux/automate.py (correct Qt filename)..."
python3 - <<'PYEOF'
with open("tools/linux/automate.py") as f:
    content = f.read()

# Replace install_qt_prebuild() with inline fetch using correct filename
old_func = '''def install_qt_prebuild():
  url_amd64 = "https://github.com/ONLYOFFICE-data/build_tools_data/raw/refs/heads/master/qt/qt_binary_linux_amd64.7z"
  base.download(url_amd64, "./qt_amd64.7z")
  base.extract("./qt_amd64.7z", "./qt_build")
  base.create_dir("./qt_build/Qt-5.9.9")
  base.cmd("mv", ["./qt_build/qt_amd64", "./qt_build/Qt-5.9.9/gcc_64"])
  base.setup_local_qmake("./qt_build/Qt-5.9.9/gcc_64/bin")
  return'''

new_func = '''def install_qt_prebuild():
  # Use correct filename (qt_binary_linux_amd64.7z is 404, fixed name works)
  url_amd64 = "https://github.com/ONLYOFFICE-data/build_tools_data/raw/refs/heads/master/qt/qt_binary_5.9.9_gcc_64.7z"
  if not base.is_dir("./qt_build/Qt-5.9.9"):
    base.create_dir("./qt_build/Qt-5.9.9")
  base.download(url_amd64, "./qt_build/Qt-5.9.9/qt_binary_5.9.9_gcc_64.7z")
  base.extract("./qt_build/Qt-5.9.9/qt_binary_5.9.9_gcc_64.7z", "./qt_build/Qt-5.9.9")
  base.setup_local_qmake("./qt_build/Qt-5.9.9/gcc_64/bin")
  return'''

if old_func in content:
    content = content.replace(old_func, new_func)
    with open("tools/linux/automate.py", "w") as f:
        f.write(content)
    print("  automate.py patched (correct Qt filename)")
else:
    print("  WARNING: could not find install_qt_prebuild() — already patched or pattern changed")
PYEOF

# ── Fix 4: build_server.py — npm ci → npm install ───────────────────────────
echo "  Patching scripts/build_server.py (npm ci → npm install)..."
sed -i 's/"npm", \["ci"\]/"npm", ["install"]/g' scripts/build_server.py

# ── Fix 4: build_js.py — npm ci → npm install ───────────────────────────────
echo "  Patching scripts/build_js.py (npm ci → npm install)..."
sed -i 's/return base\.cmd_in_dir(directory, "npm", \["ci"\])/return base.cmd_in_dir(directory, "npm", ["install"])/g' scripts/build_js.py
sed -i 's/base\.cmd("npm", \["ci"\])/base.cmd("npm", ["install"])/g' scripts/build_js.py

git add Dockerfile tools/linux/deps.py tools/linux/automate.py scripts/build_server.py scripts/build_js.py

if git diff --cached --quiet; then
  echo "  (no changes needed in build_tools)"
else
  git commit -m "fix: Node.js 20, correct Qt filename, npm ci to npm install

- Dockerfile: install Node.js 20 + yarn/grunt-cli/pkg at image build time
- deps.py: skip nodejs block (already installed in image)
- automate.py: fix Qt download URL (qt_binary_linux_amd64.7z is 404,
  use qt_binary_5.9.9_gcc_64.7z which exists in ONLYOFFICE-data LFS)
- build_server.py: npm ci -> npm install (old lockfileVersion)
- build_js.py: npm ci -> npm install"
fi

# Tag so btactic builder can clone it at the right ref
git tag --delete "v9.2.1.8" 2>/dev/null || true
git tag -a "v9.2.1.8" -m "v9.2.1.8"

BUILD_TOOLS_COMMIT=$(git rev-parse HEAD)
echo "  build_tools commit: ${BUILD_TOOLS_COMMIT}"

git push lnkpaulo v9.2.1.8-unlimited --force
git push lnkpaulo "v9.2.1.8" --force
echo "  Pushed lnkpaulo/build_tools"
echo ""

# ── Summary ─────────────────────────────────────────────────────────────────
echo "============================================"
echo "  Done!"
echo ""
echo "  server commit:      ${SERVER_COMMIT}"
echo "  build_tools commit: ${BUILD_TOOLS_COMMIT}"
echo ""
echo "  Next: update onlyoffice-package-builder.sh with these SHAs"
echo "  and push a new trigger tag."
echo "============================================"
