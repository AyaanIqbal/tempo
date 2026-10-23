#!/usr/bin/env python3
"""Transfer the Tempo Keychain key into a GitHub encrypted secret. Never print it."""
import base64
import os
from pathlib import Path
import subprocess
import tempfile

# Sparkle's export tool requires a nonexistent regular file, so /dev/stdout
# cannot be used. A 0700 temporary directory protects the brief export.
with tempfile.TemporaryDirectory(prefix='tempo-key-transfer-') as directory:
    os.chmod(directory, 0o700)
    export = Path(directory) / 'signing-key'
    try:
        result = subprocess.run([
            '.build/artifacts/sparkle/Sparkle/bin/generate_keys',
            '--account', 'app.tempo.tasks', '-x', str(export)
        ], capture_output=True)
        if result.returncode:
            raise SystemExit('Keychain export failed; no secret was uploaded.')
        export.chmod(0o600)
        key = export.read_bytes().strip()
        if len(base64.b64decode(key, validate=True)) not in (32, 96):
            raise SystemExit('Unexpected signing key format; no secret was uploaded.')
        subprocess.run(['gh', 'secret', 'set', 'SPARKLE_PRIVATE_KEY', '--repo', 'AyaanIqbal/tempo'], input=key, check=True)
    finally:
        export.unlink(missing_ok=True)
print('SPARKLE_PRIVATE_KEY saved as an encrypted GitHub Actions secret. Temporary export removed.')
