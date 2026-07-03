// ── Ollin Playground — provider GitHub (dépôt de projets paramétrable) ──────
//
// Synchronise les projets avec un dépôt GitHub (un dossier par projet, miroir
// exact du modèle local de pg-store.js). Auth par Personal Access Token
// (fine-grained, portée Contents) collé une fois et rangé dans le localStorage.
//
// Le dépôt cible est paramétrable (getRepo/setRepo, défaut `ollin-projects`) :
//   - "mon-repo"        → sous le compte de l'utilisateur authentifié
//   - "owner/mon-repo"  → dépôt d'une orga / partagé (non créé automatiquement)
//
// api.github.com renvoie CORS ouvert pour les appels REST authentifiés → tout
// marche depuis le navigateur, sans serveur intermédiaire.

const API          = 'https://api.github.com'
const TOKEN_KEY    = 'ollin-gh-token'
const REPO_KEY     = 'ollin-gh-repo'
const DEFAULT_REPO = 'ollin-projects'
const MANIFEST     = 'ollin.project.json'
const IMAGE_EXTS   = new Set(['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'])

// ── token ─────────────────────────────────────────────────────────────────
export function setToken(t) {
  if (t) localStorage.setItem(TOKEN_KEY, t.trim())
  else localStorage.removeItem(TOKEN_KEY)
  _login = null
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

// ── dépôt cible (paramétrable) ──────────────────────────────────────────────
export function getRepo() {
  return localStorage.getItem(REPO_KEY) || DEFAULT_REPO
}
export function setRepo(v) {
  const s = (v || '').trim()
  if (s && s !== DEFAULT_REPO) localStorage.setItem(REPO_KEY, s)
  else localStorage.removeItem(REPO_KEY)
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
function encodeUtf8(str) {
  const bytes = new TextEncoder().encode(str)
  let bin = ''
  for (const b of bytes) bin += String.fromCharCode(b)
  return btoa(bin)
}

// sha du dossier <slug> dans un arbre récursif (empreinte de son contenu) ; null
// si le dossier n'existe pas. Sert au garde-fou de conflit / fraîcheur.
function slugTreeSha(tree, slug) {
  const e = tree.find(x => x.type === 'tree' && x.path === slug)
  return e ? e.sha : null
}

// ── identité + cible ─────────────────────────────────────────────────────────
let _login = null
export async function getUser() {
  const u = await ghJson('/user')
  _login = u.login
  return u
}
async function login() {
  return _login || (await getUser()).login
}

// Résout le dépôt cible : { owner, repo, mine, base }.
// mine=true si le dépôt appartient à l'utilisateur authentifié (créable).
async function ctx() {
  const val = getRepo()
  if (val.includes('/')) {
    const [owner, repo] = val.split('/')
    return { owner, repo, mine: (owner === (await login())), base: `/repos/${owner}/${repo}` }
  }
  const owner = await login()
  return { owner, repo: val, mine: true, base: `/repos/${owner}/${val}` }
}

// ── repo ──────────────────────────────────────────────────────────────────
// Renvoie le dépôt ; le crée (public, auto-init) s'il n'existe pas ET qu'il
// appartient à l'utilisateur. Chez un autre propriétaire : erreur explicite.
export async function ensureRepo() {
  const { owner, repo, mine, base } = await ctx()
  const res = await gh(base)
  if (res.ok) return res.json()
  if (res.status === 404) {
    if (!mine) throw new Error(`Dépôt ${owner}/${repo} introuvable — création impossible chez un autre propriétaire.`)
    return ghJson('/user/repos', {
      method: 'POST',
      body: { name: repo, private: false, auto_init: true, description: 'Projets Ollin (playground)' },
    })
  }
  let msg = String(res.status)
  try { const e = await res.json(); if (e && e.message) msg = res.status + ' — ' + e.message } catch (_) {}
  throw new Error('GitHub ' + msg)
}

// Arbre complet de la branche par défaut (+ contexte du dépôt).
async function fullTree() {
  const { owner, repo, base } = await ctx()
  const info = await ghJson(base)
  const branch = info.default_branch || 'main'
  const res = await gh(`${base}/git/trees/${branch}?recursive=1`)
  if (!res.ok) {
    if (res.status === 409 || res.status === 404) return { owner, repo, base, branch, tree: [] }  // dépôt vide
    let msg = String(res.status)
    try { const e = await res.json(); if (e && e.message) msg = res.status + ' — ' + e.message } catch (_) {}
    throw new Error('GitHub ' + msg)
  }
  const t = await res.json()
  return { owner, repo, base, branch, tree: t.tree || [] }
}

// ── liste des projets distants ───────────────────────────────────────────────
export async function listRemoteProjects() {
  const { base, tree } = await fullTree()
  const out = []
  for (const e of tree) {
    if (e.type !== 'blob' || !/^[^/]+\/ollin\.project\.json$/.test(e.path)) continue
    const slug = e.path.split('/')[0]
    let name = slug
    try {
      const blob = await ghJson(`${base}/git/blobs/${e.sha}`)
      const m = JSON.parse(decodeUtf8(blob.content))
      name = m.name || slug
    } catch (_) {}
    out.push({ slug, name })
  }
  return out
}

// Empreinte actuelle du dossier <slug> distant (pour le garde-fou de fraîcheur).
export async function remoteTreeSha(slug) {
  const { tree } = await fullTree()
  return slugTreeSha(tree, slug)
}

// ── pull d'un projet ─────────────────────────────────────────────────────────
export async function pullProject(slug) {
  const { owner, repo, base, branch, tree } = await fullTree()
  const prefix = slug + '/'
  const files = {}, resources = {}
  for (const e of tree) {
    if (e.type !== 'blob' || !e.path.startsWith(prefix)) continue
    const rel = e.path.slice(prefix.length)
    const blob = await ghJson(`${base}/git/blobs/${e.sha}`)
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
  const treeSha = slugTreeSha(tree, slug)
  return { id: slug, name, entry, files, resources, remote: { repo: `${owner}/${repo}`, branch, slug, treeSha }, createdAt: now, updatedAt: now }
}

// ── push d'un projet ─────────────────────────────────────────────────────────
// Rend le dossier `<slug>/` identique au projet local, en UN commit atomique
// (Git Data API). Répercute ajouts, modifs ET suppressions ; si le projet a été
// renommé (remote.slug ≠ slug), supprime aussi l'ancien dossier.
export async function pushProject(project, message, opts = {}) {
  const { owner, repo, base } = await ctx()
  const info = await ghJson(base)
  const branch = info.default_branch || 'main'
  const slug = project.id

  // Dépôt vide (aucun commit) → l'initialiser via l'API Contents : un PUT crée
  // le commit initial + la branche (la Git Data API refuse un dépôt vide → 409).
  let refRes = await gh(`${base}/git/ref/heads/${branch}`)
  if (!refRes.ok) {
    if (refRes.status === 409 || refRes.status === 404) {
      await ghJson(`${base}/contents/README.md`, {
        method: 'PUT',
        body: { message: 'Initialise ollin-projects', branch, content: encodeUtf8('# ollin-projects\n\nProjets du playground Ollin.\n') },
      })
      refRes = await gh(`${base}/git/ref/heads/${branch}`)
    }
    if (!refRes.ok) {
      let msg = String(refRes.status)
      try { const e = await refRes.json(); if (e && e.message) msg = refRes.status + ' — ' + e.message } catch (_) {}
      throw new Error('GitHub ' + msg)
    }
  }
  const ref = await refRes.json()
  const baseSha = ref.object.sha
  const baseCommit = await ghJson(`${base}/git/commits/${baseSha}`)
  const baseTree = baseCommit.tree.sha

  // État distant courant (sert au garde-fou de conflit ET aux suppressions).
  const oldSlug = project.remote && project.remote.slug
  const trackedSlug = oldSlug || slug
  const { tree: remoteTree } = await fullTree()

  // Garde-fou : le dossier suivi a-t-il changé sur GitHub depuis notre dernière
  // synchro ? Si oui (et pas de force) → conflit, on n'écrase pas en silence.
  if (!opts.force && project.remote && project.remote.treeSha != null) {
    const current = slugTreeSha(remoteTree, trackedSlug)
    if (current !== project.remote.treeSha) {
      const err = new Error('Le projet a été modifié sur GitHub depuis ta dernière synchro.')
      err.code = 'CONFLICT'
      throw err
    }
  }

  const tree = []
  for (const rel in (project.files || {})) {
    const blob = await ghJson(`${base}/git/blobs`, { method: 'POST', body: { content: project.files[rel], encoding: 'utf-8' } })
    tree.push({ path: `${slug}/${rel}`, mode: '100644', type: 'blob', sha: blob.sha })
  }
  for (const rel in (project.resources || {})) {
    const blob = await ghJson(`${base}/git/blobs`, { method: 'POST', body: { content: project.resources[rel].b64, encoding: 'base64' } })
    tree.push({ path: `${slug}/${rel}`, mode: '100644', type: 'blob', sha: blob.sha })
  }

  // Suppressions : fichiers distants (slug courant + ancien slug si renommage)
  // absents localement → sha:null.
  const desired = new Set(tree.map(t => t.path))
  const scan = new Set([slug])
  if (oldSlug && oldSlug !== slug) scan.add(oldSlug)
  for (const e of remoteTree) {
    if (e.type !== 'blob') continue
    if (!scan.has(e.path.split('/')[0])) continue
    if (!desired.has(e.path)) tree.push({ path: e.path, mode: '100644', type: 'blob', sha: null })
  }

  const newTree = await ghJson(`${base}/git/trees`, { method: 'POST', body: { base_tree: baseTree, tree } })
  const commit = await ghJson(`${base}/git/commits`, {
    method: 'POST',
    body: { message: message || `ollin: ${project.name}`, tree: newTree.sha, parents: [baseSha] },
  })
  await ghJson(`${base}/git/refs/heads/${branch}`, { method: 'PATCH', body: { sha: commit.sha } })

  // Nouvelle empreinte du dossier après commit → base des prochains garde-fous.
  const after = await fullTree()
  project.remote = { repo: `${owner}/${repo}`, branch, slug, commit: commit.sha, treeSha: slugTreeSha(after.tree, slug) }
  return project.remote
}
