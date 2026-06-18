import re, datetime, sys, os

html = os.path.join(os.path.dirname(__file__), '..', 'docs', 'index.html')
html = os.path.normpath(html)
ts = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
content = open(html, encoding='utf-8').read()
content = re.sub(r'id="build-date">[^<]+<', f'id="build-date">{ts}<', content)

open(html, 'w', encoding='utf-8').write(content)
print(f'Build date updated: {ts}')
