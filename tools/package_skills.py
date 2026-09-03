"""Build both install archives from an explicit list of distributable files."""
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
COMMON = ['INSTALLATION.md', 'SKILL.md', 'reference/protocole.md',
          'scripts/attendre.ps1', 'scripts/duo.sh', 'scripts/run_metadata.py']

def build():
    for side in ('claude-code', 'codex'):
        files = COMMON + (['reference/codex-cli.md'] if side == 'claude-code'
                          else ['agents/openai.yaml'])
        source = ROOT / f'you-can-install-{side}'
        target = ROOT / f'INSTALL-{side}.zip'
        with ZipFile(target, 'w', compression=ZIP_DEFLATED) as archive:
            for name in sorted(files):
                info = ZipInfo('duo-claude-codex/' + name, (2026, 9, 3, 0, 0, 0))
                info.compress_type = ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                archive.writestr(info, (source / name).read_bytes())
        with ZipFile(target) as archive:
            assert archive.testzip() is None
            for name in files:
                assert archive.read('duo-claude-codex/' + name) == (source / name).read_bytes()
        print(f'{target.name}: {len(files)} fichiers verifies')

if __name__ == '__main__':
    build()
