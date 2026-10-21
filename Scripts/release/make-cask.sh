#!/bin/sh
# Prints the Homebrew cask of a release, which installs the prebuilt SimDeeplink.app.
#
#   Scripts/release/make-cask.sh VERSION SHA256 > simdeeplink.rb
#
# The Release workflow runs this and attaches the result to the GitHub release; copy it to Casks/simdeeplink.rb in
# alifu/homebrew-tap (the workflow does that itself when the TAP_TOKEN secret is set).
set -eu

[ $# -eq 2 ] || { echo "usage: make-cask.sh VERSION SHA256" >&2; exit 2; }
version="$1"
sha="$2"
case "$version" in *[!0-9.]* | "") echo "bad version: $version" >&2; exit 2 ;; esac
case "$sha" in *[!0-9a-f]* | "") echo "bad sha256: $sha" >&2; exit 2 ;; esac
[ "${#sha}" -eq 64 ] || { echo "sha256 must be 64 hex digits" >&2; exit 2; }

cat <<RUBY
cask "simdeeplink" do
  version "$version"
  sha256 "$sha"

  url "https://github.com/alifu/SimDeeplink/releases/download/v#{version}/SimDeeplink.zip"
  name "SimDeeplink"
  desc "Menu bar app that runs deeplinks on iOS simulators and Android emulators"
  homepage "https://github.com/alifu/SimDeeplink"

  depends_on macos: :sequoia

  app "stage/SimDeeplink.app"

  uninstall quit: "com.alifu.SimDeeplink"

  zap trash: [
    "~/Library/Preferences/com.alifu.SimDeeplink.plist",
    "~/Library/Saved Application State/com.alifu.SimDeeplink.savedState",
  ]
end
RUBY
