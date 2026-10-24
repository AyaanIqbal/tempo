#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/Tempo.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
if [[ "${TEMPO_UNIVERSAL:-0}" == "1" ]]; then
  for arch in arm64 x86_64; do
    swift build -c release --arch "$arch"
  done
  arm_bin="$(swift build -c release --arch arm64 --show-bin-path)/Tempo"
  intel_bin="$(swift build -c release --arch x86_64 --show-bin-path)/Tempo"
  lipo -create "$arm_bin" "$intel_bin" -output "$APP/Contents/MacOS/Tempo"
else
  swift build -c release
  bin_dir="$(swift build -c release --show-bin-path)"
  cp "$bin_dir/Tempo" "$APP/Contents/MacOS/Tempo"
fi
sparkle_framework=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$sparkle_framework" ]]; then
  echo "Sparkle.framework was not resolved at the expected location." >&2; exit 1
fi
ditto "$sparkle_framework" "$APP/Contents/Frameworks/Sparkle.framework"
test -f Assets/Tempo.icns || ./scripts/generate-icon.sh
cp Assets/Tempo.icns "$APP/Contents/Resources/Tempo.icns"
python3 scripts/write-plist.py "$APP/Contents/Info.plist"
# Finder metadata is not permitted in a signed app bundle.
xattr -cr "$APP"
if [[ -n "${TEMPO_SIGN_IDENTITY:-}" ]]; then
  # Sign nested code from the inside out, preserving Sparkle's helper entitlements.
  framework="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  for nested in "$framework/XPCServices/Downloader.xpc" "$framework/XPCServices/Installer.xpc" "$framework/Updater.app" "$framework/Autoupdate"; do
    if [[ -e "$nested" ]]; then
      codesign --force --sign "$TEMPO_SIGN_IDENTITY" --options runtime --timestamp --preserve-metadata=entitlements "$nested"
    fi
  done
  codesign --force --sign "$TEMPO_SIGN_IDENTITY" --options runtime --timestamp "$APP/Contents/Frameworks/Sparkle.framework"
  codesign --force --sign "$TEMPO_SIGN_IDENTITY" --options runtime --timestamp "$APP"
else
  # Local development signing. Do not enable hardened runtime without a Developer ID.
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "Built $APP"
