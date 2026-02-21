# OnlyOffice Document Server — Unlimited Connections

Builds [OnlyOffice Document Server](https://github.com/ONLYOFFICE/DocumentServer) v9.2.1.8 from official source with the 20-connection limit removed, using GitHub Actions via [btactic's package builder](https://github.com/btactic-oo/unlimited-onlyoffice-package-builder).

## What this does

OnlyOffice Community Edition has hardcoded limits in `server/Common/sources/constants.js`:

```js
exports.LICENSE_CONNECTIONS = 20;
exports.LICENSE_USERS = 3;
```

This toolbox patches those constants to `99999`, enables mobile editing, and produces a `.deb` package via GitHub Actions — no local build environment required.

## Legal

Permitted under [AGPL v3](https://www.gnu.org/licenses/agpl-3.0.html), as confirmed by OnlyOffice in [issue #3017](https://github.com/ONLYOFFICE/DocumentServer/issues/3017). Per AGPL v3, this repository contains the full build scripts to reproduce the modified software.

---

## Architecture

The build runs entirely on **GitHub Actions** using the `lnkpaulo` forks:

| Fork | Purpose |
|---|---|
| `lnkpaulo/unlimited-onlyoffice-package-builder` | Workflow + builder script (forked from btactic) |
| `lnkpaulo/server` | OnlyOffice server with unlimited connections patch |
| `lnkpaulo/web-apps` | OnlyOffice web apps with mobile editing enabled |
| `lnkpaulo/build_tools` | Build system with Node.js 20, Qt and npm fixes |

The workflow is triggered by pushing an annotated tag matching `builds-debian-11/*` to `lnkpaulo/unlimited-onlyoffice-package-builder`. It produces a `.deb` artifact uploaded to the GitHub release.

---

## Repository contents

```
.builder/                         ← fork of lnkpaulo/unlimited-onlyoffice-package-builder
  onlyoffice-package-builder.sh   ← builder script (points to lnkpaulo forks)
  .github/workflows/
    build-release-debian-11.yml   ← GitHub Actions workflow
setup-forks.sh                    ← (one-time) patches server and web-apps forks
apply-fixes-to-forks.sh           ← (re-run when needed) patches build_tools fork
```

---

## How to use

### Prerequisites

- GitHub account `lnkpaulo` with forks of:
  - `ONLYOFFICE/server`
  - `ONLYOFFICE/web-apps`
  - `ONLYOFFICE/build_tools`
  - `btactic-oo/unlimited-onlyoffice-package-builder`
- GitHub PAT with `repo` + `workflow` scopes (classic) or Contents + Workflows (fine-grained)
- Local clones of `server` and `web-apps` at `v9.2.1.8` inside `.build/`

### Step 1 — Apply source patches (once)

Patches `LICENSE_CONNECTIONS`, `LICENSE_USERS` in `lnkpaulo/server` and enables mobile editing in `lnkpaulo/web-apps`:

```bash
./setup-forks.sh
```

After it runs, copy the printed commit SHAs into `.builder/onlyoffice-package-builder.sh`:

```bash
SERVER_CUSTOM_COMMITS="<sha from setup-forks.sh>"
WEB_APPS_CUSTOM_COMMITS="<sha from setup-forks.sh>"
```

### Step 2 — Apply build system patches (once, or after upstream changes)

Patches `lnkpaulo/build_tools` to fix the build inside GitHub Actions Docker environment:

```bash
./apply-fixes-to-forks.sh
```

This will prompt for your GitHub token interactively (never stored). It applies:

| File | Fix |
|---|---|
| `build_tools/Dockerfile` | Install Node.js 20 via NodeSource at image build time |
| `build_tools/tools/linux/deps.py` | Skip Node.js install (already in image) |
| `build_tools/tools/linux/automate.py` | Fix Qt download URL (correct filename) |
| `build_tools/scripts/build_server.py` | `npm ci` → `npm install` |
| `build_tools/scripts/build_js.py` | `npm ci` → `npm install` |
| `lnkpaulo/server` `package.json` | Remove `install:AdminPanel/*` scripts (ENOENT fix) |

### Step 3 — Push the workflow

```bash
cd .builder
git push origin main
```

### Step 4 — Trigger a build

Push an annotated tag to `lnkpaulo/unlimited-onlyoffice-package-builder`:

```bash
cd .builder
git tag -a "builds-debian-11/9.2.1.8-lnkpaulo-$(date +%Y%m%d-%H%M)" -m "trigger build"
git push origin --tags
```

The GitHub Actions workflow will start automatically. Monitor it at:
`https://github.com/lnkpaulo/unlimited-onlyoffice-package-builder/actions`

### Step 5 — Download the artifact

When the build completes, the `.deb` is attached to the GitHub release:

```
onlyoffice-documentserver_9.2.1-8-lnkpaulo_amd64.deb
```

---

## Patches applied

### Source patches (server / web-apps)

| Repo | File | Change |
|---|---|---|
| `server` | `Common/sources/constants.js` | `LICENSE_CONNECTIONS = 20` → `99999` |
| `server` | `Common/sources/constants.js` | `LICENSE_USERS = 3` → `99999` |
| `server` | `package.json` | Remove `install:AdminPanel/*` scripts |
| `web-apps` | `apps/*/mobile/src/lib/patch.jsx` | Enable mobile editing (`false` → `true`) |

### Build system patches (build_tools)

| File | Problem | Fix |
|---|---|---|
| `Dockerfile` | Node.js 10.19 in builder image too old | Install Node.js 20 via NodeSource |
| `tools/linux/deps.py` | Runtime Node.js install fails in Docker (no dbus) | Skip (already in image) |
| `tools/linux/automate.py` | Qt download URL 404 (`qt_binary_linux_amd64.7z`) | Use `qt_binary_5.9.9_gcc_64.7z` |
| `scripts/build_server.py` | `npm ci` fails with old `lockfileVersion` | Use `npm install` |
| `scripts/build_js.py` | `npm ci` fails with old `lockfileVersion` | Use `npm install` |

---

## Credits

- [ONLYOFFICE](https://github.com/ONLYOFFICE) — the software itself
- [btactic](https://github.com/btactic-oo/unlimited-onlyoffice-package-builder) — deb packaging methodology and GitHub Actions workflow
- [thomisus](https://github.com/thomisus/build_tools) — Qt filename fix discovery
