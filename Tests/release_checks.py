#!/usr/bin/env python3
import base64
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module


plist = load('tempo_plist', 'scripts/write-plist.py')
appcast = load('tempo_appcast', 'scripts/create-appcast.py')


class ReleaseChecks(unittest.TestCase):
    def setUp(self):
        self.config = {'version': '0.2.0', 'build': 2, 'bundleIdentifier': 'app.tempo.tasks',
                       'releasesRepository': 'AyaanIqbal/tempo', 'publicEDKey': base64.b64encode(bytes(32)).decode()}

    @patch.dict(os.environ, {}, clear=True)
    def test_release_metadata_and_stable_feed(self):
        info = plist.metadata(self.config, require_updates=True)
        self.assertEqual(info['CFBundleVersion'], '2')
        self.assertEqual(info['SUFeedURL'], 'https://github.com/AyaanIqbal/tempo/releases/latest/download/appcast.xml')
        self.assertTrue(info['SUVerifyUpdateBeforeExtraction'])

    @patch.dict(os.environ, {'TEMPO_RELEASES_REPOSITORY': ''}, clear=True)
    def test_empty_ci_override_uses_config(self):
        self.assertIn('SUFeedURL', plist.metadata(self.config, require_updates=True))

    @patch.dict(os.environ, {}, clear=True)
    def test_reject_unconfigured_release(self):
        self.config['publicEDKey'] = ''
        with self.assertRaises(ValueError): plist.metadata(self.config, require_updates=True)
        self.assertNotIn('SUFeedURL', plist.metadata(self.config))

    @patch.dict(os.environ, {}, clear=True)
    def test_reject_invalid_versions_and_keys(self):
        for version, build in [('v0.2.0', 2), ('0.2.0', 0), ('0.2.0', 'abc')]:
            with self.subTest(version=version, build=build):
                with self.assertRaises(ValueError): plist.metadata(dict(self.config, version=version, build=build))
        with self.assertRaises(ValueError): plist.metadata(dict(self.config, publicEDKey='not-a-key'))

    @patch('subprocess.run')
    def test_feed_version_url_and_signature(self, verify):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'Tempo.zip'; archive.write_bytes(b'test archive')
            info = plist.metadata(self.config)
            signature = base64.b64encode(bytes(64)).decode()
            xml = appcast.create(archive, info, signature, self.config['publicEDKey'], 'AyaanIqbal/tempo')
            root = ET.fromstring(xml); item = root.find('./channel/item')
            self.assertEqual(item.find(f'{{{appcast.SPARKLE}}}version').text, '2')
            self.assertEqual(item.find('enclosure').attrib['url'], 'https://github.com/AyaanIqbal/tempo/releases/download/v0.2.0/Tempo.zip')
            self.assertEqual(item.find('enclosure').attrib['length'], str(archive.stat().st_size))
            verify.assert_called_once()


if __name__ == '__main__': unittest.main()
