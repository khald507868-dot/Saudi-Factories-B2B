from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
errors = []
for page in sorted(root.glob('*.html')):
    text = page.read_text(encoding='utf-8')
    for i, match in enumerate(re.finditer(r'<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)</script>', text, re.I), 1):
        with tempfile.NamedTemporaryFile(
            mode='w', suffix='.js', encoding='utf-8', delete=False
        ) as handle:
            handle.write(match.group(1))
            temp = Path(handle.name)
        try:
            result = subprocess.run(['node', '--check', str(temp)], capture_output=True, text=True)
        finally:
            temp.unlink(missing_ok=True)
        if result.returncode:
            errors.append(f'{page.name}: inline script {i}: {result.stderr.strip()}')
for sql in sorted((root / 'supabase/migrations').glob('*.sql')):
    text = sql.read_text(encoding='utf-8')
    if text.count('$fn$') % 2 or text.count('$do$') % 2:
        errors.append(f'{sql.name}: unbalanced dollar quotes')
    if 'public.orders.updated_at' in text:
        errors.append(f'{sql.name}: invalid qualified column reference')
if errors:
    print('\n'.join(errors))
    sys.exit(1)
print('Static validation passed')
