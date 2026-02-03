#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUITE_DIR="$ROOT_DIR/tests/component-model"
CACHE_DIR="$ROOT_DIR/tests/.component-model"
UPSTREAM_REPO="https://github.com/WebAssembly/component-model.git"
UPSTREAM_REF="${COMPONENT_MODEL_TESTS_REF:-main}"

mkdir -p "$SUITE_DIR"

if [ ! -d "$CACHE_DIR/.git" ]; then
  git clone --depth 1 --branch "$UPSTREAM_REF" "$UPSTREAM_REPO" "$CACHE_DIR"
else
  git -C "$CACHE_DIR" fetch --depth 1 origin "$UPSTREAM_REF"
  git -C "$CACHE_DIR" checkout -f "$UPSTREAM_REF"
  git -C "$CACHE_DIR" reset --hard "origin/$UPSTREAM_REF"
fi

rsync -a --delete "$CACHE_DIR/test/" "$SUITE_DIR/"

REV="$(git -C "$CACHE_DIR" rev-parse --short HEAD)"
echo "Updated component-model tests to $UPSTREAM_REF ($REV)"
