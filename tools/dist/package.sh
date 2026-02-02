#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <os> <arch>" >&2
  exit 2
fi

os="$1"
arch="$2"

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

dist_dir="$root_dir/dist"
mkdir -p "$dist_dir"

moon build --target native --release -C "$root_dir/src/main"

bin_src="$root_dir/_build/native/release/build/src/main/main.exe"
if [[ ! -f "$bin_src" ]]; then
  echo "Binary not found: $bin_src" >&2
  exit 1
fi

bin_name="moon-component"
asset_name="moon-component-${os}-${arch}.tar.gz"
cp "$bin_src" "$dist_dir/$bin_name"
chmod +x "$dist_dir/$bin_name"

tarball="$dist_dir/$asset_name"
( cd "$dist_dir" && tar -czf "$tarball" "$bin_name" )

rm -f "$dist_dir/$bin_name"

echo "Built $tarball"
