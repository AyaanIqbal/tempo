#!/usr/bin/env python3
"""Reject a release that installed clients would treat as a downgrade/no-op."""
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

config = json.loads(Path('release.json').read_text())
root = ET.parse(sys.argv[1]).getroot()
namespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
previous = [e.text for e in root.findall(f'.//{{{namespace}}}version')]
if not previous or any(not value or not value.isdigit() for value in previous):
    raise SystemExit('The previous update feed has an invalid build number.')
if int(config['build']) <= max(map(int, previous)):
    raise SystemExit('Increase the build number in release.json before releasing.')
print('Release build number increases correctly.')
