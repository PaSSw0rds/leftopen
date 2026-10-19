import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('dev_app', Path(__file__).resolve().parents[2] / 'Scripts/dev-app.py')
dev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dev)


class LocalAppTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.build = dev.LocalBuild(self.root)

    def owned(self):
        self.build.directory.mkdir(parents=True)
        (self.build.directory / dev.MARKER).write_text('leftopen-local-build-v1\n')
        (self.build.app / 'Contents').mkdir(parents=True)
        (self.build.app / 'Contents/Info.plist').write_text('fixture')

    def test_unknown_directory_and_symlink_are_untouched(self):
        self.build.directory.mkdir(parents=True)
        keep = self.build.directory / 'keep.txt'
        keep.write_text('user data')
        with self.assertRaises(RuntimeError):
            self.build.clean()
        self.assertTrue(keep.exists())
        other = self.root / 'other'
        other.mkdir()
        self.build.app.symlink_to(other, target_is_directory=True)
        with self.assertRaises(RuntimeError):
            self.build.check_paths()
        self.assertTrue(other.exists())

    def test_active_app_or_runtime_prevents_removal(self):
        self.owned()
        for executable in ['Contents/MacOS/LeftOpenApp', 'Contents/Resources/Portless/node-arm64']:
            output = str(self.build.app.resolve() / executable) + '\n'
            with patch.object(dev.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, output, '')):
                with self.assertRaises(RuntimeError):
                    self.build.clean()
            self.assertTrue(self.build.app.exists())

    def test_scan_failure_does_not_remove_bundle(self):
        self.owned()
        with patch.object(dev.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'ps')):
            with self.assertRaises(subprocess.CalledProcessError):
                self.build.clean()
        self.assertTrue(self.build.app.exists())

    def test_clean_only_removes_owned_output_and_unregisters_exact_app(self):
        self.owned()
        keep = self.build.parent / 'keep'
        keep.write_text('unrelated cache')
        with patch.object(dev.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '', '')) as run:
            self.build.clean()
        self.assertFalse(self.build.directory.exists())
        self.assertTrue(keep.exists())
        self.assertEqual(run.call_args_list[-1].args[0], [dev.REGISTER, '-u', str(self.build.app)])

    def test_failed_build_cleans_partial_bundle(self):
        def fail(*args, **kwargs):
            self.build.app.mkdir()
            raise subprocess.CalledProcessError(1, 'build')
        with patch.object(dev.subprocess, 'run', side_effect=fail), patch.object(self.build, 'active', return_value=False), patch.object(self.build, 'unregister'):
            with self.assertRaises(subprocess.CalledProcessError):
                self.build.build()
        self.assertFalse(self.build.directory.exists())

    def test_run_cleans_after_exit_without_installing(self):
        self.owned()
        with patch.object(self.build, 'build'), patch.object(self.build, 'clean') as clean, patch.object(dev.subprocess, 'Popen') as popen:
            popen.return_value.wait.return_value = 0
            popen.return_value.poll.return_value = 0
            self.build.run()
        clean.assert_called_once()
        self.assertEqual(popen.call_args.args[0], [str(self.build.app / 'Contents/MacOS/LeftOpenApp')])

    def test_unregistered_bundle_is_cleanable_but_other_errors_preserve_output(self):
        self.owned()
        with patch.object(self.build, 'active', return_value=False), patch.object(dev.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'failed: -10814')):
            self.build.clean()
        self.assertFalse(self.build.directory.exists())
        self.owned()
        with patch.object(self.build, 'active', return_value=False), patch.object(dev.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'permission denied')):
            with self.assertRaises(RuntimeError):
                self.build.clean()
        self.assertTrue(self.build.app.exists())
