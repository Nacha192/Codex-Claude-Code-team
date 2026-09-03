"""Regression tests with a fake Codex process: no model calls or network."""
import concurrent.futures
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get('BASH_BIN') or shutil.which('bash')
if not BASH and os.name == 'nt':
    git = Path(shutil.which('git')).resolve()
    BASH = str(git.parent.parent / 'bin/bash.exe')

STUB = '''#!/usr/bin/env bash
out=""
while [ $# -gt 0 ]; do
  case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac
done
echo 'session id: 12345678-1234-1234-1234-123456789abc'
echo 'UNRECOGNIZABLE_PRIVATE_VALUE_8126'
echo 'TOKEN=FAKE_TEST_SECRET_123456' >&2
case "${FAKE_MODE:-ok}" in
  missing) exit 0 ;;
  failure) echo 'Error: usage limit TOKEN=FAKE_TEST_SECRET_123456'; exit 42 ;;
esac
printf 'Reponse finale propre.\\n' > "$out"
'''

class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='duo-test-')
        self.path = Path(self.tmp.name)
        self.stub = self.path / 'fake-codex.sh'
        self.stub.write_text(STUB, encoding='utf-8', newline='\n')
        self.stub.chmod(0o700)
        self.env = dict(os.environ, CODEX_BIN=self.stub.as_posix(),
                        DUO_RACINE=self.path.as_posix(), PYTHONUTF8='1')
        self.env.pop('DUO_QUI', None)
        self.script = ROOT / 'you-can-install-claude-code/scripts/duo.sh'
        self.git('init', '-q')

    def tearDown(self):
        self.tmp.cleanup()

    def git(self, *args):
        return subprocess.run(['git', '-C', str(self.path), *args],
                              capture_output=True, text=True, check=True).stdout

    def run_duo(self, *args, code=0, **env):
        result = subprocess.run([BASH, self.script.as_posix(), *args],
                                cwd=self.path, env=dict(self.env, **env),
                                capture_output=True, text=True, encoding='utf-8',
                                errors='replace', timeout=30)
        self.assertEqual(result.returncode, code, result.stderr)
        return result

    def test_both_versions_and_syntax(self):
        other = ROOT / 'you-can-install-codex/scripts'
        for name in ('duo.sh', 'run_metadata.py', 'attendre.ps1'):
            self.assertEqual((self.script.parent / name).read_bytes(), (other / name).read_bytes())
        subprocess.run([BASH, '-n', str(self.script)], check=True)

    def test_upgrade_existing_ignore_and_idempotence(self):
        duo = self.path / '.duo'
        duo.mkdir()
        (duo / '.gitignore').write_text('.dernier-run.log\n!MISSION.md\n!etat.json\n')
        self.run_duo('init', 'mission')
        first = (duo / '.gitignore').read_bytes()
        self.run_duo('init', 'autre mission')
        self.assertEqual(first, (duo / '.gitignore').read_bytes())
        self.assertIn('mission', (duo / 'MISSION.md').read_text())
        for name in ('.run-0003.log', 'MISSION.md', 'etat.json', 'fil.partiel',
                     'echanges/0001-test.md', '.reponse-0001.partiel'):
            self.assertTrue(self.git('check-ignore', '--', '.duo/' + name).strip())

    def test_write_without_init_is_protected(self):
        self.run_duo('ecrire', '--de', 'codex', 'bonjour')
        self.assertTrue(self.git('check-ignore', '--', '.duo/echanges/0001-codex-proposition.md'))

    def test_tracked_channel_refused_without_deletion(self):
        duo = self.path / '.duo'
        duo.mkdir()
        old = duo / '.run-old.log'
        old.write_text('synthetic old log')
        self.git('add', '--', '.duo')
        self.run_duo('envoyer', 'test', code=1)
        self.assertEqual(old.read_text(), 'synthetic old log')
        self.assertFalse((duo / 'echanges').exists())

    def test_no_raw_output_persisted_success_and_resume(self):
        self.run_duo('init', 'test')
        self.run_duo('envoyer', 'question')
        self.run_duo('envoyer', 'suite')
        data = json.loads((self.path / '.duo/etat.json').read_text())
        self.assertEqual(data['session_codex'], '12345678-1234-1234-1234-123456789abc')
        self.assertEqual(data['dernier_tour'], '0004')
        responses = list((self.path / '.duo/echanges').glob('*-reponse.md'))
        self.assertEqual(len(responses), 2)
        self.assertTrue(all('Reponse finale propre.' in p.read_text() for p in responses))
        self.assert_no_raw_output()

    def assert_no_raw_output(self):
        for p in (self.path / '.duo').rglob('*'):
            if p.is_file():
                text = p.read_text(encoding='utf-8')
                self.assertNotIn('UNRECOGNIZABLE_PRIVATE_VALUE', text)
                self.assertNotIn('FAKE_TEST_SECRET', text)

    def test_missing_output_is_failure_not_log_copy(self):
        self.run_duo('envoyer', 'question', code=3, FAKE_MODE='missing')
        self.assertEqual(len(list((self.path / '.duo/echanges').glob('*.md'))), 1)
        self.assert_no_raw_output()

    def test_failure_retains_only_fixed_diagnostic(self):
        self.run_duo('envoyer', 'question', code=3, FAKE_MODE='failure')
        self.assertFalse(list((self.path / '.duo/echanges').glob('*-reponse.md')))
        self.assert_no_raw_output()
        self.assertIn('Error: usage limit', (self.path / '.duo/.run-0002.log').read_text())

    def test_invalid_options_do_not_write_messages(self):
        self.run_duo('ecrire', '--type', code=1)
        self.run_duo('ecrire', '--type', '../outside', 'message', code=1)
        self.run_duo('bonjour', '../outside', 'message', code=1)
        self.assertFalse(list((self.path / '.duo').rglob('*.md')))

    def test_state_lock_timeout_preserves_state(self):
        self.run_duo('init', 'test')
        state = self.path / '.duo/etat.json'
        before = state.read_bytes()
        (self.path / '.duo/etat.json.verrou').mkdir()
        self.run_duo('ecrire', 'message', code=1)
        self.assertEqual(state.read_bytes(), before)

    def test_concurrent_messages_are_unique(self):
        self.run_duo('init', 'test')
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(lambda n: self.run_duo('ecrire', f'message {n}'), range(8)))
        messages = list((self.path / '.duo/echanges').glob('*.md'))
        self.assertEqual(len(messages), 8)
        state = json.loads((self.path / '.duo/etat.json').read_text())
        self.assertEqual(state['dernier_tour'], '0008')

    def test_html_escapes_mission(self):
        self.run_duo('init', '<script>test</script>&')
        self.run_duo('fil')
        html = (self.path / '.duo/fil.html').read_text()
        self.assertNotIn('<script>test', html)
        self.assertIn('&lt;script&gt;test&lt;/script&gt;&amp;', html)

if __name__ == '__main__':
    unittest.main(verbosity=2)
