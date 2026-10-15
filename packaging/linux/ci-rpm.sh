#!/usr/bin/env bash
set -euo pipefail

(($# == 3)) || { echo "usage: $0 VERSION BINARY SHA256" >&2; exit 2; }
version=$1
binary=$2
expected_sha=$3

dnf -y install rpm-build rpm cpio binutils
out=${OUT:-$(pwd)/dist}
mkdir -p "$out"

packaging/linux/build.sh --format rpm --version "$version" --binary "$binary" --sha256 "$expected_sha" --out "$out"
package=$(find "$out" -maxdepth 1 -type f -name "f1r3node-$version-*.rpm" -print -quit)
[[ -n "$package" ]] || { echo "RPM package missing" >&2; exit 2; }
packaging/linux/smoke.sh --format rpm --package "$package" --version "$version" --sha256 "$expected_sha"
dnf -y install "$package"
[[ "$(f1r3node --version)" == "f1r3fly $version" ]]
[[ "$(sha256sum /usr/bin/f1r3node | cut -d' ' -f1)" == "$expected_sha" ]]
rpm -q f1r3node
dnf -y remove f1r3node
[[ ! -e /usr/bin/f1r3node ]]
