#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 --format deb|arch|rpm|tar --version X.Y.Z --binary FILE --sha256 HEX [--out DIR]" >&2
}

format='' version='' binary='' expected_sha='' out=dist
while (($#)); do
  case "$1" in
    --format|--version|--binary|--sha256|--out)
      (($# >= 2)) || { usage; exit 2; }
      case "$1" in
        --format) format=$2 ;;
        --version) version=$2 ;;
        --binary) binary=$2 ;;
        --sha256) expected_sha=$2 ;;
        --out) out=$2 ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[[ -n "$format" && -n "$version" && -n "$binary" && -n "$expected_sha" ]] || { usage; exit 2; }
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "invalid version: $version" >&2; exit 2; }
[[ "$expected_sha" =~ ^[0-9a-f]{64}$ ]] || { echo "invalid SHA-256 digest" >&2; exit 2; }
[[ -f "$binary" && -x "$binary" ]] || { echo "missing executable: $binary" >&2; exit 2; }

here=$(cd "$(dirname "$0")" && pwd)
project=$(cd "$here/../.." && pwd)
binary=$(realpath "$binary")
mkdir -p "$out"
out=$(cd "$out" && pwd)

source_version=$(sed -n '/^\[package\]/,/^\[/{s/^version = "\([^"]*\)"/\1/p;}' "$project/node/Cargo.toml" | head -n 1)
[[ "$version" == "$source_version" ]] || { echo "version differs from node/Cargo.toml: $source_version" >&2; exit 2; }
actual_sha=$(sha256sum "$binary" | cut -d' ' -f1)
[[ "$actual_sha" == "$expected_sha" ]] || { echo "binary SHA-256 mismatch" >&2; exit 2; }

host_arch=$(uname -m)
case "$host_arch" in
  x86_64) deb_arch=amd64; rpm_arch=x86_64; machine='Advanced Micro Devices X86-64' ;;
  aarch64) deb_arch=arm64; rpm_arch=aarch64; machine='AArch64' ;;
  *) echo "unsupported host architecture: $host_arch" >&2; exit 2 ;;
esac
actual_machine=$(readelf -h "$binary" | awk -F: '/Machine:/{gsub(/^[ \t]+/,"",$2);print $2}')
[[ "$actual_machine" == "$machine" ]] || { echo "binary targets $actual_machine, host is $host_arch" >&2; exit 2; }
[[ "$("$binary" --version)" == "f1r3fly $version" ]] || { echo "binary version mismatch" >&2; exit 2; }

needed=$(readelf -d "$binary" | awk -F '[][]' '/\(NEEDED\)/{print $2}')
while IFS= read -r library; do
  case "$library" in
    ld-linux-x86-64.so.2|ld-linux-aarch64.so.1|libc.so.6|libm.so.6|libgcc_s.so.1|libssl.so.3|libcrypto.so.3|libz.so.1|libbrotlienc.so.1|libbrotlidec.so.1|libbrotlicommon.so.1|libzstd.so.1) ;;
    *) echo "unmapped runtime library: $library" >&2; exit 2 ;;
  esac
done <<< "$needed"
glibc_min=$(readelf --version-info "$binary" | sed -n 's/.*GLIBC_\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | sort -Vu | tail -n 1)
[[ -n "$glibc_min" ]] || { echo "cannot determine glibc requirement" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
stage() {
  local root=$1
  install -Dm755 "$binary" "$root/usr/bin/f1r3node"
  install -Dm644 "$project/node/rnode.service" "$root/usr/lib/systemd/system/f1r3node.service"
  install -Dm644 "$project/LICENSE.TXT" "$root/usr/share/licenses/f1r3node/LICENSE.TXT"
}

case "$format" in
  deb)
    command -v dpkg-deb >/dev/null || { echo "dpkg-deb is required" >&2; exit 2; }
    root=$work/deb
    stage "$root"
    mkdir -p "$root/DEBIAN"
    size=$(du -sk "$root/usr" | cut -f1)
    cat > "$root/DEBIAN/control" <<EOF
Package: f1r3node
Version: $version
Section: net
Priority: optional
Architecture: $deb_arch
Installed-Size: $size
Depends: libc6 (>= $glibc_min), libgcc-s1, libssl3 | libssl3t64, zlib1g, libbrotli1, libzstd1, systemd
Maintainer: F1R3FLY.io <f1r3fly.ceo@gmail.com>
Homepage: https://github.com/F1R3FLY-io/f1r3node-rust
Description: F1R3Node blockchain service and command-line client
 The service is installed but is not enabled or started automatically.
EOF
    cat > "$root/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
fi
EOF
    cat > "$root/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = remove ] && command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now f1r3node.service || true
fi
EOF
    cat > "$root/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
fi
EOF
    chmod 755 "$root/DEBIAN/postinst" "$root/DEBIAN/prerm" "$root/DEBIAN/postrm"
    dpkg-deb --root-owner-group --build "$root" "$out/f1r3node_${version}_${deb_arch}.deb"
    ;;
  arch)
    command -v makepkg >/dev/null || { echo "makepkg is required" >&2; exit 2; }
    mkdir -p "$work/arch"
    cp "$here/arch/PKGBUILD" "$work/arch/PKGBUILD"
    cp /etc/makepkg.conf "$work/arch/makepkg.conf"
    printf "\nPKGEXT='.pkg.tar.zst'\nPACKAGER='F1R3FLY.io <f1r3fly.ceo@gmail.com>'\n" >> "$work/arch/makepkg.conf"
    (
      cd "$work/arch"
      F1R3NODE_BINARY="$binary" F1R3NODE_SOURCE="$project" F1R3NODE_VERSION="$version" \
        PKGDEST="$out" SRCDEST="$work/arch" SRCPKGDEST="$work/arch" \
        BUILDDIR="$work/arch" LOGDEST="$work/arch" \
        makepkg --config "$work/arch/makepkg.conf" --nodeps --noconfirm --force
    )
    ;;
  rpm)
    command -v rpmbuild >/dev/null || { echo "rpmbuild is required" >&2; exit 2; }
    mkdir -p "$work/rpm"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
    install -m755 "$binary" "$work/rpm/SOURCES/f1r3node"
    install -m644 "$project/node/rnode.service" "$work/rpm/SOURCES/f1r3node.service"
    install -m644 "$project/LICENSE.TXT" "$work/rpm/SOURCES/LICENSE.TXT"
    rpmbuild -bb "$here/rpm/f1r3node.spec" \
      --target "$rpm_arch" \
      --define "_topdir $work/rpm" \
      --define "node_version $version" \
      --define "__os_install_post %{nil}" \
      --define "debug_package %{nil}"
    find "$work/rpm/RPMS" -name '*.rpm' -exec cp {} "$out/" \;
    ;;
  tar)
    root=$work/f1r3node-$version
    stage "$root"
    tar -C "$work" -czf "$out/f1r3node-$version-linux-$host_arch.tar.gz" "f1r3node-$version"
    ;;
  *) echo "unsupported format: $format" >&2; exit 2 ;;
esac
