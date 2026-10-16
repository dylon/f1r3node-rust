#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 --version X.Y.Z --arm64 FILE --arm64-sha256 HEX --x86_64 FILE --x86_64-sha256 HEX [--out DIR]" >&2
}

version='' arm64='' arm64_sha='' x86_64='' x86_64_sha='' out=dist
while (($#)); do
  case "$1" in
    --version|--arm64|--arm64-sha256|--x86_64|--x86_64-sha256|--out)
      (($# >= 2)) || { usage; exit 2; }
      case "$1" in
        --version) version=$2 ;;
        --arm64) arm64=$2 ;;
        --arm64-sha256) arm64_sha=$2 ;;
        --x86_64) x86_64=$2 ;;
        --x86_64-sha256) x86_64_sha=$2 ;;
        --out) out=$2 ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { usage; exit 2; }
[[ "$arm64_sha" =~ ^[0-9a-f]{64}$ && "$x86_64_sha" =~ ^[0-9a-f]{64}$ ]] || { echo "invalid SHA-256 digest" >&2; exit 2; }
[[ -x "$arm64" && -x "$x86_64" ]] || { echo "missing node binary" >&2; exit 2; }

here=$(cd "$(dirname "$0")" && pwd)
project=$(cd "$here/../.." && pwd)
source_version=$(sed -n '/^\[package\]/,/^\[/{s/^version = "\([^"]*\)"/\1/p;}' "$project/node/Cargo.toml" | head -n 1)
[[ "$version" == "$source_version" ]] || { echo "version differs from node/Cargo.toml: $source_version" >&2; exit 2; }

for arch in arm64 x86_64; do
  if [[ "$arch" == arm64 ]]; then binary=$arm64; expected=$arm64_sha; else binary=$x86_64; expected=$x86_64_sha; fi
  [[ "$(shasum -a 256 "$binary" | cut -d' ' -f1)" == "$expected" ]] || { echo "$arch binary SHA-256 mismatch" >&2; exit 2; }
  [[ "$(lipo -archs "$binary")" == "$arch" ]] || { echo "$arch binary architecture mismatch" >&2; exit 2; }
  [[ "$("$binary" --version)" == "f1r3fly $version" ]] || { echo "$arch binary version mismatch" >&2; exit 2; }
  if otool -L "$binary" | tail -n +2 | awk '{print $1}' | grep -Ev '^(/System/Library/|/usr/lib/)' | grep -q .; then
    echo "$arch binary has external dynamic libraries" >&2
    otool -L "$binary" >&2
    exit 2
  fi
done

mkdir -p "$out"
out=$(cd "$out" && pwd)
[[ ! -e "$out/f1r3node-$version-macos-universal.pkg" && ! -e "$out/f1r3node-$version-macos-universal.tar.gz" ]] || { echo "package output already exists" >&2; exit 2; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
root="$work/root"
install -d "$root/usr/local/bin" "$root/usr/local/share/f1r3node"
lipo -create "$arm64" "$x86_64" -output "$root/usr/local/bin/f1r3node"
chmod 755 "$root/usr/local/bin/f1r3node"
lipo "$root/usr/local/bin/f1r3node" -verify_arch arm64 x86_64
install -m755 "$here/f1r3node-service" "$root/usr/local/bin/f1r3node-service"
install -m644 "$here/launchd.plist" "$root/usr/local/share/f1r3node/launchd.plist"
install -m644 "$project/LICENSE.TXT" "$root/usr/local/share/f1r3node/LICENSE.TXT"

if [[ -n "${MACOS_SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --options runtime --sign "$MACOS_SIGN_IDENTITY" "$root/usr/local/bin/f1r3node"
  codesign --verify --strict "$root/usr/local/bin/f1r3node"
fi

pkg="$out/f1r3node-$version-macos-universal.pkg"
pkg_args=(--root "$root" --install-location / --identifier io.f1r3fly.f1r3node --version "$version")
if [[ -n "${MACOS_INSTALLER_SIGN_IDENTITY:-}" ]]; then
  pkg_args+=(--sign "$MACOS_INSTALLER_SIGN_IDENTITY")
fi
pkgbuild "${pkg_args[@]}" "$pkg"
pkgutil --payload-files "$pkg" > "$work/pkg-files"
for path in usr/local/bin/f1r3node usr/local/bin/f1r3node-service usr/local/share/f1r3node/launchd.plist usr/local/share/f1r3node/LICENSE.TXT; do
  grep -Fq "$path" "$work/pkg-files" || { echo "missing package payload: $path" >&2; exit 2; }
done

archive="$out/f1r3node-$version-macos-universal.tar.gz"
tar -czf "$archive" -C "$root" usr/local/bin/f1r3node usr/local/bin/f1r3node-service usr/local/share/f1r3node/launchd.plist usr/local/share/f1r3node/LICENSE.TXT
(cd "$out" && shasum -a 256 "$(basename "$pkg")" "$(basename "$archive")" > "f1r3node-$version-macos-universal.sha256")
echo "built $pkg and $archive"
