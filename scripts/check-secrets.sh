#!/bin/sh
set -eu
PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_ROOT"

# Standard-library-only scanner; prints locations and categories, never matched values.
exec python3 - "$@" <<'PY'
import re
import subprocess
import sys
from pathlib import Path

history = sys.argv[1:] == ['--history']
if sys.argv[1:] and not history:
    raise SystemExit('Usage: scripts/check-secrets.sh [--history]')

patterns = {
    'absolute macOS user path': r'/Users/[^/\s]+',
    'Apple development-team identifier': r'(?:HKBRIDGE_|HKRELAY_)?DEVELOPMENT_TEAM\s*=\s*[A-Z0-9]{10}',
    'private key material': r'BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY',
    'hard-coded bearer token': r'Bearer\s+[A-Za-z0-9_-]{24,}',
    'hard-coded bridge token': r'(?:HKBRIDGE|HKRELAY)_TOKEN\s*=\s*[A-Za-z0-9_-]{16,}',
    'common secret assignment': r'''(?i)(?:api[_-]?key|client[_-]?secret|access[_-]?token|password)\s*[:=]\s*['"]?[A-Za-z0-9_./+-]{16,}''',
    'GitHub credential': r'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})',
    'AWS access key': r'(?:AKIA|ASIA)[A-Z0-9]{16}',
    'OpenAI credential': r'sk-(?:proj-)?[A-Za-z0-9_-]{32,}',
}
sensitive_name = re.compile(r'(^|/)(?:credentials\.json|secrets\.json|[^/]+\.(?:secrets|private)\.json|development-api-token|request-history\.json|Local\.xcconfig|\.env(?:\..*)?|[^/]+\.(?:p12|pem|key|cer|mobileprovision|provisionprofile))$')
failed = False
seen = set()

def scan(path, data, label):
    global failed
    if path == 'scripts/check-secrets.sh':
        return
    if sensitive_name.search(path) and not path.endswith('.env.example'):
        print(f'{label}: {path}: potentially private file', file=sys.stderr)
        failed = True
    try:
        text = data.decode('utf-8')
    except UnicodeDecodeError:
        return
    for category, pattern in patterns.items():
        for match in re.finditer(pattern, text):
            line = text.count('\n', 0, match.start()) + 1
            print(f'{label}: {path}:{line}: {category} (value withheld)', file=sys.stderr)
            failed = True

try:
    paths = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z']).decode().split('\0')
    for path in filter(None, paths):
        file = Path(path)
        # A staged deletion is not a publication file; read errors otherwise fail closed.
        if not file.exists():
            continue
        if file.is_symlink():
            print(f'working tree: {path}: review symlink target before publication', file=sys.stderr)
            failed = True
            continue
        scan(path, file.read_bytes(), 'working tree')
    if history:
        commits = subprocess.check_output(['git', 'rev-list', '--all']).decode().split()
        for commit in commits:
            entries = subprocess.check_output(['git', 'ls-tree', '-r', '-z', commit]).split(b'\0')
            for entry in filter(None, entries):
                metadata, name = entry.split(b'\t', 1)
                mode, kind, oid = metadata.split()
                path = name.decode()
                if kind != b'blob' or (oid, path) in seen:
                    continue
                seen.add((oid, path))
                scan(path, subprocess.check_output(['git', 'cat-file', 'blob', oid.decode()]), commit[:8])
        print(f'Checked {len(commits)} reachable commits. Review author identities separately before publication.')
except (OSError, subprocess.CalledProcessError, UnicodeError) as error:
    print(f'Scan could not complete: {type(error).__name__}', file=sys.stderr)
    raise SystemExit(2)
if failed:
    raise SystemExit(1)
print('No common repository disclosures detected. This is not a guarantee that all private information is absent.')
PY
