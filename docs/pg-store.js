// Ollin playground — the project storage layer (IndexedDB).
//
// A project is a folder identified by its slug and described by a standard
// `ollin.project.json` manifest at its root (see the MANIFEST field). The same structure is
// mirrored on the GitHub side (the `ollin-projects/<slug>/` repository).
//
// A project's model:
//   {
//     id:        "my-game",        // = the slug; the identity IS the folder name
//     name:      "My game",        // for display
//     entry:     "main.ol",        // the script Run launches
//     files:     { "ollin.project.json": "...", "main.ol": "...", ... },  // text
//     resources: { "assets/logo.png": { b64, ext } },                     // binaries
//     createdAt, updatedAt,        // ms epoch
//     remote:    null              // filled in by the remote sync (repo/branch/sha)
//   }
//
// `ollin.project.json` is a REAL entry of `files` rather than a set of columns of its own, hence
// no divergence between the local store and GitHub, and a self-describing exported project.

const DB_NAME    = 'ollin-playground'
const DB_VERSION = 1
const STORE      = 'projects'
const ACTIVE_KEY = 'ollin-pg-active'    // the active project's id (localStorage)
const LEGACY_KEY = 'ollin-pg-code'      // the old single buffer (migration)

export const MANIFEST = 'ollin.project.json'
const DEFAULT_ENTRY   = 'main.ol'
const DEFAULT_CODE    = 'print("hello world!")\n'

// The sentinel id of the transient project (a sample opened for direct reading), which is never
// persisted. It is the only criterion for "is this a sample?" on the UI side: a persistable flag
// could leak into the database and block renaming and deletion.
export const TRANSIENT_ID = '__exemple__'

// Slug: "My game !" becomes "my-game". ASCII, lower case, hyphens as separators.
export function slugify(name) {
  const s = (name || '')
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')   // strips the accents
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
  return s || 'project'
}

// Opening the database.
let _dbPromise = null

function openDB() {
  if (_dbPromise) return _dbPromise
  _dbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION)
    req.onupgradeneeded = () => {
      const db = req.result
      if (!db.objectStoreNames.contains(STORE)) {
        const os = db.createObjectStore(STORE, { keyPath: 'id' })
        os.createIndex('updatedAt', 'updatedAt')
      }
    }
    req.onsuccess = () => resolve(req.result)
    req.onerror   = () => reject(req.error)
  })
  return _dbPromise
}

function tx(mode) {
  return openDB().then(db => db.transaction(STORE, mode).objectStore(STORE))
}

function reqAsync(request) {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result)
    request.onerror   = () => reject(request.error)
  })
}

// The manifest, regenerated on every save from {id, name, entry}, so the file stays in step with
// the columns and travels as it is to GitHub or an export.
function writeManifest(project) {
  const manifest = { uid: project.id, name: project.name, entry: project.entry }
  project.files[MANIFEST] = JSON.stringify(manifest, null, 2)
}

// Public API.

// Opens the database, and migrates on first launch.
export async function init() {
  await openDB()
  await migrateIfNeeded()
  await healExampleFlags()
}

// Self-repair: a record may have been persisted by mistake with the transient project's
// `example` marker (an old bug), and the UI then treated it as disposable, allowing neither
// renaming nor deletion. We remove the marker; and if the id is the transient sentinel, we give
// it a real slug derived from the name. The reassigned ids are computed BEFORE the write
// transaction — uniqueId opens a transaction of its own, and awaiting it during the rw one would
// close that one (an IndexedDB trap).
async function healExampleFlags() {
  const ro = await tx('readonly')
  const all = await reqAsync(ro.getAll())
  const bad = all.filter(p => p.example || p.id === TRANSIENT_ID)
  if (!bad.length) return
  for (const p of bad) {
    delete p.example
    if (p.id === TRANSIENT_ID) {
      p._oldId = p.id
      p.id = await uniqueId(p.name || 'Untitled')
    }
    writeManifest(p)
  }
  const rw = await tx('readwrite')
  const done = new Promise((resolve, reject) => {
    rw.transaction.oncomplete = () => resolve()
    rw.transaction.onerror    = () => reject(rw.transaction.error)
    rw.transaction.onabort    = () => reject(rw.transaction.error)
  })
  for (const p of bad) {
    const oldId = p._oldId
    delete p._oldId
    if (oldId) {
      rw.add(p)
      rw.delete(oldId)
      if (getActiveId() === oldId) setActiveId(p.id)
    } else {
      rw.put(p)
    }
  }
  await done
}

// Summaries sorted from the most recent to the oldest, without the heavy content.
export async function listProjects() {
  const store = await tx('readonly')
  const all = await reqAsync(store.getAll())
  return all
    .map(p => ({ id: p.id, name: p.name, entry: p.entry, updatedAt: p.updatedAt,
                 fileCount: Object.keys(p.files || {}).length,
                 remote: p.remote || null }))   // the remote link (a slug), for a unified "Open" menu
    .sort((a, b) => b.updatedAt - a.updatedAt)
}

export async function getProject(id) {
  const store = await tx('readonly')
  return (await reqAsync(store.get(id))) || null
}

// Builds an id (a slug) unique in the database from the name: my-game, my-game-2, … `exclude` is
// an id to ignore in the uniqueness test (the project itself, during a rename), so renaming to
// the same slug does not append a -2 suffix.
async function uniqueId(name, exclude) {
  const base = slugify(name)
  const store = await tx('readonly')
  const existing = new Set((await reqAsync(store.getAllKeys())).map(String))
  if (exclude) existing.delete(exclude)
  if (!existing.has(base)) return base
  let n = 2
  while (existing.has(`${base}-${n}`)) n++
  return `${base}-${n}`
}

export async function createProject(name) {
  const now = Date.now()
  const id = await uniqueId(name || 'Untitled')
  const project = {
    id,
    name: name || 'Untitled',
    entry: DEFAULT_ENTRY,
    files: { [DEFAULT_ENTRY]: DEFAULT_CODE },
    resources: {},
    createdAt: now,
    updatedAt: now,
    remote: null,
    dirty: true,   // to be pushed to the remote (the sync flag)
  }
  writeManifest(project)
  const store = await tx('readwrite')
  await reqAsync(store.add(project))
  return project
}

// Upsert: it updates updatedAt and regenerates the manifest.
export async function saveProject(project) {
  project.updatedAt = Date.now()
  if (!project.files) project.files = {}
  if (!project.resources) project.resources = {}
  writeManifest(project)
  const store = await tx('readwrite')
  await reqAsync(store.put(project))
  return project
}

// Renames a project. For consistency the id, being the slug, hence the folder name, FOLLOWS the
// name. If the new name's slug differs, the record is recreated under the new id and the old one
// deleted — on the GitHub side this becomes a folder move on the next push. Returns the updated
// project.
export async function renameProject(id, name) {
  const project = await getProject(id)
  if (!project) return null
  const newId = await uniqueId(name, id)
  project.name = name
  project.dirty = true   // a rename is a change to push: the name, and the remote folder if the slug changes
  if (newId === id) {
    return saveProject(project)          // an unchanged slug means a plain update
  }
  // The folder follows the name: recreate it under the new id, atomically.
  project.id = newId
  project.updatedAt = Date.now()
  writeManifest(project)
  const store = await tx('readwrite')
  await Promise.all([reqAsync(store.add(project)), reqAsync(store.delete(id))])
  if (getActiveId() === id) setActiveId(newId)
  return project
}

export async function deleteProject(id) {
  const store = await tx('readwrite')
  await reqAsync(store.delete(id))
  if (getActiveId() === id) setActiveId(null)
}

// The active project (localStorage).
export function getActiveId() {
  return localStorage.getItem(ACTIVE_KEY) || null
}

export function setActiveId(id) {
  if (id) localStorage.setItem(ACTIVE_KEY, id)
  else localStorage.removeItem(ACTIVE_KEY)
}

// Migration. On first launch, with an empty database, it creates an "Untitled" project from the
// old `ollin-pg-code` buffer if there is one, otherwise from a default piece of code. The old
// localStorage key is kept, as a safety net, and never destroyed.
async function migrateIfNeeded() {
  const store = await tx('readonly')
  const count = await reqAsync(store.count())
  if (count > 0) return

  const legacy = localStorage.getItem(LEGACY_KEY)
  const code = (legacy && legacy.trim()) ? legacy : DEFAULT_CODE
  const now = Date.now()
  const project = {
    id: 'untitled',
    name: 'Untitled',
    entry: DEFAULT_ENTRY,
    files: { [DEFAULT_ENTRY]: code },
    resources: {},
    createdAt: now,
    updatedAt: now,
    remote: null,
    dirty: true,   // to be pushed to the remote (the sync flag)
  }
  writeManifest(project)
  const rw = await tx('readwrite')
  await reqAsync(rw.add(project))
  setActiveId(project.id)
}
