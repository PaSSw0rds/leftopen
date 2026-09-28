import importlib.util
import plistlib
import tempfile
import unittest
from pathlib import Path


spec = importlib.util.spec_from_file_location(
    "prepare_release", Path(__file__).resolve().parents[2] / "Scripts/prepare-release.py"
)
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class PrepareReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.plist = self.root / "Resources/Info.plist"
        self.cli = self.root / "Sources/LeftOpenCLI/main.swift"
        self.plist.parent.mkdir(parents=True)
        self.cli.parent.mkdir(parents=True)
        self.plist.write_bytes(plistlib.dumps({
            "CFBundleVersion": "13", "CFBundleShortVersionString": "0.4.0",
            "CFBundleIdentifier": "app.leftopen.mac",
        }))
        self.cli.write_text('print("LeftOpen 0.4.0")\n')

    def test_both_versions_and_identity(self):
        release.prepare(self.root, "0.10.0", 1001, "v0.9.0")
        data = plistlib.loads(self.plist.read_bytes())
        self.assertEqual(data["CFBundleShortVersionString"], "0.10.0")
        self.assertEqual(data["CFBundleVersion"], "1001")
        self.assertEqual(data["CFBundleIdentifier"], "app.leftopen.mac")
        self.assertEqual(self.cli.read_text(), 'print("LeftOpen 0.10.0")\n')

    def test_rejects_invalid_or_older_versions_without_writes(self):
        before = self.plist.read_bytes(), self.cli.read_bytes()
        for value in ["v0.4.1", "0.04.1", "0.4.1-beta", "0.4.0", "0.3.9", "$(id)", "0.4.1\n"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                release.prepare(self.root, value, 1001, "v0.4.0")
            self.assertEqual((self.plist.read_bytes(), self.cli.read_bytes()), before)

    def test_rejects_reused_build(self):
        with self.assertRaises(ValueError):
            release.prepare(self.root, "0.4.1", 13, "v0.4.0")

    def test_cli_drift_leaves_plist_untouched(self):
        before = self.plist.read_bytes()
        self.cli.write_text('print("new version mechanism")\n')
        with self.assertRaises(ValueError):
            release.prepare(self.root, "0.4.1", 1001, "v0.4.0")
        self.assertEqual(self.plist.read_bytes(), before)
