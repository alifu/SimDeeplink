#!/bin/sh
# Fails unless every target of the Xcode project names one version, and it is the expected one.
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
