"""A changing file must not extend the timeout or appear falsely stable."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
SHELL = shutil.which('pwsh') or shutil.which('powershell')

@unittest.skipUnless(SHELL, 'PowerShell absent')
class WaitTests(unittest.TestCase):
    def test_continuously_rewritten_file_times_out(self):
        with tempfile.TemporaryDirectory() as temp:
            stop = threading.Event()
            path = Path(temp) / '0001-codex-resultat.md'
            def writer():
                n = 0
                while not stop.wait(0.05):
                    path.write_text(f'{n % 10}')
                    n += 1
            thread = threading.Thread(target=writer)
            thread.start()
            try:
                started = time.monotonic()
                result = subprocess.run([SHELL, '-NoProfile', '-File',
                    str(ROOT / 'you-can-install-claude-code/scripts/attendre.ps1'),
                    '-Chemin', temp, '-Delai', '2', '-Pas', '1'],
                    capture_output=True, timeout=7)
                self.assertEqual(result.returncode, 1, result.stdout)
                self.assertLess(time.monotonic() - started, 6)
                self.assertEqual(result.stdout, b'')
            finally:
                stop.set()
                thread.join()

if __name__ == '__main__':
    unittest.main(verbosity=2)
