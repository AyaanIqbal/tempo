#!/bin/bash
# Build a drag-to-Applications download from the already built/signed app.
set -euo pipefail
cd "$(dirname "$0")/.."
app="build/Tempo.app"
image="build/release/Tempo.dmg"
test -d "$app" || { echo 'Build Tempo.app first.' >&2; exit 1; }
codesign --verify --deep --strict "$app"
mkdir -p build/release
stage="$(mktemp -d build/dmg-stage.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Tempo.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname Tempo -srcfolder "$stage" -ov -format UDZO "$image"
if [[ -n "${TEMPO_SIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$TEMPO_SIGN_IDENTITY" --timestamp "$image"
fi
if [[ -n "${TEMPO_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$image" --keychain-profile "$TEMPO_NOTARY_PROFILE" --wait
  xcrun stapler staple "$image"
fi
hdiutil verify "$image"
echo "Built $image"
