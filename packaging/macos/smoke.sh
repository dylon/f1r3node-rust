#!/usr/bin/env bash
set -euo pipefail

version=${1:?version required}
dist=${2:?distribution directory required}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "invalid version" >&2; exit 2; }
dist=$(cd "$dist" && pwd)
pkg="$dist/f1r3node-$version-macos-universal.pkg"
archive="$dist/f1r3node-$version-macos-universal.tar.gz"
manifest="$dist/f1r3node-$version-macos-universal.sha256"
[[ -s "$pkg" && -s "$archive" && -s "$manifest" ]] || { echo "missing macOS package" >&2; exit 2; }
(cd "$dist" && shasum -a 256 -c "$(basename "$manifest")")

work=$(mktemp -d)
service_installed=0
cleanup() {
  local code=$?
  if [[ "$service_installed" == 1 ]]; then /usr/local/bin/f1r3node-service uninstall || true; fi
  rm -rf "$work"
  exit "$code"
}
trap cleanup EXIT

mkdir -p "$work/stage"
tar -xzf "$archive" -C "$work/stage"
binary="$work/stage/usr/local/bin/f1r3node"
[[ -x "$binary" && -x "$work/stage/usr/local/bin/f1r3node-service" ]] || { echo "incomplete archive" >&2; exit 2; }
lipo "$binary" -verify_arch arm64 x86_64
[[ "$("$binary" --version)" == "f1r3fly $version" ]]
plutil -lint "$work/stage/usr/local/share/f1r3node/launchd.plist"

IFS=. read -r major minor patch <<< "$version"
if ((patch > 0)); then older="$major.$minor.$((patch - 1))"
elif ((minor > 0)); then older="$major.$((minor - 1)).1"
elif ((major > 0)); then older="$((major - 1)).1.1"
else echo "version 0.0.0 cannot test an upgrade" >&2; exit 2
fi
pkgbuild --root "$work/stage" --install-location / --identifier io.f1r3fly.f1r3node --version "$older" "$work/older.pkg"
sudo installer -pkg "$work/older.pkg" -target /
[[ "$(pkgutil --pkg-info io.f1r3fly.f1r3node | awk '/^version:/ {print $2}')" == "$older" ]]
sudo installer -pkg "$pkg" -target /
[[ "$(pkgutil --pkg-info io.f1r3fly.f1r3node | awk '/^version:/ {print $2}')" == "$version" ]]
cmp "$binary" /usr/local/bin/f1r3node
[[ "$(/usr/local/bin/f1r3node --version)" == "f1r3fly $version" ]]
[[ ! -e "$HOME/Library/LaunchAgents/io.f1r3fly.f1r3node.plist" ]] || { echo "service started without opt-in" >&2; exit 2; }

data_dir="$HOME/Library/Application Support/F1R3Node"
mkdir -p "$data_dir"
printf 'standalone = true\n' > "$data_dir/rnode.conf"
printf 'preserve user data\n' > "$data_dir/package-smoke-sentinel"
/usr/local/bin/f1r3node-service install
service_installed=1
/usr/local/bin/f1r3node-service status >/dev/null
started=0
for ((attempt = 0; attempt < 60; attempt++)); do
  if [[ -f "$data_dir/launchd.log" ]] && grep -Fq 'All tasks started. Node is now running.' "$data_dir/launchd.log" && pgrep -f '^/usr/local/bin/f1r3node run --data-dir=' >/dev/null && curl --fail --silent --show-error --max-time 2 http://127.0.0.1:40403/status >/dev/null 2>&1; then started=1; break; fi
  sleep 1
done
[[ "$started" == 1 ]] || { [[ ! -f "$data_dir/launchd.log" ]] || cat "$data_dir/launchd.log" >&2; echo "service did not start" >&2; exit 1; }
/usr/local/bin/f1r3node-service stop
/usr/local/bin/f1r3node-service start
/usr/local/bin/f1r3node-service status >/dev/null
restarted=0
for ((attempt = 0; attempt < 60; attempt++)); do
  if pgrep -f '^/usr/local/bin/f1r3node run --data-dir=' >/dev/null && curl --fail --silent --show-error --max-time 2 http://127.0.0.1:40403/status >/dev/null 2>&1; then restarted=1; break; fi
  sleep 1
done
[[ "$restarted" == 1 ]] || { cat "$data_dir/launchd.log" >&2; echo "service did not restart" >&2; exit 1; }
/usr/local/bin/f1r3node-service uninstall
service_installed=0
[[ ! -e "$HOME/Library/LaunchAgents/io.f1r3fly.f1r3node.plist" ]]
[[ "$(cat "$data_dir/package-smoke-sentinel")" == 'preserve user data' ]]
echo "macOS package smoke passed"
