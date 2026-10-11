// HOME view — the initialisation logic, called by app.js once the views/home.html fragment is mounted.
//   init(ctx) → cleanup()
// The main screen: the user's projects, then every group of the examples catalogue, each entry a tile
// (an icon and a name). A project opens in the playground; an example opens there too, read straight
// from the repository (the #/playground/sample/<file> route).

// The colours of a generated tile, all of them light: the ink on top is the page's own dark, so one ratio
// serves twice — the initials on the tile, and the tile against the page behind it. Measured with the
// WCAG formula: #9ba1ff 8.0, #4ade80 10.8, #fbbf24 11.3, #f87171 6.8, #5b9bff 6.8, #c084fc 7.1,
// #2dd4bf 10.1, #fb923c 8.3. A new colour is measured before it is added.
const TILE_COLORS = ['#9ba1ff', '#4ade80', '#fbbf24', '#f87171', '#5b9bff', '#c084fc', '#2dd4bf', '#fb923c']

// The same name always gets the same colour, so a tile does not change from one visit to the next.
function tileColor(name) {
  let h = 0
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) >>> 0
  return TILE_COLORS[h % TILE_COLORS.length]
}

// The initials: the first character of each of the first two words, so "Ollin Invaders" is OI and
// "Perlin noise (per pixel)" is PN. A name with no word at all falls back to a mark.
function initials(name) {
  const words = name.split(/[^A-Za-z0-9À-ɏ]+/).filter(Boolean)
  const s = words.slice(0, 2).map(w => w[0]).join('').toUpperCase()
  return s || '•'
}

function generatedIcon(name) {
  const icon = document.createElement('span')
  icon.className = 'icon'
  icon.style.background = tileColor(name)
  icon.textContent = initials(name)
  return icon
}

// A tile's picture: an <img> in the icon box. When it cannot be fetched the generated tile takes its place,
// so a missing file is a tile and not a broken image.
function imageIcon(src, name) {
  const icon = document.createElement('span')
  icon.className = 'icon'
  const img = document.createElement('img')
  img.alt = ''
  img.loading = 'lazy'
  img.src = src
  img.addEventListener('error', () => icon.replaceWith(generatedIcon(name)), { once: true })
  icon.appendChild(img)
  return icon
}

function label(tile, name) {
  const text = document.createElement('span')
  text.className = 'name'
  text.textContent = name
  tile.appendChild(text)
}

// The titles of the sections the user folded, kept so that coming back to this screen finds it as it was left.
const FOLDED_KEY = 'ollin-home-folded'
const folded = (() => {
  try { return new Set(JSON.parse(localStorage.getItem(FOLDED_KEY) || '[]')) } catch (_) { return new Set() }
})()

// A section: a heading that folds and unfolds everything under it (the tiles, or the line that says there are none).
function section(title) {
  const sec = document.createElement('details')
  sec.className = 'home-section'
  sec.open = !folded.has(title)
  const head = document.createElement('summary')
  const h = document.createElement('h2')
  h.textContent = title
  head.appendChild(h)
  sec.addEventListener('toggle', () => {
    if (sec.open === !folded.has(title)) return   // the event that follows the initial state changes nothing
    if (sec.open) folded.delete(title)
    else folded.add(title)
    try { localStorage.setItem(FOLDED_KEY, JSON.stringify([...folded])) } catch (_) {}
  })
  const tiles = document.createElement('div')
  tiles.className = 'tiles'
  sec.append(head, tiles)
  return { sec, tiles }
}

export async function init(ctx) {
  // The projects come through the provider, as in the playground: the views know no concrete store.
  const [Prov, Samples] = await Promise.all([
    import('../lib/pg-provider.js?v=' + ctx.v),
    import('../lib/pg-samples.js?v=' + ctx.v),
  ])
  const Store = await Prov.getProvider(ctx.v)
  const page = ctx.root.querySelector('#home-sections')

  // Projects first: the playground's own store, most recent first. The catalogue is fetched meanwhile.
  const catalogue = Samples.fetchCatalog()
  await Store.init()
  const projects = await Store.listProjects()
  const mine = section('My projects')
  for (const p of projects) {
    const tile = document.createElement('button')
    tile.className = 'tile'
    tile.type = 'button'
    tile.append(p.thumbnail ? imageIcon(p.thumbnail, p.name) : generatedIcon(p.name))
    label(tile, p.name)
    tile.addEventListener('click', () => {
      Store.setActiveId(p.id)
      ctx.navigate('playground')
    })
    mine.tiles.appendChild(tile)
  }
  if (!projects.length) {
    const empty = document.createElement('p')
    empty.className = 'empty'
    empty.textContent = 'No project yet. Open an example and press “Create a project”, or start one from the playground’s Project menu.'
    mine.sec.replaceChild(empty, mine.tiles)
  }
  page.appendChild(mine.sec)

  // Then the examples, grouped as the catalogue groups them.
  for (const [name, entries] of Samples.groupCatalog(await catalogue)) {
    const group = section(name)
    for (const entry of entries) {
      const tile = document.createElement('a')
      tile.className = 'tile'
      tile.href = '#/playground/sample/' + entry.file
      tile.append(entry.icon ? imageIcon('samples/' + entry.icon, entry.name) : generatedIcon(entry.name))
      label(tile, entry.name)
      group.tiles.appendChild(tile)
    }
    page.appendChild(group.sec)
  }

  return () => {}
}
