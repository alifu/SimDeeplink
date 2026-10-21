#!/bin/sh
# Fails unless tauri.conf.json, Cargo.toml and package.json name one version, and it is the expected one.
#
#   Scripts/release/check-version.sh [expected-version]
set -eu

conf="$(sed -n 's/^ *"version": *"\([0-9.]*\)".*/\1/p' src-tauri/tauri.conf.json | head -n 1)"
cargo="$(sed -n 's/^version = "\([0-9.]*\)".*/\1/p' src-tauri/Cargo.toml | head -n 1)"
node="$(sed -n 's/^ *"version": *"\([0-9.]*\)".*/\1/p' package.json | head -n 1)"
expected="${1:-$conf}"

echo "tauri.conf.json $conf, Cargo.toml $cargo, package.json $node, expected $expected"
[ -n "$conf" ] && [ "$conf" = "$expected" ] && [ "$cargo" = "$expected" ] && [ "$node" = "$expected" ] || {
  echo "version mismatch" >&2
  exit 1
}
