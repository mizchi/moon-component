#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

moon build --target js --release -C "$root_dir/src/main"

src_js="$root_dir/_build/js/release/build/src/main/main.js"
out_dir="$root_dir/npm/dist"
mkdir -p "$out_dir"

if [[ ! -f "$src_js" ]]; then
  echo "JS output not found: $src_js" >&2
  exit 1
fi

cp "$src_js" "$out_dir/moon-component.js"

echo "Wrote $out_dir/moon-component.js"
