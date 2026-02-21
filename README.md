# OnlyOffice Document Server — Unlimited Connections

Builds [OnlyOffice Document Server](https://github.com/ONLYOFFICE/DocumentServer) from **official source** with the 20-connection limit removed.

## What this does

The OnlyOffice Community Edition has a hardcoded limit of 20 concurrent connections, defined in `server/Common/sources/constants.js`:

```js
exports.LICENSE_CONNECTIONS = 20;
```

This builder compiles OnlyOffice from official source with that constant changed to `999999`, then packages it as a `.deb` and optionally a Docker image.

## Legal

This modification is permitted under [AGPL v3](https://www.gnu.org/licenses/agpl-3.0.html), as confirmed by OnlyOffice: [ONLYOFFICE/DocumentServer#3017](https://github.com/ONLYOFFICE/DocumentServer/issues/3017).

Per AGPL v3 requirements, this repository contains the build scripts and instructions to reproduce the modified software. The source code is available from the official ONLYOFFICE repositories.

## Prerequisites

- Docker with **16GB+ RAM** available
- **50GB+ free disk space**
- Git

No forks needed — the build script clones directly from the official ONLYOFFICE repositories and applies patches locally.

## Usage

### Build the .deb package

```bash
# Build latest version (~2.5 hours)
./build.sh

# Build specific version
./build.sh 9.2.1 8
```

Output: `output/onlyoffice-documentserver_<version>.deb`

### Build the Docker image

```bash
# Build .deb and Docker image in one step
./build.sh 9.2.1 8 --docker
```

### Deploy

Replace the image in your deployment script:

```bash
# In your onlyoffice.sh or docker-compose.yml
DS_IMAGE="trendaiq/onlyoffice-ds:latest"
```

## How it works

1. Clones official [ONLYOFFICE/server](https://github.com/ONLYOFFICE/server) at the release tag
2. Patches `Common/sources/constants.js` via `sed` (`LICENSE_CONNECTIONS=999999`)
3. Clones official [ONLYOFFICE/web-apps](https://github.com/ONLYOFFICE/web-apps) and enables mobile editing
4. Clones official [ONLYOFFICE/build_tools](https://github.com/ONLYOFFICE/build_tools)
5. Compiles everything inside Docker using ONLYOFFICE's official build system
6. Packages the result as a `.deb` using [btactic's deb builder](https://github.com/btactic-oo/unlimited-onlyoffice-package-builder)
7. Optionally layers the `.deb` onto the official Docker image

## Patches applied

| File | Change |
|---|---|
| `server/Common/sources/constants.js` | `LICENSE_CONNECTIONS = 20` → `999999` |
| `server/Common/sources/constants.js` | `LICENSE_USERS = 3` → `999999` |
| `web-apps/apps/*/mobile/src/lib/patch.jsx` | Enable mobile editing (`false` → `true`) |

## Credits

- [ONLYOFFICE](https://github.com/ONLYOFFICE) — the software itself
- [btactic](https://github.com/btactic-oo/unlimited-onlyoffice-package-builder) — deb packaging methodology
