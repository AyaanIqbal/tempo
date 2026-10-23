#!/usr/bin/env python3
import base64
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET
from email.utils import formatdate

SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)


def create(archive, info, signature, public_key, repository):
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError('Expected a 64-byte Ed25519 signature.')
    # CryptoKit verifies the artifact against the key shipped in the application.
    subprocess.run(['swift', 'scripts/verify-update.swift', public_key, signature, str(archive)], check=True)
    root = ET.Element('rss', version='2.0'); channel = ET.SubElement(root, 'channel')
    ET.SubElement(channel, 'title').text = 'Tempo updates'
    ET.SubElement(channel, 'link').text = f'https://github.com/{repository}/releases'
    ET.SubElement(channel, 'description').text = 'Tempo for Mac'
    ET.SubElement(channel, 'language').text = 'en'
    item = ET.SubElement(channel, 'item')
    version = info['CFBundleShortVersionString']
    ET.SubElement(item, 'title').text = f'Tempo {version}'
    ET.SubElement(item, 'pubDate').text = formatdate(usegmt=True)
    ET.SubElement(item, f'{{{SPARKLE}}}version').text = info['CFBundleVersion']
    ET.SubElement(item, f'{{{SPARKLE}}}shortVersionString').text = version
    ET.SubElement(item, f'{{{SPARKLE}}}minimumSystemVersion').text = '14.0.0'
    ET.SubElement(item, 'enclosure', {
        'url': f'https://github.com/{repository}/releases/download/v{version}/Tempo.zip',
        f'{{{SPARKLE}}}edSignature': signature,
        'length': str(archive.stat().st_size), 'type': 'application/octet-stream',
    })
    ET.indent(root)
    return ET.tostring(root, encoding='utf-8', xml_declaration=True)


if __name__ == '__main__':
    archive = Path(sys.argv[1]); config = json.loads(Path('release.json').read_text())
    info = plistlib.loads(Path('build/Tempo.app/Contents/Info.plist').read_bytes())
    repo = (os.environ.get('TEMPO_RELEASES_REPOSITORY') or config['releasesRepository'])
    data = create(archive, info, os.environ['TEMPO_UPDATE_SIGNATURE'], info['SUPublicEDKey'], repo)
    (archive.parent / 'appcast.xml').write_bytes(data)
