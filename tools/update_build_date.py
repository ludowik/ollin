import re, datetime, sys, os

html = os.path.join(os.path.dirname(__file__), '..', 'docs', 'index.html')
html = os.path.normpath(html)
ts = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
content = open(html, encoding='utf-8').read()
# remplit le texte de tous les <span data-build-date ...>…</span> (hero + sidebar)
content = re.sub(r'(data-build-date[^>]*>)[^<]*<', rf'\g<1>{ts}<', content)

open(html, 'w', encoding='utf-8').write(content)
print(f'Build date updated: {ts}')
