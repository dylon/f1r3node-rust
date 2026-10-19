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
IFS=. read -r major minor patch <<< "$version"
if ((patch > 0)); then older="$major.$minor.$((patch - 1))"
elif ((minor > 0)); then older="$major.$((minor - 1)).1"
elif ((major > 0)); then older="$((major - 1)).1.1"
else exit 2
fi
older_work=$(mktemp -d)
trap 'rm -rf "$older_work"' EXIT
mkdir -p "$older_work"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
install -m755 "$binary" "$older_work/SOURCES/f1r3node"
install -m644 node/rnode.service "$older_work/SOURCES/f1r3node.service"
install -m644 LICENSE.TXT "$older_work/SOURCES/LICENSE.TXT"
rpmbuild -bb packaging/linux/rpm/f1r3node.spec --target "$(uname -m)" \
  --define "_topdir $older_work" --define "node_version $older" \
  --define "__os_install_post %{nil}" --define "debug_package %{nil}"
older_package=$(find "$older_work/RPMS" -name '*.rpm' -print -quit)
[[ -s "$older_package" ]]
install -d -m 0700 /var/lib/f1r3node
printf 'preserve package state\n' > /var/lib/f1r3node/package-smoke-sentinel
dnf -y install "$older_package"
[[ "$(rpm -q --qf '%{VERSION}' f1r3node)" == "$older" ]]
dnf -y upgrade "$package"
[[ "$(rpm -q --qf '%{VERSION}' f1r3node)" == "$version" ]]
[[ -s /var/lib/f1r3node/package-smoke-sentinel ]]
[[ "$(f1r3node --version)" == "f1r3fly $version" ]]
[[ "$(sha256sum /usr/bin/f1r3node | cut -d' ' -f1)" == "$expected_sha" ]]
rpm -q f1r3node
dnf -y remove f1r3node
[[ ! -e /usr/bin/f1r3node ]]
[[ -s /var/lib/f1r3node/package-smoke-sentinel ]]
