#!/usr/bin/env bash
set -euo pipefail

repo="mizchi/moon-component"
version="${VERSION:-latest}"

os="$(uname -s)"
case "$os" in
  Darwin) os="macos" ;;
  Linux) os="linux" ;;
  *)
    echo "Unsupported OS: $os" >&2
    exit 1
    ;;
 esac

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) arch="x64" ;;
  arm64|aarch64) arch="arm64" ;;
  *)
    echo "Unsupported arch: $arch" >&2
    exit 1
    ;;
 esac

asset="moon-component-${os}-${arch}.tar.gz"
if [[ "$version" == "latest" ]]; then
  url="https://github.com/${repo}/releases/latest/download/${asset}"
else
  url="https://github.com/${repo}/releases/download/${version}/${asset}"
fi

prefix="${PREFIX:-$HOME/.local}"
bin_dir="$prefix/bin"
mkdir -p "$bin_dir"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

curl -fsSL "$url" -o "$tmp_dir/$asset"

tar -xzf "$tmp_dir/$asset" -C "$tmp_dir"

install -m 755 "$tmp_dir/moon-component" "$bin_dir/moon-component"

echo "Installed moon-component to $bin_dir/moon-component"
