// ── Ollin Playground — couche de stockage des projets (IndexedDB) ───────────
//
// Un projet = un dossier identifié par son slug, décrit par un manifeste
// standard `ollin.project.json` à sa racine (voir le champ MANIFEST). Cette
// même structure est miroir côté GitHub (repo `ollin-projects/<slug>/`).
//
// Modèle d'un projet :
//   {
//     id:        "mon-jeu",        // = slug (Option A : identité = nom du dossier)
//     name:      "Mon jeu",        // affichage
//     entry:     "main.ol",        // script lancé par Run
//     files:     { "ollin.project.json": "...", "main.ol": "...", ... },  // texte
//     resources: { "assets/logo.png": { b64, ext } },                     // binaires
//     createdAt, updatedAt,        // ms epoch
//     remote:    null              // rempli en Phase 2 (repo/branch/sha)
//   }
//
// `ollin.project.json` est un VRAI fichier de `files` (pas des colonnes à
// part) → zéro divergence entre local et GitHub, projet exporté autodescriptif.

const DB_NAME    = 'ollin-playground'
const DB_VERSION = 1
const STORE      = 'projects'
const ACTIVE_KEY = 'ollin-pg-active'    // id du projet actif (localStorage)
const LEGACY_KEY = 'ollin-pg-code'      // ancien buffer unique (migration)

export const MANIFEST = 'ollin.project.json'
const DEFAULT_ENTRY   = 'main.ol'
const DEFAULT_CODE    = 'print("hello world!")\n'

// ── slug ────────────────────────────────────────────────────────────────────
// "Mon jeu !" → "mon-jeu". ASCII, minuscules, séparateurs = tirets.
export function slugify(name) {
  const s = (name || '')
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')   // retire les accents
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
  return s || 'projet'
}

// ── ouverture de la base ────────────────────────────────────────────────────
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

// ── manifeste ────────────────────────────────────────────────────────────────
// Régénéré à chaque sauvegarde depuis {id, name, entry} → le fichier reste en
// phase avec les colonnes, et voyage tel quel vers GitHub / export.
function writeManifest(project) {
  const manifest = { uid: project.id, name: project.name, entry: project.entry }
  project.files[MANIFEST] = JSON.stringify(manifest, null, 2)
}

// ── API publique ─────────────────────────────────────────────────────────────

// Ouvre la base et effectue la migration au premier lancement.
export async function init() {
  await openDB()
  await migrateIfNeeded()
}

// Résumés triés du plus récent au plus ancien (sans le contenu lourd).
export async function listProjects() {
  const store = await tx('readonly')
  const all = await reqAsync(store.getAll())
  return all
    .map(p => ({ id: p.id, name: p.name, entry: p.entry, updatedAt: p.updatedAt,
                 fileCount: Object.keys(p.files || {}).length }))
    .sort((a, b) => b.updatedAt - a.updatedAt)
}

export async function getProject(id) {
  const store = await tx('readonly')
  return (await reqAsync(store.get(id))) || null
}

// Génère un id (slug) unique en base à partir du nom : mon-jeu, mon-jeu-2, …
// `exclude` : id à ignorer dans le test d'unicité (le projet lui-même, lors d'un
// renommage) → renommer vers le même slug ne produit pas de suffixe -2.
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
  const id = await uniqueId(name || 'Sans titre')
  const project = {
    id,
    name: name || 'Sans titre',
    entry: DEFAULT_ENTRY,
    files: { [DEFAULT_ENTRY]: DEFAULT_CODE },
    resources: {},
    createdAt: now,
    updatedAt: now,
    remote: null,
  }
  writeManifest(project)
  const store = await tx('readwrite')
  await reqAsync(store.add(project))
  return project
}

// Upsert : met à jour updatedAt et régénère le manifeste.
export async function saveProject(project) {
  project.updatedAt = Date.now()
  if (!project.files) project.files = {}
  if (!project.resources) project.resources = {}
  writeManifest(project)
  const store = await tx('readwrite')
  await reqAsync(store.put(project))
  return project
}

// Renomme un projet. Cohérence Option A : l'id/slug (= nom du dossier) SUIT le
// nom. Si le slug du nouveau nom diffère, l'enregistrement est recréé sous le
// nouvel id (l'ancien est supprimé) — côté GitHub cela se traduira par un
// déplacement du dossier au prochain push (Phase 2). Renvoie le projet à jour.
export async function renameProject(id, name) {
  const project = await getProject(id)
  if (!project) return null
  const newId = await uniqueId(name, id)
  project.name = name
  if (newId === id) {
    return saveProject(project)          // slug inchangé : simple mise à jour
  }
  // Le dossier suit le nom : recréer sous le nouvel id, atomiquement.
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

// ── projet actif (localStorage) ───────────────────────────────────────────────
export function getActiveId() {
  return localStorage.getItem(ACTIVE_KEY) || null
}

export function setActiveId(id) {
  if (id) localStorage.setItem(ACTIVE_KEY, id)
  else localStorage.removeItem(ACTIVE_KEY)
}

// ── migration ─────────────────────────────────────────────────────────────────
// Au premier lancement (base vide) : crée un projet « Sans titre » à partir de
// l'ancien buffer `ollin-pg-code` s'il existe, sinon d'un code par défaut.
// L'ancienne clé localStorage est conservée (sécurité, non détruite).
async function migrateIfNeeded() {
  const store = await tx('readonly')
  const count = await reqAsync(store.count())
  if (count > 0) return

  const legacy = localStorage.getItem(LEGACY_KEY)
  const code = (legacy && legacy.trim()) ? legacy : DEFAULT_CODE
  const now = Date.now()
  const project = {
    id: 'sans-titre',
    name: 'Sans titre',
    entry: DEFAULT_ENTRY,
    files: { [DEFAULT_ENTRY]: code },
    resources: {},
    createdAt: now,
    updatedAt: now,
    remote: null,
  }
  writeManifest(project)
  const rw = await tx('readwrite')
  await reqAsync(rw.add(project))
  setActiveId(project.id)
}
