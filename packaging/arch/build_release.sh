#!/usr/bin/env bash
# Build from a clean checkout; prefer a neutral source/SDK/pub-cache directory.
set -euo pipefail
root=$(pwd -P)
revision=
if [[ $(git rev-parse --show-toplevel 2>/dev/null || true) == "$root" ]]; then revision=$(git rev-parse HEAD); fi
if [[ -n $revision ]]; then git diff --quiet HEAD --; fi
: "${FLUTTER_ROOT:?Set FLUTTER_ROOT}"
: "${PUB_CACHE:?Set an isolated PUB_CACHE}"
export RUSTFLAGS="${RUSTFLAGS:-} --remap-path-prefix=$root=/usr/src/fqapp --remap-path-prefix=$HOME=/usr/src/build-home"
export CFLAGS="${CFLAGS:-} -ffile-prefix-map=$root=/usr/src/fqapp -ffile-prefix-map=$HOME=/usr/src/build-home"
export CXXFLAGS="${CXXFLAGS:-} -ffile-prefix-map=$root=/usr/src/fqapp -ffile-prefix-map=$HOME=/usr/src/build-home"
export CARGO_NET_OFFLINE=true
flutter build linux --release --no-pub
# Provenance marker only after a successful build, never copied from old caches.
if [[ -n $revision ]]; then printf '%s\n' "$revision" > build/linux/x64/release/bundle/source-commit.txt; fi
