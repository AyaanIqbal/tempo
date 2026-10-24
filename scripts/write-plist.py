#!/usr/bin/env python3
"""Single source of truth for bundle and release metadata; never contains private keys."""
import base64
import json
import os
import plistlib
import re
import sys
from pathlib import Path


def metadata(config, require_updates=False):
    version = os.environ.get("TEMPO_VERSION", config["version"])
    build = os.environ.get("TEMPO_BUILD", str(config["build"]))
    repository = (os.environ.get("TEMPO_RELEASES_REPOSITORY") or config["releasesRepository"])
    key = config["publicEDKey"].strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or not re.fullmatch(r"[1-9]\d*", build):
        raise ValueError("Use a major.minor.patch version and a positive, increasing build number.")
    if repository and not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("releasesRepository must be owner/repo.")
    if key and len(base64.b64decode(key, validate=True)) != 32:
        raise ValueError("The Sparkle public key must decode to 32 bytes.")
    if require_updates and (not repository or not key):
        raise ValueError("Configure releasesRepository and publicEDKey in release.json first.")
    result = {
        "CFBundleExecutable": "Tempo", "CFBundleIdentifier": config["bundleIdentifier"],
        "CFBundleIconFile": "Tempo.icns", "CFBundleName": "Tempo", "CFBundleDisplayName": "Tempo", "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": version, "CFBundleVersion": build,
        "LSMinimumSystemVersion": "14.0", "NSHighResolutionCapable": True,
    }
    if repository and key:
        result.update({
            "SUFeedURL": f"https://github.com/{repository}/releases/latest/download/appcast.xml",
            "SUPublicEDKey": key, "SUEnableAutomaticChecks": True,
            "SUAutomaticallyUpdate": True, "SUScheduledCheckInterval": 86400,
            "SUVerifyUpdateBeforeExtraction": True,
        })
    return result


if __name__ == "__main__":
    config = json.loads(Path("release.json").read_text())
    data = metadata(config, require_updates=os.environ.get("TEMPO_REQUIRE_UPDATES") == "1")
    Path(sys.argv[1]).write_bytes(plistlib.dumps(data))
