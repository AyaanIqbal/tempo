#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/icon Assets
swift scripts/generate-icon.swift build/icon/Tempo.iconset Assets/TempoIcon.png
iconutil -c icns build/icon/Tempo.iconset -o Assets/Tempo.icns
echo 'Created Assets/Tempo.icns'
