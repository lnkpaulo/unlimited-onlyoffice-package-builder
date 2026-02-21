#!/bin/bash
# ---------------------------------------------------------------------------
# Setup lnkpaulo forks with unlimited patch commits for GitHub Actions build
# Run this once, then configure and trigger the workflow.
# ---------------------------------------------------------------------------
set -e

BUILD_DIR="$(cd "$(dirname "$0")" && pwd)/.build"
GITHUB_USER="lnkpaulo"

echo "============================================"
echo "  Setting up lnkpaulo forks for GH Actions"
echo "============================================"
echo ""

# ── 1. server repo: patch LICENSE_CONNECTIONS ──────────────────────────────
echo "[1/2] Patching lnkpaulo/server..."
cd "${BUILD_DIR}/server"

git config user.name 'Unlimited Builder'
git config user.email 'builder@localhost'

git remote add lnkpaulo "https://github.com/${GITHUB_USER}/server.git" 2>/dev/null || true

# Hard reset to v9.2.1.8 tag (clean state, discard any leftover build changes)
git checkout -f tags/v9.2.1.8
git clean -fd
git branch -D unlimited-patch 2>/dev/null || true
git checkout -b unlimited-patch

# Apply the patch (same as btactic commit 35fda010)
sed -i 's/exports\.LICENSE_CONNECTIONS = 20/exports.LICENSE_CONNECTIONS = 99999/' Common/sources/constants.js
sed -i 's/exports\.LICENSE_USERS = 3/exports.LICENSE_USERS = 99999/' Common/sources/constants.js

# Verify
echo "  Verifying patch..."
grep "LICENSE_CONNECTIONS\|LICENSE_USERS" Common/sources/constants.js

# The tag v9.2.1.8 already points to our patch commit (ebb7f5a2)
# from the previous local build run. Just ensure it's committed.
if git diff --cached --quiet && git diff --quiet; then
  echo "  (already patched, using existing commit)"
else
  git add Common/sources/constants.js
  git commit -m "License connection updated from 20 to 99999"
fi

SERVER_COMMIT=$(git rev-parse HEAD)
echo "  Server patch commit: ${SERVER_COMMIT}"

git push lnkpaulo unlimited-patch --force
echo "  Pushed to lnkpaulo/server unlimited-patch"
echo ""

# ── 2. web-apps repo: enable mobile editing ────────────────────────────────
echo "[2/2] Patching lnkpaulo/web-apps..."
cd "${BUILD_DIR}/web-apps"

git config user.name 'Unlimited Builder'
git config user.email 'builder@localhost'

git remote add lnkpaulo "https://github.com/${GITHUB_USER}/web-apps.git" 2>/dev/null || true

# Hard reset to v9.2.1.8 tag (clean state)
git checkout -f tags/v9.2.1.8
git clean -fd
git branch -D unlimited-patch 2>/dev/null || true
git checkout -b unlimited-patch

# Apply mobile editing patch (same as btactic commit 140ef6d1)
for f in \
  apps/documenteditor/mobile/src/lib/patch.jsx \
  apps/presentationeditor/mobile/src/lib/patch.jsx \
  apps/spreadsheeteditor/mobile/src/lib/patch.jsx; do
  if [ -f "$f" ]; then
    sed -i 's/return false/return true/g' "$f"
    sed -i 's/=> false/=> true/g' "$f"
    echo "  Patched: $f"
  fi
done

if git diff --cached --quiet && git diff --quiet; then
  echo "  (already patched, using existing commit)"
else
  git add \
    apps/documenteditor/mobile/src/lib/patch.jsx \
    apps/presentationeditor/mobile/src/lib/patch.jsx \
    apps/spreadsheeteditor/mobile/src/lib/patch.jsx
  git commit -m "Change isSupportEditFeature to true for document, presentation and spreadsheet mobile editors."
fi

WEBAPPS_COMMIT=$(git rev-parse HEAD)
echo "  Web-apps patch commit: ${WEBAPPS_COMMIT}"

git push lnkpaulo unlimited-patch --force
echo "  Pushed to lnkpaulo/web-apps unlimited-patch"
echo ""

# ── Summary ────────────────────────────────────────────────────────────────
echo "============================================"
echo "  Done! Patch commits created:"
echo ""
echo "  server:   ${SERVER_COMMIT}"
echo "  web-apps: ${WEBAPPS_COMMIT}"
echo ""
echo "  Next steps:"
echo "  1. Update onlyoffice-package-builder.sh with these commit SHAs"
echo "  2. Configure the GitHub Actions workflow"
echo "  3. Push a tag to trigger the build"
echo "============================================"
