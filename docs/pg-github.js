// ── Ollin Playground — provider GitHub (dépôt ollin-projects) ───────────────
//
// Synchronise les projets avec un dépôt GitHub public `ollin-projects` (un
// dossier par projet, miroir exact du modèle local de pg-store.js). Auth par
// Personal Access Token (fine-grained, portée Contents sur ce repo) collé une
// fois et rangé dans le localStorage du navigateur.
//
// Étape 2.1 = LECTURE : auth, ensureRepo, listRemoteProjects, pullProject.
// (L'écriture — pushProject via Git Data API — arrive à l'étape 2.2.)
//
// api.github.com renvoie CORS ouvert pour les appels REST authentifiés → tout
// marche depuis le navigateur, sans serveur intermédiaire.

const API        = 'https://api.github.com'
const REPO       = 'ollin-projects'
const TOKEN_KEY  = 'ollin-gh-token'
const MANIFEST   = 'ollin.project.json'
const IMAGE_EXTS = new Set(['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'])

// ── token ─────────────────────────────────────────────────────────────────
export function setToken(t) {
  if (t) localStorage.setItem(TOKEN_KEY, t.trim())
  else localStorage.removeItem(TOKEN_KEY)
  _login = null   // invalider le cache d'identité
}
export function getToken() {
  return localStorage.getItem(TOKEN_KEY) || null
}
export function clearToken() {
  localStorage.removeItem(TOKEN_KEY)
  _login = null
}
export function isConnected() {
  return !!getToken()
}

// ── requêtes bas niveau ───────────────────────────────────────────────────
async function gh(path, { method = 'GET', body = null } = {}) {
  const token = getToken()
  if (!token) throw new Error('Non connecté à GitHub (token manquant)')
  return fetch(API + path, {
    method,
    headers: {
      'Authorization': 'Bearer ' + token,
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  })
}

async function ghJson(path, opts) {
  const res = await gh(path, opts)
  if (!res.ok) {
    let msg = String(res.status)
    try { const e = await res.json(); if (e && e.message) msg = res.status + ' — ' + e.message } catch (_) {}
    throw new Error('GitHub ' + msg)
  }
  return res.status === 204 ? null : res.json()
}

// ── base64 ↔ UTF-8 ─────────────────────────────────────────────────────────
function decodeUtf8(b64) {
  const bin = atob((b64 || '').replace(/\n/g, ''))
  const bytes = Uint8Array.from(bin, c => c.charCodeAt(0))
  return new TextDecoder().decode(bytes)
}

// ── identité ────────────────────────────────────────────────────────────────
let _login = null
export async function getUser() {
  const u = await ghJson('/user')
  _login = u.login
  return u
}
async function owner() {
  return _login || (await getUser()).login
}

// ── repo ──────────────────────────────────────────────────────────────────
// Renvoie le repo ; le crée (public, auto-init) s'il n'existe pas encore.
export async function ensureRepo() {
  const login = await owner()
  const res = await gh(`/repos/${login}/${REPO}`)
  if (res.ok) return res.json()
  if (res.status === 404) {
    return ghJson('/user/repos', {
      method: 'POST',
      body: { name: REPO, private: false, auto_init: true, description: 'Projets Ollin (playground)' },
    })
  }
  let msg = String(res.status)
  try { const e = await res.json(); if (e && e.message) msg = res.status + ' — ' + e.message } catch (_) {}
  throw new Error('GitHub ' + msg)
}

// Arbre complet de la branche par défaut (login + branch + entrées).
async function fullTree() {
  const login = await owner()
  const repo = await ghJson(`/repos/${login}/${REPO}`)
  const branch = repo.default_branch || 'main'
  const t = await ghJson(`/repos/${login}/${REPO}/git/trees/${branch}?recursive=1`)
  return { login, branch, tree: t.tree || [] }
}

// ── liste des projets distants ───────────────────────────────────────────────
// Un projet = un dossier racine contenant `ollin.project.json`.
export async function listRemoteProjects() {
  const { login, tree } = await fullTree()
  const out = []
  for (const e of tree) {
    if (e.type !== 'blob' || !/^[^/]+\/ollin\.project\.json$/.test(e.path)) continue
    const slug = e.path.split('/')[0]
    let name = slug
    try {
      const blob = await ghJson(`/repos/${login}/${REPO}/git/blobs/${e.sha}`)
      const m = JSON.parse(decodeUtf8(blob.content))
      name = m.name || slug
    } catch (_) {}
    out.push({ slug, name })
  }
  return out
}

// ── pull d'un projet ─────────────────────────────────────────────────────────
// Reconstruit l'objet projet local à partir du dossier `<slug>/` du repo.
// Distinction script/ressource par extension (image → resources, sinon files).
export async function pullProject(slug) {
  const { login, branch, tree } = await fullTree()
  const prefix = slug + '/'
  const files = {}, resources = {}
  for (const e of tree) {
    if (e.type !== 'blob' || !e.path.startsWith(prefix)) continue
    const rel = e.path.slice(prefix.length)
    const blob = await ghJson(`/repos/${login}/${REPO}/git/blobs/${e.sha}`)
    const b64 = (blob.content || '').replace(/\n/g, '')
    const ext = rel.includes('.') ? rel.split('.').pop().toLowerCase() : ''
    if (IMAGE_EXTS.has(ext)) resources[rel] = { b64, ext }
    else files[rel] = decodeUtf8(b64)
  }
  let name = slug, entry = 'main.ol'
  try {
    const m = JSON.parse(files[MANIFEST] || '{}')
    name = m.name || slug
    entry = m.entry || entry
  } catch (_) {}
  const now = Date.now()
  return { id: slug, name, entry, files, resources, remote: { repo: REPO, branch, slug }, createdAt: now, updatedAt: now }
}

// ── push d'un projet ─────────────────────────────────────────────────────────
// Rend le dossier `<slug>/` du repo identique au projet local, en UN commit
// atomique (Git Data API). Répercute ajouts, modifs ET suppressions ; si le
// projet a été renommé (remote.slug ≠ slug), supprime aussi l'ancien dossier.
// Renseigne project.remote = { repo, branch, slug, commit } et le renvoie.
export async function pushProject(project, message) {
  const login = await owner()
  const repoInfo = await ghJson(`/repos/${login}/${REPO}`)
  const branch = repoInfo.default_branch || 'main'
  const slug = project.id
  const base = `/repos/${login}/${REPO}`

  // 1–2. tête courante → arbre de base
  const ref = await ghJson(`${base}/git/ref/heads/${branch}`)
  const baseSha = ref.object.sha
  const baseCommit = await ghJson(`${base}/git/commits/${baseSha}`)
  const baseTree = baseCommit.tree.sha

  // 3. blobs (scripts en utf-8, ressources en base64) → entrées d'arbre
  const tree = []
  for (const rel in (project.files || {})) {
    const blob = await ghJson(`${base}/git/blobs`, { method: 'POST', body: { content: project.files[rel], encoding: 'utf-8' } })
    tree.push({ path: `${slug}/${rel}`, mode: '100644', type: 'blob', sha: blob.sha })
  }
  for (const rel in (project.resources || {})) {
    const blob = await ghJson(`${base}/git/blobs`, { method: 'POST', body: { content: project.resources[rel].b64, encoding: 'base64' } })
    tree.push({ path: `${slug}/${rel}`, mode: '100644', type: 'blob', sha: blob.sha })
  }

  // 4. suppressions : fichiers distants (sous le slug courant + l'ancien slug si
  //    renommage) qui n'existent plus localement → sha:null.
  const desired = new Set(tree.map(t => t.path))
  const scan = new Set([slug])
  const oldSlug = project.remote && project.remote.slug
  if (oldSlug && oldSlug !== slug) scan.add(oldSlug)
  const { tree: remoteTree } = await fullTree()
  for (const e of remoteTree) {
    if (e.type !== 'blob') continue
    if (!scan.has(e.path.split('/')[0])) continue
    if (!desired.has(e.path)) tree.push({ path: e.path, mode: '100644', type: 'blob', sha: null })
  }

  // 5–7. nouvel arbre → commit → avance la branche
  const newTree = await ghJson(`${base}/git/trees`, { method: 'POST', body: { base_tree: baseTree, tree } })
  const commit = await ghJson(`${base}/git/commits`, {
    method: 'POST',
    body: { message: message || `ollin: ${project.name}`, tree: newTree.sha, parents: [baseSha] },
  })
  await ghJson(`${base}/git/refs/heads/${branch}`, { method: 'PATCH', body: { sha: commit.sha } })

  project.remote = { repo: REPO, branch, slug, commit: commit.sha }
  return project.remote
}
