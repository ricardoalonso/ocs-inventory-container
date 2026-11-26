#!/bin/bash
# Build the image. Tags: <version>-<release> (immutable: bump RELEASE for every
# rebuild of the same OCS version) and <version> (moves to the latest release).
# Deploy by digest, not by tag.
#
#   ./build.sh
#   test/smoketest.sh quay.io/ricardoalonsos/ocs-inventory:2.12.6-1
#   podman push quay.io/ricardoalonsos/ocs-inventory:2.12.6-1
#   podman push quay.io/ricardoalonsos/ocs-inventory:2.12.6
set -euo pipefail

VERSION=2.12.6
RELEASE=1
IMAGE=quay.io/ricardoalonsos/ocs-inventory

cd "$(dirname "$0")"
# OCS_SHA256 in the Containerfile belongs to its default OCS_VERSION: change
# both there, not here.
grep -q "^ARG OCS_VERSION=$VERSION$" Containerfile || { echo "Containerfile OCS_VERSION is not $VERSION" >&2; exit 1; }
podman build --pull=newer -t "$IMAGE:$VERSION-$RELEASE" -t "$IMAGE:$VERSION" .

echo "Built $IMAGE:$VERSION-$RELEASE (also tagged $VERSION)"
