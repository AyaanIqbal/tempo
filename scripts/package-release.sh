#!/bin/bash
# Package only. This script never commits, tags, pushes, or publishes anything.
set -euo pipefail
cd "$(dirname "$0")/.."
export TEMPO_REQUIRE_UPDATES=1
python3 scripts/write-plist.py /dev/null
./scripts/build-app.sh
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/Tempo.app/Contents/Info.plist)"
repository="$(python3 -c 'import json,os; c=json.load(open("release.json")); print((os.environ.get("TEMPO_RELEASES_REPOSITORY") or c["releasesRepository"]))')"
tag="v$version"
mkdir -p build/release
# Use a fixed asset name so /releases/latest/download/Tempo.zip always works.
archive="build/release/Tempo.zip"
if [[ -e "$archive" ]]; then rm "$archive"; fi
ditto -c -k --sequesterRsrc --keepParent build/Tempo.app "$archive"
if [[ -n "${TEMPO_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$archive" --keychain-profile "$TEMPO_NOTARY_PROFILE" --wait
  xcrun stapler staple build/Tempo.app
  rm "$archive"
  ditto -c -k --sequesterRsrc --keepParent build/Tempo.app "$archive"
fi
signer=".build/artifacts/sparkle/Sparkle/bin/sign_update"
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  signature="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$signer" --ed-key-file - -p "$archive")"
else
  signature="$("$signer" --account app.tempo.tasks -p "$archive")"
fi
# Verify that CI's private key matches the public key baked into the app.
TEMPO_UPDATE_SIGNATURE="$signature" python3 scripts/create-appcast.py "$archive"
(cd build/release && shasum -a 256 Tempo.zip > SHA256SUMS.txt)
echo "Release $tag packaged in build/release. Nothing has been published."
echo "Stable download: https://github.com/$repository/releases/latest/download/Tempo.zip"
