#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUITE_DIR="$ROOT_DIR/tests/wit-parser"
CACHE_DIR="$SUITE_DIR/.wasm-tools"
UPSTREAM_REPO="https://github.com/bytecodealliance/wasm-tools.git"
UPSTREAM_REF="${WIT_TESTS_REF:-main}"

mkdir -p "$SUITE_DIR"

if [ ! -d "$CACHE_DIR/.git" ]; then
  git clone --depth 1 --branch "$UPSTREAM_REF" "$UPSTREAM_REPO" "$CACHE_DIR"
else
  git -C "$CACHE_DIR" fetch --depth 1 origin "$UPSTREAM_REF"
  git -C "$CACHE_DIR" checkout -f "$UPSTREAM_REF"
  git -C "$CACHE_DIR" reset --hard "origin/$UPSTREAM_REF"
fi

mkdir -p "$SUITE_DIR/ui"
rsync -a --delete "$CACHE_DIR/crates/wit-parser/tests/ui/" "$SUITE_DIR/ui/"

REV=$(git -C "$CACHE_DIR" rev-parse --short HEAD)
echo "Updated wit-parser tests to $UPSTREAM_REF ($REV)"
