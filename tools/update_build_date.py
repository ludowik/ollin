import re, datetime, os, glob

ts = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
docs = os.path.normpath(os.path.join(os.path.dirname(__file__), '..', 'docs'))

# The <span data-build-date>…</span> elements (hero and sidebar) live in the view fragments
# since the move to a single page, so we sweep index.html AND docs/views/*.html.
targets = [os.path.join(docs, 'index.html')] + glob.glob(os.path.join(docs, 'views', '*.html'))

updated = 0
for html in targets:
    if not os.path.exists(html):
        continue
    content = open(html, encoding='utf-8').read()
    new = re.sub(r'(data-build-date[^>]*>)[^<]*<', rf'\g<1>{ts}<', content)
    if new != content:
        open(html, 'w', encoding='utf-8').write(new)
        updated += 1

print(f'Build date updated: {ts} ({updated} fichier(s))')
