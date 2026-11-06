import importlib.util
import json
import os
import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
spec = importlib.util.spec_from_file_location('release', Path(__file__).with_name('release.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        p = patch.object(release, 'ROOT', self.root)
        p.start()
        self.addCleanup(p.stop)
        p = patch.dict(os.environ, {'GITHUB_SHA': 'test-commit'})
        p.start()
        self.addCleanup(p.stop)
        (self.root / 'Resources').mkdir()
        with (self.root / 'Resources/Info.plist').open('wb') as stream:
            plistlib.dump({'CFBundleShortVersionString': '0.4.7', 'CFBundleVersion': '13'}, stream)
        (self.root / 'dist').mkdir()

    def builds(self):
        for arch in release.ARCHES:
            for ext in ['dmg', 'app.zip']:
                (self.root / 'dist' / f'LaunchpadOS_0.4.7_{arch}.{ext}').write_bytes(b'installer-test')
            release.collect(arch)

    def test_tag_matches_plist(self):
        self.assertEqual(release.version('v0.4.7'), '0.4.7')
        with self.assertRaises(ValueError):
            release.version('v0.4.8')

    def test_complete_release(self):
        self.builds()
        release.assemble()
        self.assertEqual(len((self.root / 'release/SHA256SUMS.txt').read_text().splitlines()), 6)

    def test_missing_architecture_rejected(self):
        self.builds()
        (self.root / 'artifacts/manifest-universal.json').unlink()
        with self.assertRaises(ValueError):
            release.assemble()
        self.assertFalse((self.root / 'release').exists())

    def test_tampered_installer_rejected(self):
        self.builds()
        (self.root / 'artifacts/LaunchpadOS_0.4.7_arm64.dmg').write_bytes(b'corrupt')
        with self.assertRaises(ValueError):
            release.assemble()

    def test_mixed_commit_rejected(self):
        self.builds()
        with patch.dict(os.environ, {'GITHUB_SHA': 'different-commit'}):
            with self.assertRaises(ValueError):
                release.assemble()


if __name__ == '__main__':
    unittest.main()
