// Ollin playground — the GitHub provider, with a configurable project repository.
//
// It synchronises the projects with a GitHub repository (one folder per project, an exact mirror
// of pg-store.js's local model). Authentication is by personal access token (fine-grained, of
// Contents scope), pasted once and kept in localStorage.
//
// The target repository is configurable (getRepo/setRepo, `ollin-projects` by default):
//   - "my-repo"        goes under the authenticated user's account
//   - "owner/my-repo"  is an organisation or shared repository, never created automatically
//
// api.github.com answers with CORS open for authenticated REST calls, so everything works from
// the browser, with no server in between.

const API        = 'https://api.github.com'
const TOKEN_KEY  = 'ollin-gh-token'
const REPO_KEY   = 'ollin-gh-repo'
const MANIFEST   = 'ollin.project.json'
const IMAGE_EXTS = new Set(['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'])

// Token.
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

// The target repository (mandatory, in owner/repo form).
export function getRepo() {
  return localStorage.getItem(REPO_KEY) || null
}
export function setRepo(v) {
  const s = (v || '').trim()
  if (!s) { localStorage.removeItem(REPO_KEY); return }
  if (!s.includes('/')) throw new Error('Format invalide — utilise owner/repo (ex. moncompte/ollin-projects)')
  localStorage.setItem(REPO_KEY, s)
}

// Low-level requests.
async function gh(path, { method = 'GET', body = null, token = getToken() } = {}) {
  if (!token) throw new Error('Not signed in to GitHub (no token)')
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

// base64 to and from UTF-8.
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

// Identity and target.
let _login = null
export async function getUser() {
  const u = await ghJson('/user')
  _login = u.login
  return u
}
async function login() {
  return _login || (await getUser()).login
}
export function knownLogin() {
  return _login
}

// Tests a token WITHOUT storing it, so the store never holds an unvalidated token that another
// path (an auto-push, a sync) could use.
export async function verifyToken(t) {
  return ghJson('/user', { token: t })
}

// Resolves the target repository: { owner, repo, base }.
async function ctx() {
  const val = getRepo()
  if (!val || !val.includes('/')) throw new Error('No repository configured - set owner/repo in the GitHub settings')
  const [owner, repo] = val.split('/')
  return { owner, repo, base: `/repos/${owner}/${repo}` }
}

// Repository. Checks that it exists; it has to be created by hand on GitHub.
export async function ensureRepo() {
  const { owner, repo, base } = await ctx()
  const res = await gh(base)
  if (res.ok) return res.json()
  if (res.status === 404) throw new Error(`Repository ${owner}/${repo} not found - create it on GitHub first.`)
  let msg = String(res.status)
  try { const e = await res.json(); if (e && e.message) msg = res.status + ' — ' + e.message } catch (_) {}
  throw new Error('GitHub ' + msg)
}

// The complete tree of the default branch, plus the repository's context. The optional `pre`
// is { owner, repo, base, branch }, already resolved by the caller (pushProject, say), which
// avoids reading the repository's metadata a second time.
async function fullTree(pre) {
  let owner, repo, base, branch
  if (pre && pre.base && pre.branch) {
    ({ owner, repo, base, branch } = pre)
  } else {
    ({ owner, repo, base } = await ctx())
    const info = await ghJson(base)
    branch = info.default_branch || 'main'
  }
  const res = await gh(`${base}/git/trees/${branch}?recursive=1`)
  if (!res.ok) {
    if (res.status === 409 || res.status === 404) return { owner, repo, base, branch, tree: [] }  // an empty repository
    let msg = String(res.status)
    try { const e = await res.json(); if (e && e.message) msg = res.status + ' — ' + e.message } catch (_) {}
    throw new Error('GitHub ' + msg)
  }
  const t = await res.json()
  return { owner, repo, base, branch, tree: t.tree || [] }
}

// Listing the remote projects.
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

// The SHA of the Git tree of the <slug> sub-folder at the repository's root. It is read through
// the Git Data API (git/trees), which is STRONGLY consistent: right after a push it reflects the
// new state at once. (The commit LISTING API, git/commits?path=, is served by a LAGGING index,
// and returned a stale SHA right after a push, hence systematic conflicts and badges. It is not
// to be used for this.) The tree sha changes if and only if the folder's CONTENT changes, and it
// belongs to that folder alone: a push on another project does not touch it. It returns null when
// the folder is absent from the repository, and THROWS when the API fails — the caller must not
// confuse "no such folder" with "cannot be read".
async function folderTreeSha(base, branch, slug) {
  const res = await gh(`${base}/git/trees/${encodeURIComponent(branch)}`)
  if (!res.ok) throw new Error('GitHub trees ' + res.status)
  const root = await res.json()
  const entry = (root.tree || []).find(e => e.path === slug && e.type === 'tree')
  return entry ? entry.sha : null
}
export async function remoteFolderSha(slug) {
  const { base } = await ctx()
  const info = await ghJson(base)
  const branch = info.default_branch || 'main'
  return folderTreeSha(base, branch, slug)
}

// The SINGLE RULE for "the remote folder has moved since our last sync". It is the one definition
// shared by both guards: the freshness badge (on opening, in the playground) AND the conflict
// guard (on pushing, below). `current` is the folder's tree SHA (through folderTreeSha or
// remoteFolderSha), `known` the SHA of our last sync (project.remote.folderSha). It has moved if
// the folder exists on the remote (a non-null current) and its tree differs. The POLICY, however,
// differs between callers and stays theirs: the badge also requires `known` to be known (silence
// when uncertain), whereas the push warns even without it (against overwriting: when in doubt,
// warn). These are not duplicates but two deliberately distinct decisions.
export function folderMoved(current, known) {
  return current !== null && current !== (known || null)
}

// Pulling a project.
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
  // Best-effort: if the read fails we carry on with no baseline — the badge stays mute until the
  // next push or pull — rather than failing the whole pull when the files are already fetched.
  let folderSha = null
  try {
    folderSha = await folderTreeSha(base, branch, slug)
  } catch (_) {}
  return { id: slug, name, entry, files, resources, remote: { repo: `${owner}/${repo}`, branch, slug, folderSha }, createdAt: now, updatedAt: now }
}

// Pushing a project: it makes the `<slug>/` folder identical to the local project, in ONE atomic
// commit (the Git Data API). Additions, edits AND deletions are carried over; and if the project
// has been renamed (remote.slug differs from slug), the old folder is deleted too.
export async function pushProject(project, message, opts = {}) {
  const { owner, repo, base } = await ctx()
  const info = await ghJson(base)
  const branch = info.default_branch || 'main'
  const slug = project.id

  // An empty repository, with no commit, is initialised through the Contents API: a PUT creates
  // the initial commit and the branch (the Git Data API refuses an empty repository with a 409).
  let refRes = await gh(`${base}/git/ref/heads/${branch}`)
  if (!refRes.ok) {
    if (refRes.status === 409 || refRes.status === 404) {
      await ghJson(`${base}/contents/README.md`, {
        method: 'PUT',
        body: { message: 'Initialise ollin-projects', branch, content: encodeUtf8('# ollin-projects\n\nOllin playground projects.\n') },
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

  // The current remote state, used for the deletions; a rename removes the old folder.
  const oldSlug = project.remote && project.remote.slug
  const trackedSlug = oldSlug || slug
  const { tree: remoteTree } = await fullTree({ owner, repo, base, branch })   // reuses the context already resolved

  // No conflict guard here: the sync model (the `dirty` flag, single-person use) makes the LOCAL
  // side authoritative on a push. Reconciling with a divergent remote happens on OPENING
  // (syncOnOpen, on the playground side), not here.

  const tree = []
  for (const rel in (project.files || {})) {
    const blob = await ghJson(`${base}/git/blobs`, { method: 'POST', body: { content: project.files[rel], encoding: 'utf-8' } })
    tree.push({ path: `${slug}/${rel}`, mode: '100644', type: 'blob', sha: blob.sha })
  }
  for (const rel in (project.resources || {})) {
    const blob = await ghJson(`${base}/git/blobs`, { method: 'POST', body: { content: project.resources[rel].b64, encoding: 'base64' } })
    tree.push({ path: `${slug}/${rel}`, mode: '100644', type: 'blob', sha: blob.sha })
  }

  // Deletions: remote files (under the current slug, plus the old one on a rename) absent
  // locally get sha:null.
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

  // The baseline for the next guards is the folder's tree sha, read from the POST git/trees
  // response (its top-level entries), so there is no further network read and it is strictly the
  // same identifier folderTreeSha will read back. A fallback covers the case where the entry was
  // not there (Git Data being strongly consistent).
  let folderSha = (newTree.tree || []).find(e => e.path === slug && e.type === 'tree')?.sha || null
  if (!folderSha) {
    try {
      folderSha = await folderTreeSha(base, branch, slug)
    } catch (_) {}
  }
  project.remote = { repo: `${owner}/${repo}`, branch, slug, folderSha }
  return project.remote
}
