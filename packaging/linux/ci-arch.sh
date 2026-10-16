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
IFS=. read -r major minor patch <<< "$version"
if ((patch > 0)); then older="$major.$minor.$((patch - 1))"
elif ((minor > 0)); then older="$major.$((minor - 1)).1"
elif ((major > 0)); then older="$((major - 1)).1.1"
else exit 2
fi
cp "$project/packaging/linux/arch/PKGBUILD" /tmp/node-arch-output/PKGBUILD
runuser -u node-builder -- env F1R3NODE_BINARY="$binary" F1R3NODE_SOURCE="$project" F1R3NODE_VERSION="$older" \
  PKGDEST=/tmp/node-arch-output SRCDEST=/tmp/node-arch-output BUILDDIR=/tmp/node-arch-output \
  bash -c 'cd /tmp/node-arch-output && makepkg --nodeps --noconfirm --force'
older_package=$(find /tmp/node-arch-output -maxdepth 1 -type f -name "f1r3node-$older-1-$arch.pkg.tar.*" -print -quit)
[[ -s "$older_package" ]]
install -d -m 0700 /var/lib/f1r3node
printf 'preserve package state\n' > /var/lib/f1r3node/package-smoke-sentinel
pacman -U --noconfirm "$older_package"
[[ "$(pacman -Q f1r3node)" == "f1r3node $older-1" ]]
pacman -U --noconfirm "$package"
[[ "$(pacman -Q f1r3node)" == "f1r3node $version-1" ]]
[[ -s /var/lib/f1r3node/package-smoke-sentinel ]]
[[ "$(f1r3node --version)" == "f1r3fly $version" ]]
[[ "$(sha256sum /usr/bin/f1r3node | cut -d' ' -f1)" == "$expected_sha" ]]
pacman -R --noconfirm f1r3node
[[ ! -e /usr/bin/f1r3node ]]
[[ -s /var/lib/f1r3node/package-smoke-sentinel ]]

out=${OUT:-$project/dist}
mkdir -p "$out"
cp "$package" "$out/"
