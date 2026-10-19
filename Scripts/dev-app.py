#!/usr/bin/env python3
"""One local test bundle, outside application search; never installs into /Applications."""
import argparse
import fcntl
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
REGISTER = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
MARKER = '.leftopen-local-build'


class LocalBuild:
    def __init__(self, repo=ROOT):
        self.repo = repo
        self.parent = repo / '.build'
        self.directory = self.parent / 'local-app.noindex'
        self.app = self.directory / 'LeftOpen.app'

    def check_paths(self):
        for path in (self.parent, self.directory, self.app):
            if path.is_symlink():
                raise RuntimeError(f'Refusing a symlink at {path}')
        if self.directory.exists():
            marker = self.directory / MARKER
            if marker.is_symlink() or not marker.is_file() or marker.read_text() != 'leftopen-local-build-v1\n':
                raise RuntimeError(f'Unrecognized build directory; left untouched: {self.directory}')

    def active(self):
        result = subprocess.run(['/bin/ps', '-axo', 'comm='], check=True, capture_output=True, text=True)
        prefix = str(self.app.resolve()) + '/'
        return any(line.strip().startswith(prefix) for line in result.stdout.splitlines())

    def unregister(self):
        if (self.app / 'Contents/Info.plist').is_file():
            result = subprocess.run([REGISTER, '-u', str(self.app)], capture_output=True, text=True)
            # kLSApplicationNotFoundErr: a noindex build that was never launched is not registered.
            if result.returncode and '-10814' not in result.stderr:
                raise RuntimeError('Could not unregister the test app. Output retained; retry clean.')

    def clean(self):
        self.check_paths()
        if not self.directory.exists():
            return
        if self.active():
            raise RuntimeError('The test app or its bundled runtime is still running. Quit it before cleaning; no process was stopped.')
        self.unregister()
        shutil.rmtree(self.directory)

    def build(self):
        self.clean()
        self.directory.mkdir(parents=True)
        (self.directory / MARKER).write_text('leftopen-local-build-v1\n')
        env = dict(os.environ, LEFTOPEN_OUTPUT_DIR=str(self.directory),
                   LEFTOPEN_BUNDLE_ID='app.leftopen.local-test', LEFTOPEN_APP_DISPLAY_NAME='LeftOpen Test')
        try:
            subprocess.run(['/bin/zsh', str(self.repo / 'Scripts/build-app.sh')], cwd=self.repo, env=env, check=True)
            self.unregister()
        except BaseException:
            self.clean()
            raise
        print(f'Local test app: {self.app}\nRun: python3 Scripts/dev-app.py run\nClean: python3 Scripts/dev-app.py clean')

    def run(self):
        self.build()
        # Run the exact binary, not `open`: do not ask Launch Services to register another app.
        child = None
        try:
            child = subprocess.Popen([str(self.app / 'Contents/MacOS/LeftOpenApp')], cwd=self.repo)
            try:
                result = child.wait()
            except KeyboardInterrupt:
                child.terminate()
                child.wait(timeout=10)
                raise
            if result:
                raise RuntimeError(f'Test app exited with status {result}')
        finally:
            if child is None or child.poll() is not None:
                self.clean()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['build', 'run', 'clean'])
    args = parser.parse_args()
    build = LocalBuild()
    try:
        build.check_paths()
        build.parent.mkdir(exist_ok=True)
        lock = build.parent / '.local-app.lock'
        if lock.is_symlink():
            raise RuntimeError('Refusing a symlinked build lock.')
        with lock.open('a') as handle:
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RuntimeError('A local build or test run is already active. Quit it first.') from None
            getattr(build, args.action)()
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
