# ---------------------------------------------------------------------------
# OnlyOffice Document Server — Unlimited Connections
#
# This Dockerfile replicates the official ONLYOFFICE/Docker-DocumentServer
# build process, but installs a custom .deb package built from source with
# LICENSE_CONNECTIONS increased from 20 to 999999.
#
# The .deb is built by ./build.sh using btactic's builder on top of
# official ONLYOFFICE source repositories (AGPL v3).
#
# Usage:
#   # After running ./build.sh to produce the .deb:
#   cp output/onlyoffice-documentserver_*.deb docker/
#   docker build --build-arg DEB_PACKAGE=<filename>.deb -t trendaiq/onlyoffice-ds .
#
# Or simply:
#   ./build.sh 9.2.1 1 --docker
# ---------------------------------------------------------------------------

# Stage 1: Start from the official image (has all runtime deps and entrypoint)
FROM onlyoffice/documentserver:latest

ARG DEB_PACKAGE

# Replace the official documentserver package with our unlimited build
COPY ${DEB_PACKAGE} /tmp/onlyoffice-ds.deb

RUN apt-get -y update && \
    # Remove the official package
    dpkg -r onlyoffice-documentserver || true && \
    # Install our unlimited build
    apt-get -yq install /tmp/onlyoffice-ds.deb && \
    # Clean up
    rm -f /tmp/onlyoffice-ds.deb && \
    rm -rf /var/lib/apt/lists/*
