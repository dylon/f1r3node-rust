#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 --format deb|arch|rpm|tar --package FILE --version X.Y.Z --sha256 HEX" >&2
}

format='' package='' version='' expected_sha=''
while (($#)); do
  case "$1" in
    --format|--package|--version|--sha256)
      (($# >= 2)) || { usage; exit 2; }
      case "$1" in
        --format) format=$2 ;;
        --package) package=$2 ;;
        --version) version=$2 ;;
        --sha256) expected_sha=$2 ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[[ -n "$format" && -n "$package" && -n "$version" && -n "$expected_sha" ]] || { usage; exit 2; }
[[ -f "$package" ]] || { echo "missing package: $package" >&2; exit 2; }
[[ "$expected_sha" =~ ^[0-9a-f]{64}$ ]] || { echo "invalid SHA-256 digest" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
case "$format" in
  deb)
    [[ "$(dpkg-deb -f "$package" Package)" == f1r3node ]]
    [[ "$(dpkg-deb -f "$package" Version)" == "$version" ]]
    dpkg-deb -x "$package" "$work"
    ;;
  arch)
    bsdtar -xf "$package" -C "$work"
    bsdtar -xOf "$package" .PKGINFO | grep -Fx "pkgname = f1r3node"
    bsdtar -xOf "$package" .PKGINFO | grep -Fx "pkgver = $version-1"
    ;;
  rpm)
    [[ "$(rpm -qp --qf '%{NAME}' "$package")" == f1r3node ]]
    [[ "$(rpm -qp --qf '%{VERSION}' "$package")" == "$version" ]]
    (cd "$work" && rpm2cpio "$package" | cpio --quiet -id)
    ;;
  tar)
    tar -xzf "$package" -C "$work" --strip-components=1
    ;;
  *) echo "unsupported format: $format" >&2; exit 2 ;;
esac

binary=$work/usr/bin/f1r3node
unit=$work/usr/lib/systemd/system/f1r3node.service
license=$work/usr/share/licenses/f1r3node/LICENSE.TXT
[[ -x "$binary" && -f "$unit" && -s "$license" ]] || { echo "incomplete package payload" >&2; exit 2; }
[[ "$(sha256sum "$binary" | cut -d' ' -f1)" == "$expected_sha" ]] || { echo "packaged binary differs from tested binary" >&2; exit 2; }
[[ "$("$binary" --version)" == "f1r3fly $version" ]] || { echo "packaged binary version mismatch" >&2; exit 2; }
grep -Fx 'DynamicUser=yes' "$unit" >/dev/null
grep -Fx 'StateDirectory=f1r3node' "$unit" >/dev/null
grep -F 'ExecStart=/usr/bin/f1r3node run --data-dir=/var/lib/f1r3node --api-host=127.0.0.1' "$unit" >/dev/null
echo "smoke passed: $package"
