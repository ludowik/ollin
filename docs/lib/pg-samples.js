// The catalogue of examples, samples/index.json: the one link between the site's menus and the files
// of docs/samples. The playground's "Open an example" menu and the home screen both read it here.

// The entries as listed — {group, name, file[, icon]} — or `fallback` when the file cannot be read.
export function fetchCatalog(fallback = []) {
  return fetch('samples/index.json', { cache: 'no-cache' }).then(r => r.json()).catch(() => fallback)
}

// The groups, in the order of their first appearance in index.json: that order IS the catalogue's,
// with no second list to keep in step. An entry with no group falls into "Other".
export function groupCatalog(entries) {
  const groups = new Map()
  for (const ex of entries) {
    const g = ex.group || 'Other'
    if (!groups.has(g)) groups.set(g, [])
    groups.get(g).push(ex)
  }
  return groups
}
