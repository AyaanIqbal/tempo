#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product TempoChecks
bin_dir="$(swift build --show-bin-path)"
swiftc -swift-version 6 -parse-as-library -I "$bin_dir/Modules" \
  Sources/Tempo/Store.swift Tests/InteractionChecks.swift \
  "$bin_dir"/TempoCore.build/*.swift.o -o "$bin_dir/TempoInteractionChecks"
"$bin_dir/TempoInteractionChecks"
