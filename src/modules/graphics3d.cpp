// Module graphics — PARTIE 3D. La 2D, la fenêtre/boucle de rendu, les styles et
// les transforms sont dans graphics_module.cpp ; la frontière entre les deux
// unités est graphics_internal.h. Compilé uniquement dans les builds raylib/WASM.
#include "graphics_internal.h"
#include "graphics_quat.h"
#include "image_module.h"
#include "module_utils.h"
#include "value.h"
#include "vm.h"
#include <raylib.h>
#include <rlgl.h>
#include <raymath.h>
#include <cmath>
#include <cstdio>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

// État 3D propre à cette unité (déplacé depuis la zone de style 2D).
// s_in_3d : vrai entre begin3d et end3d. s_cur_tex3d : texture 3D courante
// (0 = blanche), remise à 0 chaque frame via reset3dFrameState().
static bool s_in_3d = false;
static unsigned int s_cur_tex3d = 0;

// Atlas de tuiles (terrain voxel) : une texture en grille (cols×rows). Chaque cube
// porte un triplet de tuiles (dessus/côté/dessous) ; le shader choisit selon la
// normale et échantillonne l'atlas. s_cur_tile = tuiles du prochain cube (état,
// comme fill) ; -1 = pas de tuile (couleur pleine / texture0 classique).
static unsigned int s_atlas_texid = 0;
static float s_atlas_grid[2] = {1.0f, 1.0f};
static float s_cur_tile[3] = {-1.0f, -1.0f, -1.0f};
static float s_anim_tile = -1.0f;   // tuile animée (UV qui défile, ex. eau) ; -1 = aucune
// paramètres de l'ondulation de la tuile animée : {défilement, vitesse d'onde, fréquence
// spatiale, amplitude}. Défauts = look eau ; réglables via graphics.tileAnim(t, ...).
static float s_anim_params[4] = {0.09f, 1.6f, 8.0f, 0.045f};

// ── 3D ────────────────────────────────────────────────────────────────────────
// L'affichage 3D s'appuie DIRECTEMENT sur l'API raylib (Camera3D / BeginMode3D…).
// La caméra est une valeur de 1re classe (map) construite par graphics.camera ;
// begin3d/end3d encadrent les dessins 3D dans draw(). Les formes suivent l'état
// fill/stroke exactement comme les primitives 2D (plein si fill, fil de fer si
// stroke, les deux si les deux). La profondeur est remise à neuf par un
// graphics.clear(couleur opaque) en début de frame (ClearBackground efface le
// tampon couleur ET le depth via rlClearScreenBuffers).

// Reconstruit une Camera3D raylib depuis le handle map (graphics.camera). up par
// défaut = +Y ; projection perspective ; near/far = valeurs par défaut de raylib.
static Camera3D cameraFromMap(const Value& v, const char* fn) {
    if (!v.isMap())
        throw std::runtime_error(std::string(fn) + ": expected a camera (graphics.camera)");
    auto get = [&](const char* k, double def) -> float {
        Value f = v.mapGet(Value(std::string(k)));
        return f.isNumber() ? (float)f.asNum() : (float)def;
    };
    bool ortho = v.mapGet(Value(std::string("ortho"))).isNumber() && v.mapGet(Value(std::string("ortho"))).asNum() != 0.0;
    Camera3D cam{};
    cam.position = Vector3{get("px", 0), get("py", 0), get("pz", 0)};
    cam.target = Vector3{get("tx", 0), get("ty", 0), get("tz", 0)};
    cam.up = Vector3{get("ux", 0), get("uy", 1), get("uz", 0)};
    cam.fovy = get("fovy", ortho ? 10.0f : 45.0f);
    cam.projection = ortho ? CAMERA_ORTHOGRAPHIC : CAMERA_PERSPECTIVE;
    return cam;
}

// ── Classe Camera (native, comme Color) ─────────────────────────────────────
// Une caméra est une INSTANCE de classe (map avec __class__) portant les champs
// px,py,pz (position), tx,ty,tz (cible), fovy. Comme toute instance reste un
// T_MAP, cameraFromMap la relit sans changement. Les méthodes MUTENT self en
// place (caméra mutable entre frames) et renvoient self → appels chaînables.
static double camField(const Value& self, const char* k) {
    Value v = self.mapGet(Value(std::string(k)));
    return v.isNumber() ? v.asNum() : 0.0;
}

// cam.setPos(x,y,z) : fixe la position de la caméra.
static Value cam_set_pos(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Value self = args[0];
    self.mapSet(Value(std::string("px")), Value(numArg(args, argc, 1, "Camera.setPos")));
    self.mapSet(Value(std::string("py")), Value(numArg(args, argc, 2, "Camera.setPos")));
    self.mapSet(Value(std::string("pz")), Value(numArg(args, argc, 3, "Camera.setPos")));
    return self;
}

// cam.lookAt(x,y,z) : réoriente la caméra vers le point cible (x,y,z).
static Value cam_look_at(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Value self = args[0];
    self.mapSet(Value(std::string("tx")), Value(numArg(args, argc, 1, "Camera.lookAt")));
    self.mapSet(Value(std::string("ty")), Value(numArg(args, argc, 2, "Camera.lookAt")));
    self.mapSet(Value(std::string("tz")), Value(numArg(args, argc, 3, "Camera.lookAt")));
    return self;
}

// cam.move(dx,dy,dz) : translate la caméra ET sa cible du même delta → la
// direction de visée est conservée (déplacement latéral/avant du point de vue).
static Value cam_move(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Value self = args[0];
    double dx = numArg(args, argc, 1, "Camera.move");
    double dy = numArg(args, argc, 2, "Camera.move");
    double dz = numArg(args, argc, 3, "Camera.move");
    self.mapSet(Value(std::string("px")), Value(camField(self, "px") + dx));
    self.mapSet(Value(std::string("py")), Value(camField(self, "py") + dy));
    self.mapSet(Value(std::string("pz")), Value(camField(self, "pz") + dz));
    self.mapSet(Value(std::string("tx")), Value(camField(self, "tx") + dx));
    self.mapSet(Value(std::string("ty")), Value(camField(self, "ty") + dy));
    self.mapSet(Value(std::string("tz")), Value(camField(self, "tz") + dz));
    return self;
}

// cam.zoom(factor) : multiplie la taille du monde visible (ortho: fovy *= factor,
// perspective: rapproche/éloigne la position le long de l'axe de visée).
static Value cam_zoom(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Value self = args[0];
    double factor = numArg(args, argc, 1, "Camera.zoom");
    if (factor <= 0.0) return self;
    bool ortho = self.mapGet(Value(std::string("ortho"))).isNumber() && self.mapGet(Value(std::string("ortho"))).asNum() != 0.0;
    if (ortho) {
        double fovy = camField(self, "fovy");
        self.mapSet(Value(std::string("fovy")), Value(std::max(0.01, fovy * factor)));
    } else {
        double tx = camField(self, "tx"), ty = camField(self, "ty"), tz = camField(self, "tz");
        double px = camField(self, "px"), py = camField(self, "py"), pz = camField(self, "pz");
        double dx = px - tx, dy = py - ty, dz = pz - tz;
        self.mapSet(Value(std::string("px")), Value(tx + dx * factor));
        self.mapSet(Value(std::string("py")), Value(ty + dy * factor));
        self.mapSet(Value(std::string("pz")), Value(tz + dz * factor));
    }
    return self;
}

// cam.orbit(angle, rayon [, hauteur]) : place la caméra en orbite autour de sa
// cible, sur un cercle du plan XZ de rayon `rayon`. `angle` en RADIANS (composable
// avec elapsedTime / math.cos-sin). `hauteur` optionnelle = altitude AU-DESSUS de
// la cible (par défaut : conserve la hauteur courante).
static Value cam_orbit(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Value self = args[0];
    double angle = numArg(args, argc, 1, "Camera.orbit");
    double radius = numArg(args, argc, 2, "Camera.orbit");
    double tx = camField(self, "tx");
    double ty = camField(self, "ty");
    double tz = camField(self, "tz");
    double py = (argc > 3) ? ty + numArg(args, argc, 3, "Camera.orbit") : camField(self, "py");
    self.mapSet(Value(std::string("px")), Value(tx + std::cos(angle) * radius));
    self.mapSet(Value(std::string("py")), Value(py));
    self.mapSet(Value(std::string("pz")), Value(tz + std::sin(angle) * radius));
    return self;
}

static Value makeCameraClass() {
    Value cls = Value::makeClass();
    cls.mapSet(Value(std::string("__name__")), Value(std::string("Camera")));
    cls.mapSet(Value(std::string("setPos")), Value::makeBuiltin(cam_set_pos));
    cls.mapSet(Value(std::string("lookAt")), Value::makeBuiltin(cam_look_at));
    cls.mapSet(Value(std::string("move")), Value::makeBuiltin(cam_move));
    cls.mapSet(Value(std::string("orbit")), Value::makeBuiltin(cam_orbit));
    cls.mapSet(Value(std::string("zoom")), Value::makeBuiltin(cam_zoom));
    return cls;
}

// Classe Camera partagée (construite une fois, réutilisée par chaque instance).
static Value cameraClass() {
    static Value cls = makeCameraClass();
    return cls;
}

// graphics.camera(px,py,pz, tx,ty,tz [, fovy]) : INSTANCE de classe Camera.
// Regarde (tx,ty,tz) depuis (px,py,pz), up = +Y, fovy = champ de vision vertical
// (45° défaut). Mutable via ses méthodes (setPos/lookAt/move/orbit/zoom).
static Value gfx_camera(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Value cam = Value::makeMap();
    cam.mapSet(Value(std::string("__class__")), cameraClass());
    cam.mapSet(Value(std::string("px")), Value(numArg(args, argc, 0, "graphics.camera")));
    cam.mapSet(Value(std::string("py")), Value(numArg(args, argc, 1, "graphics.camera")));
    cam.mapSet(Value(std::string("pz")), Value(numArg(args, argc, 2, "graphics.camera")));
    cam.mapSet(Value(std::string("tx")), Value(numArg(args, argc, 3, "graphics.camera")));
    cam.mapSet(Value(std::string("ty")), Value(numArg(args, argc, 4, "graphics.camera")));
    cam.mapSet(Value(std::string("tz")), Value(numArg(args, argc, 5, "graphics.camera")));
    cam.mapSet(Value(std::string("fovy")), Value(argc > 6 ? numArg(args, argc, 6, "graphics.camera") : 45.0));
    return cam;
}

// graphics.cameraOrtho(px,py,pz, tx,ty,tz [, size]) : caméra orthographique.
// Projection sans perspective — taille du monde visible = size unités en hauteur
// (défaut 10). Mêmes méthodes que camera() ; zoom() ajuste size.
static Value gfx_camera_ortho(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Value cam = Value::makeMap();
    cam.mapSet(Value(std::string("__class__")), cameraClass());
    cam.mapSet(Value(std::string("px")), Value(numArg(args, argc, 0, "graphics.cameraOrtho")));
    cam.mapSet(Value(std::string("py")), Value(numArg(args, argc, 1, "graphics.cameraOrtho")));
    cam.mapSet(Value(std::string("pz")), Value(numArg(args, argc, 2, "graphics.cameraOrtho")));
    cam.mapSet(Value(std::string("tx")), Value(numArg(args, argc, 3, "graphics.cameraOrtho")));
    cam.mapSet(Value(std::string("ty")), Value(numArg(args, argc, 4, "graphics.cameraOrtho")));
    cam.mapSet(Value(std::string("tz")), Value(numArg(args, argc, 5, "graphics.cameraOrtho")));
    cam.mapSet(Value(std::string("fovy")), Value(argc > 6 ? numArg(args, argc, 6, "graphics.cameraOrtho") : 10.0));
    cam.mapSet(Value(std::string("ortho")), Value((int64_t)1));
    return cam;
}

// ── Batcher 3D instancié + éclairé ──────────────────────────────────────────
// begin3d ouvre la collecte ; cube/sphere/… EMPILENT une instance {transfo, tint}
// dans le bucket de leur (mesh, texture) ; end3d résout chaque bucket en UN
// DrawMeshInstanced custom (transfo + couleur PAR INSTANCE via 2 VBO d'instance)
// avec le shader Blinn-Phong. → N formes de même (mesh,texture) = 1 draw call.

enum Shape3D { SH_CUBE = 0, SH_SPHERE = 1, SH_CYLINDER = 2, SH_PLANE = 3, SH_CONE = 4, SH_TORUS = 5, SH_COUNT = 6 };

struct Bucket3D {
    unsigned int vaoId;          // clé mesh : identifie le mesh GPU (primitive OU modèle externe)
    Mesh mesh;                   // mesh à dessiner (primitive unitaire ou mesh d'un modèle)
    unsigned int texId;
    std::vector<Matrix> xforms;
    std::vector<float> colors;   // 4 floats (rgba 0..1) par instance
    std::vector<float> tiles;    // 3 floats (top/side/bottom, -1 = aucune) par instance
};
static std::vector<Bucket3D> s_buckets;
static Camera3D s_cam3d{};   // caméra du bloc begin3d courant (pour viewPos)

// Modèles externes (déclarés ici car reset3dGraphicsState les référence ; défs plus bas).
struct PendingModel {
    std::vector<unsigned char> bytes;
    std::string ext;   // avec le point, ex. ".obj"
};
static std::map<std::string, PendingModel> s_model_bytes;   // octets préchargés (nom → données)
static std::map<std::string, Model> s_model_cache;          // modèles chargés en GPU (paresseux)

// ── Groupes d'instances CUITS (géométrie retenue) ───────────────────────────
// beginChunk/endChunk enregistrent des cubes UNE fois dans des VBO persistants ;
// drawChunk les redessine chaque frame en 1 appel — plus besoin de ré-émettre
// chaque cube depuis Ollin à chaque frame (culling par chunk côté script).
static bool s_recording = false;
static std::vector<Matrix> s_rec_x;   // transfos locales enregistrées (OPAQUE)
static std::vector<float> s_rec_c;    // rgba (0..1) enregistrés (OPAQUE)
static std::vector<float> s_rec_t;    // tuiles (3 floats/instance) enregistrées (OPAQUE)
static std::vector<Matrix> s_rec_xw;  // idem, instances TRANSPARENTES (alpha < 1, ex. eau)
static std::vector<float> s_rec_cw;
static std::vector<float> s_rec_tw;
static Mesh s_rec_mesh{};             // mesh enregistré, groupe OPAQUE (cube)
static Mesh s_rec_mesh_w{};           // mesh enregistré, groupe TRANSPARENT (ex. plane pour l'eau)
struct InstGroup {
    Mesh mesh;
    unsigned int vboX;   // VBO transfos (persistant)
    unsigned int vboC;   // VBO couleurs (persistant)
    unsigned int vboT;   // VBO tuiles (persistant, 3 floats/instance)
    int count;
};
static std::vector<InstGroup> s_groups;   // groupes cuits (index+1 = id)
static std::vector<int> s_free_groups;    // slots libérés réutilisables → borne s_groups en streaming
static Matrix s_view3d = MatrixIdentity();   // vue figée au begin3d (MVP des solides) ; identité par défaut (fail-safe si flush avant begin3d)
static Matrix s_proj3d = MatrixIdentity();   // projection perspective figée au begin3d — pour inFrustum appelé HORS du bloc 3D (où rlGetMatrixProjection renvoie l'ortho 2D restaurée par end3d)

// Cache de meshes indexé par (shape, segments) — plusieurs résolutions coexistent
// (ex. push→segments(8)→sphère + pop n'invalide pas la sphère 64 segments du même frame).
static std::map<std::pair<int,int>, Mesh> s_shape_cache;

void reset3dShapeCache() {
    for (auto& kv : s_shape_cache)
        UnloadMesh(kv.second);
    s_shape_cache.clear();
}

static Mesh getShapeMesh(int shape) {
    int seg = gfxSegments();
    auto key = std::make_pair(shape, seg);
    auto it = s_shape_cache.find(key);
    if (it != s_shape_cache.end())
        return it->second;
    Mesh mesh{};
    switch (shape) {
        case SH_CUBE:
            mesh = GenMeshCube(1.0f, 1.0f, 1.0f);
            break;
        case SH_SPHERE:
            mesh = GenMeshSphere(0.5f, seg, seg);
            break;
        case SH_CYLINDER:
            mesh = GenMeshCylinder(1.0f, 1.0f, seg);
            break;
        case SH_CONE:
            mesh = GenMeshCone(1.0f, 1.0f, seg);
            break;
        case SH_TORUS:
            // major=1, tube=0.3, size=2 → par_shapes_scale×1 → no shrink
            // The ring lies in the XY plane; XY scale = major radius, Z = tube
            mesh = GenMeshTorus(0.3f, 2.0f, seg, seg);
            break;
        default:
            mesh = GenMeshPlane(1.0f, 1.0f, 1, 1);
            break;
    }
    s_shape_cache[key] = mesh;
    return s_shape_cache[key];
}

// Texture blanche 1×1 : « pas de texture » → échantillon blanc → texture×tint = tint.
static Texture2D s_white_tex{};
static bool s_white_ready = false;
static unsigned int whiteTexId() {
    if (!s_white_ready) {
        Image img = GenImageColor(1, 1, WHITE);
        s_white_tex = LoadTextureFromImage(img);
        UnloadImage(img);
        s_white_ready = true;
    }
    return s_white_tex.id;
}

// État d'éclairage (phase 1 : ambient + 1 lumière directionnelle). Opt-in : tant
// qu'aucune lumière/ambient n'est posée, rendu PLAT (ambient blanc, lumière off).
static bool s_lighting_used = false;
static float s_amb3d[4] = {0.15f, 0.15f, 0.15f, 1.0f};
static bool s_light_on = false;
static int s_light_type = 0;   // 0 = directionnelle, 1 = ponctuelle
static Vector3 s_light_pos = {0.0f, 0.0f, 0.0f};
static Vector3 s_light_tgt = {0.0f, -1.0f, 0.0f};
static float s_light_col[4] = {1.0f, 1.0f, 1.0f, 1.0f};

// Shader Blinn-Phong instancié (transfo + couleur par instance) + texture.
static Shader s_lit{};
static bool s_lit_ready = false;
static int s_loc_instcolor = -1, s_loc_viewpos = -1, s_loc_ambient = -1;
static int s_loc_insttile = -1, s_loc_atlasgrid = -1, s_loc_utime = -1, s_loc_animtile = -1;
static int s_loc_animparams = -1;
static int s_loc_l_en = -1, s_loc_l_type = -1, s_loc_l_pos = -1, s_loc_l_tgt = -1, s_loc_l_col = -1;

// VBO d'instance PERSISTANTS (transfo + couleur) : réutilisés d'une frame à
// l'autre (mis à jour par glBufferSubData), au lieu d'être créés/détruits à
// chaque bucket/frame. Capacités en octets ; agrandissement seulement.
static unsigned int s_inst_vbo_xform = 0, s_inst_vbo_color = 0, s_inst_vbo_tile = 0;
static int s_inst_cap_xform = 0, s_inst_cap_color = 0, s_inst_cap_tile = 0;

// Crée (1re fois / agrandissement) ou met à jour un VBO d'instance ; laisse le
// VBO lié en sortie (pour le rlSetVertexAttribute qui suit).
static void uploadInstanceVBO(unsigned int& vbo, int& cap, const void* data, int bytes) {
    if (vbo == 0 || bytes > cap) {
        if (vbo != 0)
            rlUnloadVertexBuffer(vbo);
        vbo = rlLoadVertexBuffer(data, bytes, true);   // GL_DYNAMIC_DRAW, laisse lié
        cap = bytes;
    } else {
        rlEnableVertexBuffer(vbo);
        rlUpdateVertexBuffer(vbo, data, bytes, 0);
    }
}

static void loadLitShader() {
    if (s_lit_ready) {
        return;
    }
#ifdef __EMSCRIPTEN__
    const char* HDR = "#version 300 es\nprecision highp float;\n";
#else
    const char* HDR = "#version 330\n";
#endif
    std::string vs = std::string(HDR) +
        "in vec3 vertexPosition;\n"
        "in vec2 vertexTexCoord;\n"
        "in vec3 vertexNormal;\n"
        "in mat4 instanceTransform;\n"
        "in vec4 instanceColor;\n"
        "in vec3 instanceTile;\n"
        "uniform mat4 mvp;\n"
        "out vec3 fragPosition;\n"
        "out vec2 fragTexCoord;\n"
        "out vec4 fragColor;\n"
        "out vec3 fragNormal;\n"
        "flat out vec3 fragTile;\n"
        "void main() {\n"
        "    mat4 m = instanceTransform;\n"
        "    vec4 wp = m * vec4(vertexPosition, 1.0);\n"
        "    fragPosition = wp.xyz;\n"
        "    fragTexCoord = vertexTexCoord;\n"
        "    fragColor = instanceColor;\n"
        "    fragTile = instanceTile;\n"
        "    mat3 nm = transpose(inverse(mat3(m)));\n"   // matrice de normale : correcte sous rotation / scale non uniforme
        "    fragNormal = normalize(nm * vertexNormal);\n"
        "    gl_Position = mvp * wp;\n"
        "}\n";
    std::string fs = std::string(HDR) +
        "in vec3 fragPosition;\n"
        "in vec2 fragTexCoord;\n"
        "in vec4 fragColor;\n"
        "in vec3 fragNormal;\n"
        "flat in vec3 fragTile;\n"
        "uniform sampler2D texture0;\n"
        "uniform vec2 atlasGrid;\n"
        "uniform float uTime;\n"
        "uniform float animTile;\n"
        "uniform vec4 animParams;\n"
        "uniform vec4 ambient;\n"
        "uniform vec3 viewPos;\n"
        "struct Light { int enabled; int type; vec3 position; vec3 target; vec4 color; };\n"
        "uniform Light light0;\n"
        "out vec4 finalColor;\n"
        "void main() {\n"
        "    vec4 texel;\n"
        "    if (fragTile.x >= 0.0) {\n"                 // cube d'atlas : tuile selon la face (normale)
        "        float t = fragTile.y;\n"                //   côté par défaut
        "        if (fragNormal.y > 0.5) t = fragTile.x;\n"   // dessus
        "        else if (fragNormal.y < -0.5) t = fragTile.z;\n" // dessous
        "        float cols = atlasGrid.x;\n"
        "        vec2 cell = vec2(mod(t, cols), floor(t / cols));\n"
        "        vec2 uv = fract(fragTexCoord);\n"
        "        if (animTile >= 0.0 && abs(t - animTile) < 0.5) {\n"           // tuile animée (eau) : défilement + ondulation sinusoïdale
        "            float sc = animParams.x; float ws = animParams.y;\n"        //   sc=défilement, ws=vitesse d'onde
        "            float wf = animParams.z; float wa = animParams.w;\n"        //   wf=fréquence spatiale, wa=amplitude
        "            uv = fract(uv + vec2(uTime * sc + sin(uTime * ws + fragPosition.z * wf) * wa,\n" // phase en coord. MONDE (fragPosition)
        "                                 uTime * sc * 0.66 + cos(uTime * ws * 0.8 + fragPosition.x * wf) * wa));\n" // → continue d'une tuile à l'autre
        "        }\n"
        "        uv = clamp(uv, 0.002, 0.998);\n"        // léger inset : évite le bleeding entre tuiles
        "        vec2 auv = (cell + uv) / atlasGrid;\n"
        "        texel = texture(texture0, auv);\n"
        "    } else {\n"                                 // chemin classique (modèles, texture immédiate)
        "        texel = texture(texture0, fragTexCoord);\n"
        "    }\n"
        "    vec4 tint = fragColor;\n"
        "    vec3 base = (texel * tint).rgb;\n"
        "    vec3 normal = normalize(fragNormal);\n"
        "    vec3 result = base * ambient.rgb;\n"
        "    if (light0.enabled == 1) {\n"
        "        vec3 l;\n"
        "        if (light0.type == 0) l = -normalize(light0.target - light0.position);\n"
        "        else l = normalize(light0.position - fragPosition);\n"
        "        float ndl = max(dot(normal, l), 0.0);\n"
        "        result += base * light0.color.rgb * ndl;\n"
        "        if (ndl > 0.0) {\n"
        "            vec3 viewD = normalize(viewPos - fragPosition);\n"
        "            float spec = pow(max(dot(viewD, reflect(-l, normal)), 0.0), 16.0);\n"
        "            result += light0.color.rgb * spec * 0.3;\n"
        "        }\n"
        "    }\n"
        "    finalColor = vec4(result, texel.a * tint.a);\n"
        "}\n";
    s_lit = LoadShaderFromMemory(vs.c_str(), fs.c_str());
    if (s_lit.locs[SHADER_LOC_VERTEX_INSTANCETRANSFORM] <= 0) {
        s_lit.locs[SHADER_LOC_VERTEX_INSTANCETRANSFORM] = GetShaderLocationAttrib(s_lit, "instanceTransform");
    }
    s_loc_instcolor = GetShaderLocationAttrib(s_lit, "instanceColor");
    s_loc_insttile = GetShaderLocationAttrib(s_lit, "instanceTile");
    s_loc_atlasgrid = GetShaderLocation(s_lit, "atlasGrid");
    s_loc_utime = GetShaderLocation(s_lit, "uTime");
    s_loc_animtile = GetShaderLocation(s_lit, "animTile");
    s_loc_animparams = GetShaderLocation(s_lit, "animParams");
    s_loc_viewpos = GetShaderLocation(s_lit, "viewPos");
    s_loc_ambient = GetShaderLocation(s_lit, "ambient");
    s_loc_l_en = GetShaderLocation(s_lit, "light0.enabled");
    s_loc_l_type = GetShaderLocation(s_lit, "light0.type");
    s_loc_l_pos = GetShaderLocation(s_lit, "light0.position");
    s_loc_l_tgt = GetShaderLocation(s_lit, "light0.target");
    s_loc_l_col = GetShaderLocation(s_lit, "light0.color");
    s_lit_ready = true;
}

// Bucket courant pour (mesh, texture courante) — créé à la demande. Keyé par
// mesh.vaoId → primitives unitaires ET meshes de modèles externes partagent le
// même chemin instancié + éclairé (N formes de même (mesh,texture) = 1 draw call).
static Bucket3D& bucketFor(const Mesh& mesh, unsigned int texId) {
    for (auto& b : s_buckets) {
        if (b.vaoId == mesh.vaoId && b.texId == texId) {
            return b;
        }
    }
    s_buckets.push_back(Bucket3D{mesh.vaoId, mesh, texId, {}, {}, {}});
    return s_buckets.back();
}

// Empile une instance (transfo translate·scale + couleur) dans son bucket (mesh, texId).
static void pushInstance(const Mesh& mesh, unsigned int texId, Vector3 pos, Vector3 size, Color col) {
    if (s_recording) {
        // Mode enregistrement (beginChunk) : on cuit la transfo LOCALE (monde) et la
        // couleur ; texId ignoré (groupe cuit = texture blanche + couleur par instance).
        (void)texId;
        Matrix rm = MatrixMultiply(MatrixScale(size.x, size.y, size.z), MatrixTranslate(pos.x, pos.y, pos.z));
        // Routage OPAQUE vs TRANSPARENT selon l'alpha de la couleur (eau = alpha<1).
        if (col.a < 250) {
            s_rec_mesh_w = mesh;
            s_rec_xw.push_back(rm);
            s_rec_cw.push_back(col.r / 255.0f);
            s_rec_cw.push_back(col.g / 255.0f);
            s_rec_cw.push_back(col.b / 255.0f);
            s_rec_cw.push_back(col.a / 255.0f);
            s_rec_tw.push_back(s_cur_tile[0]);
            s_rec_tw.push_back(s_cur_tile[1]);
            s_rec_tw.push_back(s_cur_tile[2]);
            return;
        }
        s_rec_mesh = mesh;
        s_rec_x.push_back(rm);
        s_rec_c.push_back(col.r / 255.0f);
        s_rec_c.push_back(col.g / 255.0f);
        s_rec_c.push_back(col.b / 255.0f);
        s_rec_c.push_back(col.a / 255.0f);
        s_rec_t.push_back(s_cur_tile[0]);
        s_rec_t.push_back(s_cur_tile[1]);
        s_rec_t.push_back(s_cur_tile[2]);
        return;
    }
    Bucket3D& b = bucketFor(mesh, texId);
    // Placement local (scale puis translate) PUIS la transfo courante capturée ICI
    // → chaque instance fige sa propre transfo. begin3d ayant ouvert le mode
    // transform, rlGetMatrixTransform() reflète translate/rotate/scale qu'ils soient
    // encadrés par push/pop ou « nus » (accumulés sur le bloc) — même sémantique que
    // les primitives immédiates.
    Matrix local = MatrixMultiply(MatrixScale(size.x, size.y, size.z), MatrixTranslate(pos.x, pos.y, pos.z));
    b.xforms.push_back(MatrixMultiply(local, rlGetMatrixTransform()));
    b.colors.push_back(col.r / 255.0f);
    b.colors.push_back(col.g / 255.0f);
    b.colors.push_back(col.b / 255.0f);
    b.colors.push_back(col.a / 255.0f);
    b.tiles.push_back(s_cur_tile[0]);
    b.tiles.push_back(s_cur_tile[1]);
    b.tiles.push_back(s_cur_tile[2]);
}

// Active le shader lit et pose les uniforms du frame (MVP = view·proj figée au
// begin3d, position caméra, éclairage). Renvoie false si le shader est indisponible.
// Partagé par flushBucket (instances collectées) ET drawChunk (groupe cuit).
static bool litBeginDraw() {
    loadLitShader();
    if (s_lit.id == 0) {
        return false;
    }
    rlEnableShader(s_lit.id);
    Matrix mvp = MatrixMultiply(s_view3d, rlGetMatrixProjection());
    rlSetUniformMatrix(s_lit.locs[SHADER_LOC_MATRIX_MVP], mvp);
    float vp[3] = {s_cam3d.position.x, s_cam3d.position.y, s_cam3d.position.z};
    rlSetUniform(s_loc_viewpos, vp, RL_SHADER_UNIFORM_VEC3, 1);
    float amb[4] = {1.0f, 1.0f, 1.0f, 1.0f};
    int en = 0;
    if (s_lighting_used) {
        amb[0] = s_amb3d[0];
        amb[1] = s_amb3d[1];
        amb[2] = s_amb3d[2];
        amb[3] = s_amb3d[3];
        en = s_light_on ? 1 : 0;
    }
    rlSetUniform(s_loc_ambient, amb, RL_SHADER_UNIFORM_VEC4, 1);
    rlSetUniform(s_loc_l_en, &en, RL_SHADER_UNIFORM_INT, 1);
    rlSetUniform(s_loc_l_type, &s_light_type, RL_SHADER_UNIFORM_INT, 1);
    float lp[3] = {s_light_pos.x, s_light_pos.y, s_light_pos.z};
    rlSetUniform(s_loc_l_pos, lp, RL_SHADER_UNIFORM_VEC3, 1);
    float lt[3] = {s_light_tgt.x, s_light_tgt.y, s_light_tgt.z};
    rlSetUniform(s_loc_l_tgt, lt, RL_SHADER_UNIFORM_VEC3, 1);
    rlSetUniform(s_loc_l_col, s_light_col, RL_SHADER_UNIFORM_VEC4, 1);
    if (s_loc_atlasgrid >= 0) {
        rlSetUniform(s_loc_atlasgrid, s_atlas_grid, RL_SHADER_UNIFORM_VEC2, 1);
    }
    if (s_loc_utime >= 0) {
        float tm = (float)GetTime();
        rlSetUniform(s_loc_utime, &tm, RL_SHADER_UNIFORM_FLOAT, 1);
    }
    if (s_loc_animtile >= 0) {
        rlSetUniform(s_loc_animtile, &s_anim_tile, RL_SHADER_UNIFORM_FLOAT, 1);
    }
    if (s_loc_animparams >= 0) {
        rlSetUniform(s_loc_animparams, s_anim_params, RL_SHADER_UNIFORM_VEC4, 1);
    }
    return true;
}

// Attache les attributs d'instance (transfo mat4 = 4 vec4, puis couleur vec4,
// divisor 1) depuis des VBO DÉJÀ REMPLIS, sur le VAO du mesh.
// Attache les attributs d'instance (transfo mat4 = 4 vec4, couleur vec4, tuiles
// vec3 ; divisor 1) depuis des VBO DÉJÀ REMPLIS. VAO supposé déjà actif. Partagé
// par litBindInstances (groupe cuit) et flushBucket (VBO partagés).
static void bindInstanceVBOs(unsigned int vboX, unsigned int vboC, unsigned int vboT) {
    int locT = s_lit.locs[SHADER_LOC_VERTEX_INSTANCETRANSFORM];
    rlEnableVertexBuffer(vboX);
    for (unsigned int i = 0; i < 4; i++) {
        rlEnableVertexAttribute(locT + i);
        rlSetVertexAttribute(locT + i, 4, RL_FLOAT, 0, sizeof(Matrix), i * sizeof(Vector4));
        rlSetVertexAttributeDivisor(locT + i, 1);
    }
    rlEnableVertexBuffer(vboC);
    if (s_loc_instcolor >= 0) {
        rlEnableVertexAttribute(s_loc_instcolor);
        rlSetVertexAttribute(s_loc_instcolor, 4, RL_FLOAT, 0, 0, 0);
        rlSetVertexAttributeDivisor(s_loc_instcolor, 1);
    }
    if (s_loc_insttile >= 0 && vboT != 0) {
        rlEnableVertexBuffer(vboT);
        rlEnableVertexAttribute(s_loc_insttile);
        rlSetVertexAttribute(s_loc_insttile, 3, RL_FLOAT, 0, 0, 0);
        rlSetVertexAttributeDivisor(s_loc_insttile, 1);
    }
}

// divisor 1) depuis des VBO DÉJÀ REMPLIS, sur le VAO du mesh.
static void litBindInstances(unsigned int vaoId, unsigned int vboX, unsigned int vboC, unsigned int vboT) {
    rlEnableVertexArray(vaoId);
    bindInstanceVBOs(vboX, vboC, vboT);
    rlDisableVertexBuffer();
    rlDisableVertexArray();
}

// Dessin instancié (shader + attributs déjà en place). Lie la texture puis draw.
static void litDrawInstanced(const Mesh& mesh, unsigned int texId, int n) {
    rlActiveTextureSlot(0);
    rlEnableTexture(texId ? texId : whiteTexId());
    int slot = 0;
    rlSetUniform(s_lit.locs[SHADER_LOC_MAP_DIFFUSE], &slot, RL_SHADER_UNIFORM_INT, 1);
    rlEnableVertexArray(mesh.vaoId);
    if (mesh.indices != nullptr) {
        rlDrawVertexArrayElementsInstanced(0, mesh.triangleCount * 3, 0, n);
    } else {
        rlDrawVertexArrayInstanced(0, mesh.vertexCount, n);
    }
    rlDisableVertexArray();
    rlActiveTextureSlot(0);
    rlDisableTexture();
}

// Résout un bucket (instances collectées CETTE frame) en UN appel instancié.
static void flushBucket(const Bucket3D& b) {
    int n = (int)b.xforms.size();
    if (n == 0) {
        return;
    }
    if (!litBeginDraw()) {
        return;
    }
    Mesh mesh = b.mesh;
    // Tampon scratch réutilisé (pas d'alloc par bucket/frame) + VBO d'instance
    // PARTAGÉS persistants (upload par frame, pas recréés).
    static std::vector<float16> xf;
    xf.resize(n);
    for (int i = 0; i < n; i++) {
        xf[i] = MatrixToFloatV(b.xforms[i]);
    }
    rlEnableVertexArray(mesh.vaoId);
    uploadInstanceVBO(s_inst_vbo_xform, s_inst_cap_xform, xf.data(), n * (int)sizeof(float16));
    uploadInstanceVBO(s_inst_vbo_color, s_inst_cap_color, b.colors.data(), n * 4 * (int)sizeof(float));
    uploadInstanceVBO(s_inst_vbo_tile, s_inst_cap_tile, b.tiles.data(), n * 3 * (int)sizeof(float));
    bindInstanceVBOs(s_inst_vbo_xform, s_inst_vbo_color, s_inst_vbo_tile);
    rlDisableVertexBuffer();
    rlDisableVertexArray();
    litDrawInstanced(mesh, b.texId, n);
    rlDisableShader();
}

void reset3dLightingState() {
    s_lighting_used = false;
    s_light_on = false;
    s_cur_tex3d = 0;
    s_amb3d[0] = 0.15f;
    s_amb3d[1] = 0.15f;
    s_amb3d[2] = 0.15f;
    s_amb3d[3] = 1.0f;
}

// Libère TOUTES les ressources GL 3D en cache (shader, meshes unitaires, texture
// blanche, VBO d'instance) et remet les caches à zéro. À appeler par gfx_canvas
// AVANT de détruire le contexte GL (CloseWindow) : sinon les ids GL survivraient
// dans les caches et pointeraient vers des objets d'un contexte détruit au run
// suivant (playground) → 3D corrompue/plantage. Équivalent 3D de image_reset().
// NB : ne fait des appels GL que si un contexte est courant (garde IsWindowReady
// côté appelant) ; sur le 1er run les flags *_ready sont false → no-op.
void reset3dGraphicsState() {
    if (s_lit_ready) {
        UnloadShader(s_lit);
        s_lit = Shader{};
        s_lit_ready = false;
    }
    reset3dShapeCache();
    // Modèles chargés en GPU : invalides avec le contexte détruit → décharger et
    // vider le cache (rechargés paresseusement depuis les octets au prochain usage).
    for (auto& kv : s_model_cache) {
        UnloadModel(kv.second);
    }
    s_model_cache.clear();
    // Groupes d'instances cuits : VBO liés au contexte → libérer et vider (le script
    // les recuit dans setup au prochain run).
    for (auto& g : s_groups) {
        if (g.vboX) {
            rlUnloadVertexBuffer(g.vboX);
        }
        if (g.vboC) {
            rlUnloadVertexBuffer(g.vboC);
        }
        if (g.vboT) {
            rlUnloadVertexBuffer(g.vboT);
        }
    }
    s_groups.clear();
    s_free_groups.clear();
    s_recording = false;
    s_rec_x.clear();
    s_rec_c.clear();
    s_rec_t.clear();
    s_rec_xw.clear();
    s_rec_cw.clear();
    s_rec_tw.clear();
    if (s_white_ready) {
        UnloadTexture(s_white_tex);
        s_white_tex = Texture2D{};
        s_white_ready = false;
    }
    if (s_inst_vbo_xform != 0) {
        rlUnloadVertexBuffer(s_inst_vbo_xform);
        s_inst_vbo_xform = 0;
        s_inst_cap_xform = 0;
    }
    if (s_inst_vbo_color != 0) {
        rlUnloadVertexBuffer(s_inst_vbo_color);
        s_inst_vbo_color = 0;
        s_inst_cap_color = 0;
    }
    if (s_inst_vbo_tile != 0) {
        rlUnloadVertexBuffer(s_inst_vbo_tile);
        s_inst_vbo_tile = 0;
        s_inst_cap_tile = 0;
    }
    s_buckets.clear();
    s_in_3d = false;
    s_cur_tex3d = 0;
    s_atlas_texid = 0;
    s_atlas_grid[0] = 1.0f;
    s_atlas_grid[1] = 1.0f;
    s_cur_tile[0] = -1.0f;
    s_cur_tile[1] = -1.0f;
    s_cur_tile[2] = -1.0f;
    s_anim_tile = -1.0f;
    s_anim_params[0] = 0.09f;
    s_anim_params[1] = 1.6f;
    s_anim_params[2] = 8.0f;
    s_anim_params[3] = 0.045f;
}

static void flush3dBuckets() {
    // Vider le batch immédiat en attente (fil de fer/grille dessinés pendant la
    // collecte) avant nos draw calls instanciés → ordre cohérent.
    rlDrawRenderBatchActive();
    for (const auto& b : s_buckets) {
        flushBucket(b);
    }
    s_buckets.clear();
}

void end3dInternal() {
    if (!s_in_3d) {
        return;
    }
    flush3dBuckets();   // encore en Mode3D → matrices view/proj disponibles
    rlPopMatrix();      // referme le mode transform ouvert par begin3d (rlPushMatrix)
    EndMode3D();
    s_in_3d = false;
}

static Value gfx_begin3d(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 1)
        throw std::runtime_error("graphics.begin3d: expected a camera (graphics.camera)");
    s_cam3d = cameraFromMap(args[0], "graphics.begin3d");
    s_buckets.clear();
    BeginMode3D(s_cam3d);
    s_view3d = rlGetMatrixModelview();   // vue « pure » (avant toute transfo utilisateur)
    s_proj3d = rlGetMatrixProjection();  // projection perspective figée → inFrustum correct même appelé hors du bloc 3D
    // Entre dans le mode « transform » de rlgl pour TOUT le bloc 3D : ainsi
    // translate/rotate/scale — AVEC OU SANS push/pop — écrivent dans
    // RLGL.State.transform (espace monde, lu par rlGetMatrixTransform) au lieu de
    // la modelview. Les solides instanciés (bake) ET les primitives immédiates
    // (transformRequired) reçoivent alors la même transfo → cohérent, sans exiger
    // push/pop. Refermé par le rlPopMatrix d'end3dInternal.
    rlPushMatrix();
    s_in_3d = true;
    return Value{};
}

static Value gfx_end3d(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    end3dInternal();   // idempotent
    return Value{};
}

// graphics.ambient(v | couleur) : lumière ambiante (active le mode éclairé).
static Value gfx_ambient(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc > 0 && (args[0].isMap() || args[0].isClass())) {
        Color c = gfxToColor(args[0]);
        s_amb3d[0] = c.r / 255.0f;
        s_amb3d[1] = c.g / 255.0f;
        s_amb3d[2] = c.b / 255.0f;
        s_amb3d[3] = 1.0f;
    } else {
        float v = argc > 0 ? (float)numArg(args, argc, 0, "graphics.ambient") : 0.15f;
        s_amb3d[0] = v;
        s_amb3d[1] = v;
        s_amb3d[2] = v;
        s_amb3d[3] = 1.0f;
    }
    s_lighting_used = true;
    return Value{};
}

// ── Classe Light (native, comme Camera/Color) ───────────────────────────────
// Phase 1 : une seule lumière active (directionnelle ou ponctuelle). Un objet
// Light porte sa config (type, direction/position, couleur, activée) et, à chaque
// mutation, la répercute sur l'état d'éclairage global (dernier écrit = actif).
static double instField(const Value& self, const char* k, double def) {
    Value v = self.mapGet(Value(std::string(k)));
    return v.isNumber() ? v.asNum() : def;
}

static void applyLightFromInstance(const Value& self) {
    int type = (int)instField(self, "type", 0);
    float x = (float)instField(self, "dx", 0.0);
    float y = (float)instField(self, "dy", -1.0);
    float z = (float)instField(self, "dz", 0.0);
    s_light_type = type;
    if (type == 1) {
        s_light_pos = Vector3{x, y, z};
        s_light_tgt = Vector3{0.0f, 0.0f, 0.0f};
    } else {
        s_light_pos = Vector3{0.0f, 0.0f, 0.0f};
        s_light_tgt = Vector3{x, y, z};
    }
    s_light_col[0] = (float)instField(self, "r", 1.0);
    s_light_col[1] = (float)instField(self, "g", 1.0);
    s_light_col[2] = (float)instField(self, "b", 1.0);
    s_light_col[3] = (float)instField(self, "a", 1.0);
    s_light_on = instField(self, "enabled", 1.0) != 0.0;
    s_lighting_used = true;
}

// light.setDir(x,y,z) : oriente une lumière directionnelle (direction de propagation).
static Value light_set_dir(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Value self = args[0];
    self.mapSet(Value(std::string("type")), Value((int64_t)0));
    self.mapSet(Value(std::string("dx")), Value(numArg(args, argc, 1, "Light.setDir")));
    self.mapSet(Value(std::string("dy")), Value(numArg(args, argc, 2, "Light.setDir")));
    self.mapSet(Value(std::string("dz")), Value(numArg(args, argc, 3, "Light.setDir")));
    applyLightFromInstance(self);
    return self;
}

// light.setPos(x,y,z) : positionne une lumière ponctuelle.
static Value light_set_pos(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Value self = args[0];
    self.mapSet(Value(std::string("type")), Value((int64_t)1));
    self.mapSet(Value(std::string("dx")), Value(numArg(args, argc, 1, "Light.setPos")));
    self.mapSet(Value(std::string("dy")), Value(numArg(args, argc, 2, "Light.setPos")));
    self.mapSet(Value(std::string("dz")), Value(numArg(args, argc, 3, "Light.setPos")));
    applyLightFromInstance(self);
    return self;
}

// light.setColor(couleur) : couleur de la lumière.
static Value light_set_color(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Value self = args[0];
    if (argc > 1 && (args[1].isMap() || args[1].isClass())) {
        Color c = gfxToColor(args[1]);
        self.mapSet(Value(std::string("r")), Value(c.r / 255.0));
        self.mapSet(Value(std::string("g")), Value(c.g / 255.0));
        self.mapSet(Value(std::string("b")), Value(c.b / 255.0));
        self.mapSet(Value(std::string("a")), Value(c.a / 255.0));
    }
    applyLightFromInstance(self);
    return self;
}

// light.enable(bool) : active/désactive la lumière (défaut : active).
static Value light_enable(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Value self = args[0];
    bool on = (argc > 1) ? !isFalsy(args[1]) : true;
    self.mapSet(Value(std::string("enabled")), Value((int64_t)(on ? 1 : 0)));
    applyLightFromInstance(self);
    return self;
}

static Value makeLightClass() {
    Value cls = Value::makeClass();
    cls.mapSet(Value(std::string("__name__")), Value(std::string("Light")));
    cls.mapSet(Value(std::string("setDir")), Value::makeBuiltin(light_set_dir));
    cls.mapSet(Value(std::string("setPos")), Value::makeBuiltin(light_set_pos));
    cls.mapSet(Value(std::string("setColor")), Value::makeBuiltin(light_set_color));
    cls.mapSet(Value(std::string("enable")), Value::makeBuiltin(light_enable));
    return cls;
}

static Value lightClass() {
    static Value cls = makeLightClass();
    return cls;
}

// graphics.light("dir"|"point", x,y,z [, couleur]) : crée un objet Light et
// l'active. "dir" : (x,y,z) = direction de propagation ; "point" : position.
static Value gfx_light(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    std::string type = (argc > 0 && args[0].isString()) ? args[0].asString() : "dir";
    float x = (float)numArg(args, argc, 1, "graphics.light");
    float y = (float)numArg(args, argc, 2, "graphics.light");
    float z = (float)numArg(args, argc, 3, "graphics.light");
    Color c = (argc > 4 && (args[4].isMap() || args[4].isClass())) ? gfxToColor(args[4]) : WHITE;
    Value inst = Value::makeMap();
    inst.mapSet(Value(std::string("__class__")), lightClass());
    inst.mapSet(Value(std::string("type")), Value((int64_t)(type == "point" ? 1 : 0)));
    inst.mapSet(Value(std::string("dx")), Value((double)x));
    inst.mapSet(Value(std::string("dy")), Value((double)y));
    inst.mapSet(Value(std::string("dz")), Value((double)z));
    inst.mapSet(Value(std::string("r")), Value(c.r / 255.0));
    inst.mapSet(Value(std::string("g")), Value(c.g / 255.0));
    inst.mapSet(Value(std::string("b")), Value(c.b / 255.0));
    inst.mapSet(Value(std::string("a")), Value(c.a / 255.0));
    inst.mapSet(Value(std::string("enabled")), Value((int64_t)1));
    applyLightFromInstance(inst);
    return inst;
}

// graphics.grid(slices, spacing) : repère quadrillé au sol (plan XZ), centré sur
// l'origine. Couleur grise fixe de raylib (n'utilise ni fill ni stroke).
static Value gfx_grid(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    int slices = argc > 0 ? gfxToInt(args[0]) : 10;
    float spacing = argc > 1 ? (float)numArg(args, argc, 1, "graphics.grid") : 1.0f;
    DrawGrid(slices, spacing);
    return Value{};
}

// graphics.texture(img) / graphics.noTexture() : texture 3D courante (handle image).
static Value gfx_texture(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc > 0 && args[0].isMap()) {
        Value idv = args[0].mapGet(Value(std::string("id")));
        s_cur_tex3d = idv.isInteger() ? image_gl_texid((int)idv.asInt()) : 0;
    }
    return Value{};
}

static Value gfx_no_texture(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    s_cur_tex3d = 0;
    return Value{};
}

// graphics.tileset(img, cols, rows) : déclare l'atlas de tuiles (terrain voxel).
// Une seule texture en grille, échantillonnée par tuile selon la face du cube.
static Value gfx_tileset(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc > 0 && args[0].isMap()) {
        Value idv = args[0].mapGet(Value(std::string("id")));
        s_atlas_texid = idv.isInteger() ? image_gl_texid((int)idv.asInt()) : 0;
    }
    s_atlas_grid[0] = argc > 1 ? (float)numArg(args, argc, 1, "graphics.tileset") : 1.0f;
    s_atlas_grid[1] = argc > 2 ? (float)numArg(args, argc, 2, "graphics.tileset") : 1.0f;
    if (s_atlas_texid != 0) {
        // pixels nets (look voxel) : filtrage NEAREST, pas de mipmap.
        rlTextureParameters(s_atlas_texid, RL_TEXTURE_MAG_FILTER, RL_TEXTURE_FILTER_NEAREST);
        rlTextureParameters(s_atlas_texid, RL_TEXTURE_MIN_FILTER, RL_TEXTURE_FILTER_NEAREST);
    }
    return Value{};
}

// graphics.tiles(top, side, bottom) : tuiles du prochain cube (état, comme fill).
static Value gfx_tiles(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    s_cur_tile[0] = argc > 0 ? (float)numArg(args, argc, 0, "graphics.tiles") : -1.0f;
    s_cur_tile[1] = argc > 1 ? (float)numArg(args, argc, 1, "graphics.tiles") : s_cur_tile[0];
    s_cur_tile[2] = argc > 2 ? (float)numArg(args, argc, 2, "graphics.tiles") : s_cur_tile[1];
    return Value{};
}

// graphics.tile(t) : même tuile sur les 6 faces (raccourci). tile(-1) = aucune.
static Value gfx_tile(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    float t = argc > 0 ? (float)numArg(args, argc, 0, "graphics.tile") : -1.0f;
    s_cur_tile[0] = t;
    s_cur_tile[1] = t;
    s_cur_tile[2] = t;
    return Value{};
}

// graphics.tileAnim(t [, defilement, vitesse, frequence, amplitude]) : tuile dont l'UV
// défile/ondule dans le temps (eau). -1 = aucune. Les 4 paramètres optionnels règlent
// l'ondulation (défauts = look eau) ; la phase spatiale est en coordonnées monde.
static Value gfx_tile_anim(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    s_anim_tile = argc > 0 ? (float)numArg(args, argc, 0, "graphics.tileAnim") : -1.0f;
    if (argc > 1) {
        s_anim_params[0] = (float)numArg(args, argc, 1, "graphics.tileAnim");
    }
    if (argc > 2) {
        s_anim_params[1] = (float)numArg(args, argc, 2, "graphics.tileAnim");
    }
    if (argc > 3) {
        s_anim_params[2] = (float)numArg(args, argc, 3, "graphics.tileAnim");
    }
    if (argc > 4) {
        s_anim_params[3] = (float)numArg(args, argc, 4, "graphics.tileAnim");
    }
    return Value{};
}

// graphics.cube(x,y,z, w,h,l) : cube centré en (x,y,z). Plein si fill (instancié,
// éclairé, texturé), arêtes si stroke (immédiat, non éclairé).
static Value gfx_cube(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Vector3 pos{(float)numArg(args, argc, 0, "graphics.cube"), (float)numArg(args, argc, 1, "graphics.cube"),
                (float)numArg(args, argc, 2, "graphics.cube")};
    Vector3 size{(float)numArg(args, argc, 3, "graphics.cube"), (float)numArg(args, argc, 4, "graphics.cube"),
                 (float)numArg(args, argc, 5, "graphics.cube")};
    if (gfxHasFill())
        pushInstance(getShapeMesh(SH_CUBE), s_cur_tex3d, pos, size, gfxFillColor());
    if (gfxHasStroke())
        DrawCubeWiresV(pos, size, gfxStrokeColor());
    return Value{};
}

// graphics.sphere(x,y,z, r) : sphère centrée en (x,y,z). Pleine si fill (instanciée,
// éclairée, texturée), fil de fer si stroke (immédiat). Mesh unitaire = rayon 0.5.
static Value gfx_sphere(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Vector3 pos{(float)numArg(args, argc, 0, "graphics.sphere"), (float)numArg(args, argc, 1, "graphics.sphere"),
                (float)numArg(args, argc, 2, "graphics.sphere")};
    float r = (float)numArg(args, argc, 3, "graphics.sphere");
    if (gfxHasFill())
        pushInstance(getShapeMesh(SH_SPHERE), s_cur_tex3d, pos, Vector3{2.0f * r, 2.0f * r, 2.0f * r}, gfxFillColor());
    if (gfxHasStroke())
        DrawSphereWires(pos, r, 16, 16, gfxStrokeColor());
    return Value{};
}

// graphics.cylinder(x,y,z, r, h) : cylindre, (x,y,z) = centre de la base, rayon r,
// hauteur h (vers +Y). Plein si fill (instancié), fil de fer si stroke (immédiat).
// Mono-rayon (contrainte de l'instancing : mesh unitaire figé, rayon 1 hauteur 1).
static Value gfx_cylinder(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Vector3 pos{(float)numArg(args, argc, 0, "graphics.cylinder"), (float)numArg(args, argc, 1, "graphics.cylinder"),
                (float)numArg(args, argc, 2, "graphics.cylinder")};
    float r = (float)numArg(args, argc, 3, "graphics.cylinder");
    float h = (float)numArg(args, argc, 4, "graphics.cylinder");
    if (gfxHasFill())
        pushInstance(getShapeMesh(SH_CYLINDER), s_cur_tex3d, pos, Vector3{r, h, r}, gfxFillColor());
    if (gfxHasStroke())
        DrawCylinderWires(pos, r, r, h, 16, gfxStrokeColor());
    return Value{};
}

// graphics.cone(x,y,z, r, h) : cône, (x,y,z) = centre de la base, rayon r, hauteur h (vers +Y).
static Value gfx_cone(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Vector3 pos{(float)numArg(args, argc, 0, "graphics.cone"), (float)numArg(args, argc, 1, "graphics.cone"),
                (float)numArg(args, argc, 2, "graphics.cone")};
    float r = (float)numArg(args, argc, 3, "graphics.cone");
    float h = (float)numArg(args, argc, 4, "graphics.cone");
    if (gfxHasFill())
        pushInstance(getShapeMesh(SH_CONE), s_cur_tex3d, pos, Vector3{r, h, r}, gfxFillColor());
    if (gfxHasStroke())
        DrawCylinderWires(pos, r, 0.0f, h, 16, gfxStrokeColor());
    return Value{};
}

// graphics.torus(x,y,z, r, tube) : tore centré en (x,y,z), rayon major r, rayon du tube tube.
// Le mesh unitaire a r=0.5, tube=0.25 → scale = (r/0.5, r/0.5, r/0.5) avec tube/r = 0.5 fixé.
// Pour exposer les deux paramètres indépendants, on scale X=Z sur r, Y sur tube.
static Value gfx_torus(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Vector3 pos{(float)numArg(args, argc, 0, "graphics.torus"), (float)numArg(args, argc, 1, "graphics.torus"),
                (float)numArg(args, argc, 2, "graphics.torus")};
    float r    = (float)numArg(args, argc, 3, "graphics.torus");
    float tube = (float)numArg(args, argc, 4, "graphics.torus");
    // mesh : major=1 (XY), tube=0.3 (Z) → scale XY par r, Z par tube/0.3
    if (gfxHasFill())
        pushInstance(getShapeMesh(SH_TORUS), s_cur_tex3d, pos, {r, r, tube / 0.3f}, gfxFillColor());
    if (gfxHasStroke())
        DrawCircle3D(pos, r, {1, 0, 0}, 90.0f, gfxStrokeColor());
    return Value{};
}

// graphics.plane(x,y,z, sx,sz) : plan horizontal (XZ) centré en (x,y,z), taille
// sx×sz. Instancié + éclairé (utilise la couleur fill ; sinon stroke pour rester visible).
static Value gfx_plane(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Vector3 pos{(float)numArg(args, argc, 0, "graphics.plane"), (float)numArg(args, argc, 1, "graphics.plane"),
                (float)numArg(args, argc, 2, "graphics.plane")};
    float sx = (float)numArg(args, argc, 3, "graphics.plane");
    float sz = (float)numArg(args, argc, 4, "graphics.plane");
    if (gfxHasFill() || gfxHasStroke()) {   // rien à dessiner si ni fill ni stroke (cohérent avec cube/sphere)
        Color c = gfxHasFill() ? gfxFillColor() : gfxStrokeColor();
        pushInstance(getShapeMesh(SH_PLANE), s_cur_tex3d, pos, Vector3{sx, 1.0f, sz}, c);
    }
    return Value{};
}

// graphics.line3d(x1,y1,z1, x2,y2,z2) : segment 3D — rendu comme un cylindre (rayon = strokeSize * 0.02).
static Value gfx_line3d(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Vector3 a{(float)numArg(args, argc, 0, "graphics.line3d"), (float)numArg(args, argc, 1, "graphics.line3d"),
              (float)numArg(args, argc, 2, "graphics.line3d")};
    Vector3 b{(float)numArg(args, argc, 3, "graphics.line3d"), (float)numArg(args, argc, 4, "graphics.line3d"),
              (float)numArg(args, argc, 5, "graphics.line3d")};
    float r = gfxStrokeSize() * 0.02f;
    DrawCylinderEx(a, b, r, r, 6, gfxStrokeColor());
    return Value{};
}

// graphics.point3d(x,y,z) : point 3D — rendu comme une petite sphère (rayon = strokeSize * 0.015).
static Value gfx_point3d(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    float x = (float)numArg(args, argc, 0, "graphics.point3d");
    float y = (float)numArg(args, argc, 1, "graphics.point3d");
    float z = (float)numArg(args, argc, 2, "graphics.point3d");
    float r = gfxStrokeSize() * 0.015f;
    pushInstance(getShapeMesh(SH_SPHERE), s_cur_tex3d, {x, y, z}, {2.0f * r, 2.0f * r, 2.0f * r}, gfxStrokeColor());
    return Value{};
}

// graphics.rotateq(q) : applique la rotation du quaternion q dans la pile de
// transformation courante — comme rotate/rotateX-Y-Z mais depuis un Quat. Donc
// composable, compatible push/pop, appliqué aux solides instanciés ET immédiats.
// rlMultMatrixf gauche-multiplie (comme rlRotatef) → composition identique.
static Value gfx_rotateq(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 1)
        throw std::runtime_error("graphics.rotateq: expected a Quat (graphics.quat…)");
    Matrix m = QuaternionToMatrix(quatFromInstance(args[0], "graphics.rotateq"));
    rlMultMatrixf(MatrixToFloatV(m).v);
    return Value{};
}

// ── Modèles externes (OBJ/GLTF…) ────────────────────────────────────────────
// raylib n'a pas de LoadModel depuis mémoire : on stocke les OCTETS préchargés
// (par nom) puis, au 1er usage (contexte GL prêt), on écrit dans le FS et LoadModel.
// Le chargement GPU est PARESSEUX (après graphics.canvas → InitWindow) et mis en
// cache. Le rendu réutilise le batcher : drawModel empile les meshes du modèle
// comme instances → mêmes éclairage/fill/instancing que les primitives.
// (PendingModel/s_model_bytes/s_model_cache sont déclarés plus haut car
// reset3dGraphicsState les référence.)

// Préchargement depuis JS/natif : mémorise les octets bruts (chargement GPU différé).
void model_preload_bytes(const std::string& name, std::vector<unsigned char> bytes, const std::string& ext) {
    s_model_bytes[name] = PendingModel{std::move(bytes), ext};
}

// Récupère (et charge en GPU à la demande) le modèle `name`. Cherche : cache →
// octets préchargés (écriture FS + LoadModel) → chemin de fichier direct (natif /
// asset écrit dans MEMFS). Renvoie nullptr si introuvable/illisible.
static Model* modelGet(const std::string& name) {
    auto c = s_model_cache.find(name);
    if (c != s_model_cache.end()) {
        return &c->second;
    }
    Model m{};
    auto p = s_model_bytes.find(name);
    if (p != s_model_bytes.end()) {
        // raylib LoadModel lit un FICHIER → on écrit les octets dans le FS (MEMFS
        // sur WASM) puis on charge, et on nettoie le fichier de travail.
        std::string path = std::string("ollin_model") + p->second.ext;
        FILE* f = fopen(path.c_str(), "wb");
        if (!f) {
            return nullptr;
        }
        fwrite(p->second.bytes.data(), 1, p->second.bytes.size(), f);
        fclose(f);
        m = LoadModel(path.c_str());
        remove(path.c_str());
    } else {
        // Repli : charger directement depuis un chemin (natif, ou asset en MEMFS).
        m = LoadModel(name.c_str());
    }
    if (m.meshCount <= 0) {
        UnloadModel(m);
        return nullptr;
    }
    s_model_cache[name] = m;
    return &s_model_cache[name];
}

// graphics.model(name) : renvoie un handle {name} vers un modèle préchargé (ou un
// chemin chargeable). Déclenche le chargement (erreur si introuvable).
static Value gfx_model(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 1 || !args[0].isString()) {
        throw std::runtime_error("graphics.model: expected a model name (string)");
    }
    const std::string& name = args[0].asString();
    if (!modelGet(name)) {
        throw std::runtime_error("graphics.model: modèle introuvable ou illisible : " + name);
    }
    Value h = Value::makeMap();
    h.mapSet(Value(std::string("name")), Value(name));
    return h;
}

// graphics.drawModel(handle [, x, y, z [, scale]]) : dans un bloc begin3d, empile
// les meshes du modèle comme instances (transfo courante · translate · scale,
// teinte = fill) → éclairage + instancing du batcher.
static Value gfx_draw_model(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 1 || !args[0].isMap()) {
        throw std::runtime_error("graphics.drawModel: expected a model handle (graphics.model)");
    }
    Value nameV = args[0].mapGet(Value(std::string("name")));
    if (!nameV.isString()) {
        throw std::runtime_error("graphics.drawModel: handle de modèle invalide");
    }
    Model* mdl = modelGet(nameV.asString());
    if (!mdl) {
        throw std::runtime_error("graphics.drawModel: modèle introuvable : " + nameV.asString());
    }
    float x = argc > 1 ? (float)numArg(args, argc, 1, "graphics.drawModel") : 0.0f;
    float y = argc > 2 ? (float)numArg(args, argc, 2, "graphics.drawModel") : 0.0f;
    float z = argc > 3 ? (float)numArg(args, argc, 3, "graphics.drawModel") : 0.0f;
    float s = argc > 4 ? (float)numArg(args, argc, 4, "graphics.drawModel") : 1.0f;
    Vector3 pos{x, y, z};
    Vector3 size{s, s, s};
    // fill = teinte GLOBALE (multiplicateur). fill blanc → le modèle garde ses
    // propres couleurs/textures ; fill coloré → il teinte le modèle.
    Color fill = gfxHasFill() ? gfxFillColor() : WHITE;
    for (int i = 0; i < mdl->meshCount; i++) {
        // Matériau du mesh (GLB/GLTF) : texture diffuse + couleur de base.
        unsigned int texId = s_cur_tex3d;   // défaut : texture 3D courante (ou blanche)
        Color base = WHITE;
        int mi = mdl->meshMaterial ? mdl->meshMaterial[i] : 0;
        if (mdl->materials && mi >= 0 && mi < mdl->materialCount) {
            const MaterialMap& diff = mdl->materials[mi].maps[MATERIAL_MAP_DIFFUSE];
            if (diff.texture.id != 0) {
                texId = diff.texture.id;   // texture du matériau (prioritaire)
            }
            base = diff.color;             // baseColorFactor (glTF) — blanc par défaut (OBJ)
        }
        // tint = couleur de base du matériau × fill (composantes).
        Color tint{(unsigned char)(base.r * fill.r / 255), (unsigned char)(base.g * fill.g / 255),
                   (unsigned char)(base.b * fill.b / 255), (unsigned char)(base.a * fill.a / 255)};
        pushInstance(mdl->meshes[i], texId, pos, size, tint);
    }
    return Value{};
}

// graphics.modelSize(handle) : dimensions du modèle (boîte englobante) →
// map { w, h, d, cx, cy, cz, radius }. radius = rayon de la sphère englobante
// (demi-diagonale). À appeler UNE fois (le parcours des sommets n'est pas gratuit).
static Value gfx_model_size(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 1 || !args[0].isMap()) {
        throw std::runtime_error("graphics.modelSize: expected a model handle (graphics.model)");
    }
    Value nameV = args[0].mapGet(Value(std::string("name")));
    if (!nameV.isString()) {
        throw std::runtime_error("graphics.modelSize: handle de modèle invalide");
    }
    Model* mdl = modelGet(nameV.asString());
    if (!mdl) {
        throw std::runtime_error("graphics.modelSize: modèle introuvable : " + nameV.asString());
    }
    BoundingBox bb = GetModelBoundingBox(*mdl);
    float w = bb.max.x - bb.min.x;
    float h = bb.max.y - bb.min.y;
    float d = bb.max.z - bb.min.z;
    Value r = Value::makeMap();
    r.mapSet(Value(std::string("w")), Value((double)w));
    r.mapSet(Value(std::string("h")), Value((double)h));
    r.mapSet(Value(std::string("d")), Value((double)d));
    r.mapSet(Value(std::string("cx")), Value((double)((bb.min.x + bb.max.x) * 0.5f)));
    r.mapSet(Value(std::string("cy")), Value((double)((bb.min.y + bb.max.y) * 0.5f)));
    r.mapSet(Value(std::string("cz")), Value((double)((bb.min.z + bb.max.z) * 0.5f)));
    r.mapSet(Value(std::string("radius")), Value((double)(0.5f * std::sqrt(w * w + h * h + d * d))));
    return r;
}

// graphics.fitDistance(radius [, fovy]) : distance de caméra pour qu'une sphère de
// rayon `radius` tienne ENTIÈREMENT dans la vue, selon le RATIO d'écran courant
// (portrait/paysage) et le champ de vision vertical `fovy` (degrés, 45 défaut). En
// paysage la contrainte est verticale ; en portrait, horizontale — on prend le plus
// petit demi-angle. À appeler chaque frame (bon marché) → suit les rotations d'écran.
static Value gfx_fit_distance(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    double radius = numArg(args, argc, 0, "graphics.fitDistance");
    double fovy = argc > 1 ? numArg(args, argc, 1, "graphics.fitDistance") : 45.0;
    int sh = GetScreenHeight();
    int sw = GetScreenWidth();
    double aspect = (sh > 0) ? (double)sw / (double)sh : 1.0;
    double halfV = fovy * DEG2RAD * 0.5;
    double halfH = std::atan(std::tan(halfV) * aspect);
    double half = halfV < halfH ? halfV : halfH;
    double s = std::sin(half);
    return Value((s > 1e-4) ? radius / s : radius * 10.0);
}

// graphics.inFrustum(x, y, z [, radius]) : la sphère (centre, rayon) est-elle
// (au moins partiellement) DANS le champ de vision de la caméra courante ? →
// 1 (visible) / 0 (hors-champ). Sert au culling par chunk (on ne dessine que le
// visible). À appeler DANS un bloc begin3d/end3d (la vue/projection du frame y
// sont posées). Test exact : 6 plans du frustum extraits de view·projection.
static Value gfx_in_frustum(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    float x = (float)numArg(args, argc, 0, "graphics.inFrustum");
    float y = (float)numArg(args, argc, 1, "graphics.inFrustum");
    float z = (float)numArg(args, argc, 2, "graphics.inFrustum");
    float r = argc > 3 ? (float)numArg(args, argc, 3, "graphics.inFrustum") : 0.0f;
    // Utilise la projection FIGÉE au begin3d (s_proj3d), pas rlGetMatrixProjection()
    // en direct : le culling par chunk est fait AVANT begin3d, où la projection
    // courante est l'ortho 2D restaurée par le end3d précédent → frustum faux
    // (chunks lointains cullés à tort ; ils « apparaissent » en approchant).
    Matrix vp = MatrixMultiply(s_view3d, s_proj3d);
    // Lignes de VP (clip.x/y/z/w = ligne · (x,y,z,1)), layout colonne-major raylib.
    float rows[4][4] = {
        {vp.m0, vp.m4, vp.m8, vp.m12},   // clip.x
        {vp.m1, vp.m5, vp.m9, vp.m13},   // clip.y
        {vp.m2, vp.m6, vp.m10, vp.m14},  // clip.z
        {vp.m3, vp.m7, vp.m11, vp.m15},  // clip.w
    };
    // 6 plans = ligne_w ± ligne_i (gauche/droite, bas/haut, near/far).
    for (int i = 0; i < 3; i++) {
        for (int sgn = 0; sgn < 2; sgn++) {
            float a = rows[3][0] + (sgn ? -rows[i][0] : rows[i][0]);
            float b = rows[3][1] + (sgn ? -rows[i][1] : rows[i][1]);
            float c = rows[3][2] + (sgn ? -rows[i][2] : rows[i][2]);
            float d = rows[3][3] + (sgn ? -rows[i][3] : rows[i][3]);
            float len = std::sqrt(a * a + b * b + c * c);
            if (len < 1e-6f) {
                continue;
            }
            float dist = (a * x + b * y + c * z + d) / len;
            if (dist < -r) {
                return Value((int64_t)0);   // entièrement du mauvais côté d'un plan → hors-champ
            }
        }
    }
    return Value((int64_t)1);
}

// graphics.beginChunk() : démarre l'enregistrement d'un groupe de cubes. Les
// graphics.cube(...) suivants sont CUITS (pas dessinés). Appeler dans setup (le
// contexte GL doit être prêt : après graphics.canvas).
static Value gfx_begin_chunk(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    s_recording = true;
    s_rec_x.clear();
    s_rec_c.clear();
    s_rec_t.clear();
    s_rec_xw.clear();
    s_rec_cw.clear();
    s_rec_tw.clear();
    return Value{};
}

// Construit un InstGroup (VBO persistants) depuis des vecteurs d'instances cuits.
static InstGroup buildGroup(const Mesh& mesh, const std::vector<Matrix>& xs, const std::vector<float>& cs,
                            const std::vector<float>& ts) {
    InstGroup g{};
    g.mesh = mesh;
    g.count = (int)xs.size();
    if (g.count > 0) {
        std::vector<float16> xf(g.count);
        for (int i = 0; i < g.count; i++) {
            xf[i] = MatrixToFloatV(xs[i]);
        }
        g.vboX = rlLoadVertexBuffer(xf.data(), g.count * (int)sizeof(float16), false);
        g.vboC = rlLoadVertexBuffer(cs.data(), g.count * 4 * (int)sizeof(float), false);
        g.vboT = rlLoadVertexBuffer(ts.data(), g.count * 3 * (int)sizeof(float), false);
    }
    return g;
}

// Range un groupe cuit dans s_groups en réutilisant un slot libéré si dispo (borne
// la croissance en streaming infini) ; sinon agrandit. Renvoie l'id 1-based.
static int placeGroup(const InstGroup& g) {
    if (!s_free_groups.empty()) {
        int idx = s_free_groups.back();
        s_free_groups.pop_back();
        s_groups[idx] = g;
        return idx + 1;
    }
    s_groups.push_back(g);
    return (int)s_groups.size();
}

// graphics.endChunk() : cuit les cubes enregistrés dans des VBO persistants et
// renvoie un handle { id, idw, count, wcount }. `id` = groupe OPAQUE, `idw` = groupe
// TRANSPARENT (eau, idw=0 si aucune eau). À redessiner chaque frame : drawChunk
// (opaque) puis, après TOUT l'opaque, drawChunkAlpha (eau).
static Value gfx_end_chunk(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    s_recording = false;
    InstGroup g = buildGroup(s_rec_mesh, s_rec_x, s_rec_c, s_rec_t);
    InstGroup w = buildGroup(s_rec_mesh_w, s_rec_xw, s_rec_cw, s_rec_tw);
    int idO = placeGroup(g);
    int idW = 0;                       // pas de slot si pas d'eau (évite un groupe vide)
    if (w.count > 0) {
        idW = placeGroup(w);
    }
    s_rec_x.clear();
    s_rec_c.clear();
    s_rec_t.clear();
    s_rec_xw.clear();
    s_rec_cw.clear();
    s_rec_tw.clear();
    Value h = Value::makeMap();
    h.mapSet(Value(std::string("id")), Value((int64_t)idO));
    h.mapSet(Value(std::string("idw")), Value((int64_t)idW));
    h.mapSet(Value(std::string("count")), Value((int64_t)g.count));
    h.mapSet(Value(std::string("wcount")), Value((int64_t)w.count));
    return h;
}

// graphics.drawChunk(handle) : redessine un groupe cuit en UN appel instancié
// (éclairé). À appeler DANS un bloc begin3d. Ne ré-émet AUCUN cube depuis Ollin.
static Value gfx_draw_chunk(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 1 || !args[0].isMap()) {
        throw std::runtime_error("graphics.drawChunk: expected a chunk handle (graphics.endChunk)");
    }
    Value idv = args[0].mapGet(Value(std::string("id")));
    if (!idv.isInteger()) {
        throw std::runtime_error("graphics.drawChunk: handle de chunk invalide");
    }
    int id = (int)idv.asInt();
    if (id < 1 || id > (int)s_groups.size()) {
        return Value{};
    }
    InstGroup& g = s_groups[id - 1];
    if (g.count <= 0 || g.vboX == 0) {
        return Value{};
    }
    if (!litBeginDraw()) {
        return Value{};
    }
    litBindInstances(g.mesh.vaoId, g.vboX, g.vboC, g.vboT);
    // Atlas lié si déclaré (tuiles≥0 échantillonnent l'atlas) ; sinon blanc (couleur
    // pleine). CONTRAT : avec un tileset actif, donner une tuile à CHAQUE cube du
    // chunk — un cube à tuile -1 échantillonnerait l'atlas @ fragTexCoord (tuile 0)
    // au lieu d'une couleur pleine.
    litDrawInstanced(g.mesh, s_atlas_texid, g.count);
    rlDisableShader();
    return Value{};
}

// graphics.drawChunkAlpha(handle) : dessine le groupe TRANSPARENT du chunk (eau) en
// mélange alpha (on voit le fond opaque déjà dessiné à travers). Depth test+write
// gardés → la surface d'eau s'occlude proprement (pas d'accumulation entre couches).
// À appeler DANS begin3d APRÈS avoir dessiné TOUT l'opaque (drawChunk) des chunks.
static Value gfx_draw_chunk_alpha(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 1 || !args[0].isMap()) {
        return Value{};
    }
    Value idv = args[0].mapGet(Value(std::string("idw")));
    if (!idv.isInteger()) {
        return Value{};
    }
    int id = (int)idv.asInt();
    if (id < 1 || id > (int)s_groups.size()) {
        return Value{};
    }
    InstGroup& g = s_groups[id - 1];
    if (g.count <= 0 || g.vboX == 0) {
        return Value{};
    }
    if (!litBeginDraw()) {
        return Value{};
    }
    BeginBlendMode(BLEND_ALPHA);
    litBindInstances(g.mesh.vaoId, g.vboX, g.vboC, g.vboT);
    litDrawInstanced(g.mesh, s_atlas_texid, g.count);
    rlDisableShader();
    EndBlendMode();
    return Value{};
}

// graphics.freeChunk(handle) : libère les VBO d'un groupe cuit (chunk lointain
// déchargé) → mémoire GPU récupérée. Le handle devient un no-op au dessin. Permet
// un monde INFINI : on cuit les chunks autour du joueur, on libère les autres.
static void freeGroupById(Value& handle, const char* key) {
    Value idv = handle.mapGet(Value(std::string(key)));
    if (!idv.isInteger()) {
        return;
    }
    int id = (int)idv.asInt();
    if (id < 1 || id > (int)s_groups.size()) {
        return;
    }
    InstGroup& g = s_groups[id - 1];
    bool live = g.vboX != 0 || g.vboC != 0 || g.vboT != 0 || g.count != 0;
    if (g.vboX) {
        rlUnloadVertexBuffer(g.vboX);
        g.vboX = 0;
    }
    if (g.vboC) {
        rlUnloadVertexBuffer(g.vboC);
        g.vboC = 0;
    }
    if (g.vboT) {
        rlUnloadVertexBuffer(g.vboT);
        g.vboT = 0;
    }
    g.count = 0;
    // slot rendu au pool UNIQUEMENT s'il était vivant → double-free idempotent
    // (2ᵉ libération du même handle = no-op, pas de slot dupliqué dans le pool).
    if (live) {
        s_free_groups.push_back(id - 1);
    }
}

static Value gfx_free_chunk(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 1 || !args[0].isMap()) {
        return Value{};
    }
    freeGroupById(args[0], "id");    // groupe opaque
    freeGroupById(args[0], "idw");   // groupe transparent (eau)
    return Value{};
}

// Remet la texture 3D courante (appelé chaque frame par resetStyles, côté 2D).
void reset3dFrameState() {
    s_cur_tex3d = 0;
    s_cur_tile[0] = -1.0f;
    s_cur_tile[1] = -1.0f;
    s_cur_tile[2] = -1.0f;
}

// Texture 3D courante — exposée pour la sauvegarde/restauration de style (push/pushStyle).
unsigned int gfx3dGetTexture() {
    return s_cur_tex3d;
}
void gfx3dSetTexture(unsigned int id) {
    s_cur_tex3d = id;
}

// Enregistre les builtins 3D dans le module graphics (appelé par makeGraphicsModule).
void register3dGraphics(Value& m) {
    m.mapSet(Value(std::string("camera")), Value::makeBuiltin(gfx_camera));
    m.mapSet(Value(std::string("cameraOrtho")), Value::makeBuiltin(gfx_camera_ortho));
    m.mapSet(Value(std::string("begin3d")), Value::makeBuiltin(gfx_begin3d));
    m.mapSet(Value(std::string("end3d")), Value::makeBuiltin(gfx_end3d));
    m.mapSet(Value(std::string("ambient")), Value::makeBuiltin(gfx_ambient));
    m.mapSet(Value(std::string("light")), Value::makeBuiltin(gfx_light));
    m.mapSet(Value(std::string("texture")), Value::makeBuiltin(gfx_texture));
    m.mapSet(Value(std::string("noTexture")), Value::makeBuiltin(gfx_no_texture));
    m.mapSet(Value(std::string("tileset")), Value::makeBuiltin(gfx_tileset));
    m.mapSet(Value(std::string("tiles")), Value::makeBuiltin(gfx_tiles));
    m.mapSet(Value(std::string("tile")), Value::makeBuiltin(gfx_tile));
    m.mapSet(Value(std::string("tileAnim")), Value::makeBuiltin(gfx_tile_anim));
    m.mapSet(Value(std::string("grid")), Value::makeBuiltin(gfx_grid));
    m.mapSet(Value(std::string("cube")), Value::makeBuiltin(gfx_cube));
    m.mapSet(Value(std::string("sphere")), Value::makeBuiltin(gfx_sphere));
    m.mapSet(Value(std::string("cylinder")), Value::makeBuiltin(gfx_cylinder));
    m.mapSet(Value(std::string("cone")), Value::makeBuiltin(gfx_cone));
    m.mapSet(Value(std::string("torus")), Value::makeBuiltin(gfx_torus));
    m.mapSet(Value(std::string("plane")), Value::makeBuiltin(gfx_plane));
    m.mapSet(Value(std::string("model")), Value::makeBuiltin(gfx_model));
    m.mapSet(Value(std::string("drawModel")), Value::makeBuiltin(gfx_draw_model));
    m.mapSet(Value(std::string("modelSize")), Value::makeBuiltin(gfx_model_size));
    m.mapSet(Value(std::string("fitDistance")), Value::makeBuiltin(gfx_fit_distance));
    m.mapSet(Value(std::string("inFrustum")), Value::makeBuiltin(gfx_in_frustum));
    m.mapSet(Value(std::string("beginChunk")), Value::makeBuiltin(gfx_begin_chunk));
    m.mapSet(Value(std::string("endChunk")), Value::makeBuiltin(gfx_end_chunk));
    m.mapSet(Value(std::string("drawChunk")), Value::makeBuiltin(gfx_draw_chunk));
    m.mapSet(Value(std::string("drawChunkAlpha")), Value::makeBuiltin(gfx_draw_chunk_alpha));
    m.mapSet(Value(std::string("freeChunk")), Value::makeBuiltin(gfx_free_chunk));
    m.mapSet(Value(std::string("line3d")), Value::makeBuiltin(gfx_line3d));
    m.mapSet(Value(std::string("point3d")), Value::makeBuiltin(gfx_point3d));
    m.mapSet(Value(std::string("rotateq")), Value::makeBuiltin(gfx_rotateq));
    registerQuat(m);   // quat / quatAxis / quatEuler (classe Quat, graphics_quat.cpp)
}
