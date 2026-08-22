// Ollin playground — the storage-provider abstraction layer.
//
// The SINGLE point of indirection between the views (playground, run) and the storage. A view no
// longer knows a concrete module (`pg-store`, `pg-github`) but a PROVIDER obtained here, so
// plugging in another backend (Google Drive, Dropbox, Supabase Storage, Firebase Storage, GitHub
// through Octokit…) takes an entry in the registry plus a module honouring the contract, and no
// change to the views. The choice of backend becomes transparent, with a single switch point.
//
// Two DISTINCT contracts, the roles being different:
//
// ProjectProvider — the WORKING store: CRUD, local and fast. Its surface is that of pg-store.js
// (an intended identity, so the migration did not rewrite the call sites). A provider MUST
// expose:
//   async init()
//   async listProjects()                       → [{id,name,entry,updatedAt,fileCount}]
//   async getProject(id)                        → the complete project, or null
//   async createProject(name)                   → a project
//   async saveProject(project)                  → a project (upsert)
//   async renameProject(id, name)               → a project, or null
//   async deleteProject(id)
//   getActiveId() / setActiveId(id)             (the active project's id, synchronous)
//   slugify(name)                               → slug
//   MANIFEST : string   TRANSIENT_ID : string   (constants)
//
// RemoteProvider — the SYNC with a remote store: networked, fallible. Its surface is that of
// pg-github.js. A remote provider MUST expose:
//   isConnected() ; setToken(t)/getToken()/clearToken()
//   getRepo()/setRepo(v)                        (the target: a repository, a Drive folder, a bucket…)
//   async getUser() ; async ensureRepo()
//   async listRemoteProjects()                  → [{slug,name}]
//   async pullProject(slug)                     → a project, in the same model as the local one
//   async pushProject(project, message, opts)   → project.remote (repo/branch/slug/sha)
//   async remoteFolderSha(slug) ; folderMoved(current, known)
//
// The project MODEL ({id,name,entry,files{},resources{}} plus the real `ollin.project.json`
// manifest) is common to both contracts and to every backend, so a project travels from one to
// the other as it is, with no conversion.
//
// Imports are VERSIONED (?v=) as in the views: the deployment's cache-busting is preserved, a
// backend loaded here going through the same version token.

// The available backends. Adding a provider means one entry here (the module's path) plus a
// module honouring the contract above. `default` is the implicit choice.
const STORE_KINDS = {
  local: './pg-store.js',
}
const REMOTE_KINDS = {
  github: './pg-github.js',
}

const STORE_DEFAULT  = 'local'
const REMOTE_DEFAULT = 'github'

// The localStorage keys of the chosen backend, which allow a persistent switch without touching
// the views (a settings UI would write these keys; failing that, the default applies).
const STORE_PREF_KEY  = 'ollin-pg-store-kind'
const REMOTE_PREF_KEY = 'ollin-pg-remote-kind'

const STORE_CONTRACT = [
  'init', 'listProjects', 'getProject', 'createProject', 'saveProject',
  'renameProject', 'deleteProject', 'getActiveId', 'setActiveId', 'slugify',
  'MANIFEST', 'TRANSIENT_ID',
]
const REMOTE_CONTRACT = [
  'isConnected', 'setToken', 'getToken', 'clearToken', 'getRepo', 'setRepo',
  'getUser', 'ensureRepo', 'listRemoteProjects', 'pullProject', 'pushProject',
  'remoteFolderSha', 'folderMoved',
]

// Checks that a loaded module honours the contract, failing EARLY and clearly when a new backend
// forgets a member, rather than as an `undefined is not a function` further along in a view.
function assertContract(mod, contract, label) {
  const missing = contract.filter(k => mod[k] === undefined)
  if (missing.length)
    throw new Error(`${label}: contract not met, missing members: ${missing.join(', ')}`)
  return mod
}

function preferred(key, kinds, fallback) {
  const chosen = (() => { try { return localStorage.getItem(key) } catch (_) { return null } })()
  return (chosen && kinds[chosen]) ? chosen : fallback
}

// The working store (CRUD). `v` is the app's version token, for cache-busting. An explicit
// `kind` wins, otherwise the persisted preference, otherwise the default.
export async function getProvider(v, kind) {
  const k = kind || preferred(STORE_PREF_KEY, STORE_KINDS, STORE_DEFAULT)
  const path = STORE_KINDS[k]
  if (!path) throw new Error('Fournisseur de stockage inconnu : ' + k)
  return assertContract(await import(`${path}?v=${v}`), STORE_CONTRACT, `store:${k}`)
}

// The remote provider (sync). The same selection logic as getProvider.
export async function getRemote(v, kind) {
  const k = kind || preferred(REMOTE_PREF_KEY, REMOTE_KINDS, REMOTE_DEFAULT)
  const path = REMOTE_KINDS[k]
  if (!path) throw new Error('Fournisseur distant inconnu : ' + k)
  return assertContract(await import(`${path}?v=${v}`), REMOTE_CONTRACT, `remote:${k}`)
}

export function listStoreKinds() {
  return Object.keys(STORE_KINDS)
}
export function listRemoteKinds() {
  return Object.keys(REMOTE_KINDS)
}

// Persistent backend switch: it writes the preference read by getProvider and getRemote.
export function setStoreKind(kind) {
  if (!STORE_KINDS[kind]) throw new Error('Fournisseur de stockage inconnu : ' + kind)
  localStorage.setItem(STORE_PREF_KEY, kind)
}
export function setRemoteKind(kind) {
  if (!REMOTE_KINDS[kind]) throw new Error('Fournisseur distant inconnu : ' + kind)
  localStorage.setItem(REMOTE_PREF_KEY, kind)
}
