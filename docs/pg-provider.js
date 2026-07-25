// ── Ollin Playground — couche d'abstraction des fournisseurs de stockage ─────
//
// Point d'indirection UNIQUE entre les vues (playground, run) et le stockage.
// Une vue ne connaît plus un module concret (`pg-store`, `pg-github`) mais un
// FOURNISSEUR obtenu ici — brancher un autre backend (Google Drive, Dropbox,
// Supabase Storage, Firebase Storage, GitHub via Octokit…) se fait en ajoutant
// une entrée au registre + un module respectant le contrat, sans toucher aux
// vues. Le choix du backend devient transparent (un seul point de bascule).
//
// Deux contrats DISTINCTS, car les rôles diffèrent :
//
// ── ProjectProvider (magasin de TRAVAIL, CRUD, local et rapide) ──────────────
// Surface = celle de pg-store.js (identité voulue → migration sans réécrire les
// sites d'appel). Un fournisseur DOIT exposer :
//   async init()
//   async listProjects()                       → [{id,name,entry,updatedAt,fileCount}]
//   async getProject(id)                        → projet complet | null
//   async createProject(name)                   → projet
//   async saveProject(project)                  → projet   (upsert)
//   async renameProject(id, name)               → projet | null
//   async deleteProject(id)
//   getActiveId() / setActiveId(id)             (id du projet actif, synchrone)
//   slugify(name)                               → slug
//   MANIFEST : string   TRANSIENT_ID : string   (constantes)
//
// ── RemoteProvider (SYNCHRO d'un magasin distant, réseau, faillible) ─────────
// Surface = celle de pg-github.js. Un fournisseur distant DOIT exposer :
//   isConnected() ; setToken(t)/getToken()/clearToken()
//   getRepo()/setRepo(v)                        (cible : dépôt, dossier Drive, bucket…)
//   async getUser() ; async ensureRepo()
//   async listRemoteProjects()                  → [{slug,name}]
//   async pullProject(slug)                     → projet (modèle identique au local)
//   async pushProject(project, message, opts)   → project.remote (repo/branch/slug/sha)
//   async remoteFolderSha(slug) ; folderMoved(current, known)
//
// Le MODÈLE de projet ({id,name,entry,files{},resources{}} + manifeste réel
// `ollin.project.json`) est commun aux deux contrats et à tous les backends →
// un projet voyage tel quel de l'un à l'autre, aucune conversion.
//
// Imports VERSIONNÉS (?v=) comme dans les vues : le cache-busting de déploiement
// est préservé (un backend chargé ici passe par le même jeton de version).

// Backends disponibles. Ajouter un fournisseur = une entrée ici (chemin du
// module) + un module respectant le contrat ci-dessus. `default` = choix implicite.
const STORE_KINDS = {
  local: './pg-store.js',
}
const REMOTE_KINDS = {
  github: './pg-github.js',
}

const STORE_DEFAULT  = 'local'
const REMOTE_DEFAULT = 'github'

// Clés (localStorage) du backend choisi — permettent une bascule persistante sans
// toucher aux vues (une future UI de réglages écrit ces clés ; à défaut, le défaut).
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

// Vérifie qu'un module chargé honore le contrat — échoue TÔT et clairement si un
// nouveau backend oublie un membre (plutôt qu'un `undefined is not a function`
// plus loin dans une vue).
function assertContract(mod, contract, label) {
  const missing = contract.filter(k => mod[k] === undefined)
  if (missing.length)
    throw new Error(`${label} : contrat non respecté, membres manquants : ${missing.join(', ')}`)
  return mod
}

function preferred(key, kinds, fallback) {
  const chosen = (() => { try { return localStorage.getItem(key) } catch (_) { return null } })()
  return (chosen && kinds[chosen]) ? chosen : fallback
}

// Magasin de travail (CRUD). `v` = jeton de version de la SPA (cache-busting).
// `kind` explicite, sinon la préférence persistée, sinon le défaut.
export async function getProvider(v, kind) {
  const k = kind || preferred(STORE_PREF_KEY, STORE_KINDS, STORE_DEFAULT)
  const path = STORE_KINDS[k]
  if (!path) throw new Error('Fournisseur de stockage inconnu : ' + k)
  return assertContract(await import(`${path}?v=${v}`), STORE_CONTRACT, `store:${k}`)
}

// Fournisseur distant (synchro). Même logique de sélection que getProvider.
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

// Bascule persistante du backend (écrit la préférence lue par getProvider/getRemote).
export function setStoreKind(kind) {
  if (!STORE_KINDS[kind]) throw new Error('Fournisseur de stockage inconnu : ' + kind)
  localStorage.setItem(STORE_PREF_KEY, kind)
}
export function setRemoteKind(kind) {
  if (!REMOTE_KINDS[kind]) throw new Error('Fournisseur distant inconnu : ' + kind)
  localStorage.setItem(REMOTE_PREF_KEY, kind)
}
