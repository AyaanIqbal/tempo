#!/bin/bash
# Run once on your Mac. The private signing key stays in the login Keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 1 ]]; then echo "Usage: $0 OWNER/RELEASES_REPO" >&2; exit 1; fi
repository="$1"
if [[ ! "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then echo "Use owner/repo." >&2; exit 1; fi
swift package resolve
keys=".build/artifacts/sparkle/Sparkle/bin/generate_keys"
"$keys" --account app.tempo.tasks
public_key="$("$keys" --account app.tempo.tasks -p)"
python3 - "$repository" "$public_key" <<'PY'
import json, sys
from pathlib import Path
p = Path('release.json'); config = json.loads(p.read_text())
config['releasesRepository'] = sys.argv[1]; config['publicEDKey'] = sys.argv[2].strip()
p.write_text(json.dumps(config, indent=2) + '\n')
PY
echo "Update destination and public key saved to release.json. Never rotate this key casually."
