#!/usr/bin/env bash
set -euo pipefail

(($# == 3)) || { echo "usage: $0 VERSION BINARY SHA256" >&2; exit 2; }
version=$1
binary=$2
expected_sha=$3
project=$(cd "$(dirname "$0")/../.." && pwd)

sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf
pacman -Sy --noconfirm
pacman -S --noconfirm --needed glibc gcc-libs openssl zlib brotli zstd systemd
useradd --create-home --shell /bin/bash node-builder
mkdir -p /tmp/node-arch-output
chown node-builder:node-builder /tmp/node-arch-output
runuser -u node-builder -- "$project/packaging/linux/build.sh" \
  --format arch --version "$version" --binary "$binary" --sha256 "$expected_sha" \
  --out /tmp/node-arch-output

arch=$(uname -m)
package=/tmp/node-arch-output/f1r3node-$version-1-$arch.pkg.tar.zst
[[ -s "$package" ]] || { echo "Arch package missing" >&2; exit 2; }
"$project/packaging/linux/smoke.sh" --format arch --package "$package" \
  --version "$version" --sha256 "$expected_sha"
pacman -U --noconfirm "$package"
[[ "$(f1r3node --version)" == "f1r3fly $version" ]]
[[ "$(sha256sum /usr/bin/f1r3node | cut -d' ' -f1)" == "$expected_sha" ]]
pacman -R --noconfirm f1r3node
[[ ! -e /usr/bin/f1r3node ]]

out=${OUT:-$project/dist}
mkdir -p "$out"
cp "$package" "$out/"
