"""Check local Markdown links and Python syntax without external dependencies."""
import ast
import pathlib
import re
import sys
from urllib.parse import unquote,urlsplit

ROOT=pathlib.Path(__file__).resolve().parents[1]
errors=[]
markdown=list(ROOT.glob('*.md'))+list((ROOT/'docs').rglob('*.md'))
links=0
for path in markdown:
    text=path.read_text('utf8')
    fence=chr(96)*3
    text=re.sub(fence+r'[\s\S]*?'+fence+r'|~~~[\s\S]*?~~~','',text)
    for match in re.finditer(r'!?\[[^\]\n]*\]\((<?[^)\n]+>?)\)',text):
        target=match.group(1).strip('<>').split(' "',1)[0]
        if urlsplit(target).scheme or target.startswith('#'):
            continue
        target=unquote(target.split('#',1)[0])
        if not (path.parent/target).exists():
            errors.append(str(path.relative_to(ROOT))+': broken link '+target)
        links+=1
for directory in (ROOT/'scripts',ROOT/'源码/tools'):
    for path in directory.glob('*.py'):
        try:
            ast.parse(path.read_text('utf8'),filename=str(path))
        except SyntaxError as error:
            errors.append(str(path.relative_to(ROOT))+': '+str(error))
if errors:
    print('\n'.join(errors))
    sys.exit(1)
print(f'Passed: {len(markdown)} Markdown files, {links} local links and Python syntax')
