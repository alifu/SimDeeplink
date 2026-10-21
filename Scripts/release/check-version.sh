#!/bin/sh
# Fails unless the Xcode project and the Tauri app (when present) all name one version, and it is the expected one.
#
#   Scripts/release/check-version.sh [expected-version]
set -eu

versions="$(sed -n 's/.*MARKETING_VERSION = \([0-9][0-9.]*\);/\1/p' SimDeeplink.xcodeproj/project.pbxproj | sort -u)"
count="$(printf '%s\n' "$versions" | grep -c . || true)"
app="$(printf '%s\n' "$versions" | head -n 1)"
expected="${1:-$app}"

echo "app $app ($count distinct), expected $expected"
[ "$count" -eq 1 ] && [ "$app" = "$expected" ] || {
  echo "version mismatch" >&2
  exit 1
}

# The Tauri app lives in crossplatform/ until it replaces the Swift app.
if [ -d crossplatform ]; then
  conf="$(sed -n 's/^ *"version": *"\([0-9.]*\)".*/\1/p' crossplatform/src-tauri/tauri.conf.json | head -n 1)"
  cargo="$(sed -n 's/^version = "\([0-9.]*\)".*/\1/p' crossplatform/src-tauri/Cargo.toml | head -n 1)"
  node="$(sed -n 's/^ *"version": *"\([0-9.]*\)".*/\1/p' crossplatform/package.json | head -n 1)"
  echo "tauri.conf.json $conf, Cargo.toml $cargo, package.json $node"
  [ "$conf" = "$expected" ] && [ "$cargo" = "$expected" ] && [ "$node" = "$expected" ] || {
    echo "Tauri version mismatch" >&2
    exit 1
  }
fi
