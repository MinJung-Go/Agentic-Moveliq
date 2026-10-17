import pathlib
import os
import subprocess
import sys
import tempfile
import unittest
from dependency import inference_dependency


class DependencyTests(unittest.TestCase):
    def read(self, fields):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'project.yml'
            path.write_text('packages:\n  MiloInference:\n' + fields + '\nsettings:\n', encoding='utf-8')
            return inference_dependency(path)

    def test_current_project_uses_full_remote_pin(self):
        pin = inference_dependency()
        self.assertEqual(pin['url'], 'https://github.com/MinJung-Go/MiloInference.git')
        self.assertEqual(len(pin['revision']), 40)

    def test_floating_or_missing_revision_is_rejected(self):
        for revision in ['main', 'v0.1.0', '5c94a02', '']:
            with self.assertRaises(ValueError):
                self.read('    url: https://github.com/MinJung-Go/MiloInference.git\n    revision: ' + revision + '\n')

    def test_utf8_project_is_read_under_legacy_windows_encoding(self):
        # Force GBK for implicit text opens even on UTF-8 hosts, and disable Python UTF-8 mode.
        code = '''
import _pyio
import io
io.open = _pyio.open
_pyio.text_encoding = lambda encoding, stacklevel=2: encoding or 'gbk'
from dependency import inference_dependency
assert len(inference_dependency()['revision']) == 40
'''
        env = dict(os.environ, PYTHONUTF8='0')
        subprocess.run([sys.executable, '-X', 'utf8=0', '-c', code],
                       cwd=pathlib.Path(__file__).parent, env=env, check=True)

    def test_wrong_repo_and_local_override_are_rejected(self):
        revision = '5c94a02bf00d68a1bb3f5a7b2a104bbedd977888'
        with self.assertRaises(ValueError):
            self.read('    url: https://example.com/other.git\n    revision: ' + revision + '\n')
        with self.assertRaises(ValueError):
            self.read('    url: https://github.com/MinJung-Go/MiloInference.git\n    revision: ' + revision + '\n    path: Packages/MiloInference\n')


if __name__ == '__main__':
    unittest.main()
