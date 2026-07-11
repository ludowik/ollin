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
#include <stdexcept>
#include <vector>
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

// État 3D propre à cette unité (déplacé depuis la zone de style 2D).
// s_in_3d : vrai entre begin3d et end3d. s_cur_tex3d : texture 3D courante
// (0 = blanche), remise à 0 chaque frame via reset3dFrameState().
static bool s_in_3d = false;
static unsigned int s_cur_tex3d = 0;

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
    Camera3D cam{};
    cam.position = Vector3{get("px", 0), get("py", 0), get("pz", 0)};
    cam.target = Vector3{get("tx", 0), get("ty", 0), get("tz", 0)};
    cam.up = Vector3{get("ux", 0), get("uy", 1), get("uz", 0)};
    cam.fovy = get("fovy", 45.0);
    cam.projection = CAMERA_PERSPECTIVE;
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

// cam.set_pos(x,y,z) : fixe la position de la caméra.
static Value cam_set_pos(Value* args, int argc) {
    Value self = args[0];
    self.mapSet(Value(std::string("px")), Value(numArg(args, argc, 1, "Camera.set_pos")));
    self.mapSet(Value(std::string("py")), Value(numArg(args, argc, 2, "Camera.set_pos")));
    self.mapSet(Value(std::string("pz")), Value(numArg(args, argc, 3, "Camera.set_pos")));
    return self;
}

// cam.look_at(x,y,z) : réoriente la caméra vers le point cible (x,y,z).
static Value cam_look_at(Value* args, int argc) {
    Value self = args[0];
    self.mapSet(Value(std::string("tx")), Value(numArg(args, argc, 1, "Camera.look_at")));
    self.mapSet(Value(std::string("ty")), Value(numArg(args, argc, 2, "Camera.look_at")));
    self.mapSet(Value(std::string("tz")), Value(numArg(args, argc, 3, "Camera.look_at")));
    return self;
}

// cam.move(dx,dy,dz) : translate la caméra ET sa cible du même delta → la
// direction de visée est conservée (déplacement latéral/avant du point de vue).
static Value cam_move(Value* args, int argc) {
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

// cam.orbit(angle, rayon [, hauteur]) : place la caméra en orbite autour de sa
// cible, sur un cercle du plan XZ de rayon `rayon`. `angle` en RADIANS (composable
// avec elapsedTime / math.cos-sin). `hauteur` optionnelle = altitude AU-DESSUS de
// la cible (par défaut : conserve la hauteur courante).
static Value cam_orbit(Value* args, int argc) {
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
    cls.mapSet(Value(std::string("set_pos")), Value::makeBuiltin(cam_set_pos));
    cls.mapSet(Value(std::string("look_at")), Value::makeBuiltin(cam_look_at));
    cls.mapSet(Value(std::string("move")), Value::makeBuiltin(cam_move));
    cls.mapSet(Value(std::string("orbit")), Value::makeBuiltin(cam_orbit));
    return cls;
}

// Classe Camera partagée (construite une fois, réutilisée par chaque instance).
static Value cameraClass() {
    static Value cls = makeCameraClass();
    return cls;
}

// graphics.camera(px,py,pz, tx,ty,tz [, fovy]) : INSTANCE de classe Camera.
// Regarde (tx,ty,tz) depuis (px,py,pz), up = +Y, fovy = champ de vision vertical
// (45° défaut). Mutable via ses méthodes (set_pos/look_at/move/orbit).
static Value gfx_camera(Value* args, int argc) {
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

// ── Batcher 3D instancié + éclairé ──────────────────────────────────────────
// begin3d ouvre la collecte ; cube/sphere/… EMPILENT une instance {transfo, tint}
// dans le bucket de leur (mesh, texture) ; end3d résout chaque bucket en UN
// DrawMeshInstanced custom (transfo + couleur PAR INSTANCE via 2 VBO d'instance)
// avec le shader Blinn-Phong. → N formes de même (mesh,texture) = 1 draw call.

enum Shape3D { SH_CUBE = 0, SH_SPHERE = 1, SH_CYLINDER = 2, SH_PLANE = 3, SH_COUNT = 4 };

struct Bucket3D {
    int shape;
    unsigned int texId;
    std::vector<Matrix> xforms;
    std::vector<float> colors;   // 4 floats (rgba 0..1) par instance
};
static std::vector<Bucket3D> s_buckets;
static Camera3D s_cam3d{};   // caméra du bloc begin3d courant (pour viewPos)
static Matrix s_view3d = MatrixIdentity();   // vue figée au begin3d (MVP des solides) ; identité par défaut (fail-safe si flush avant begin3d)

// Meshes unitaires en cache (normales + UV propres via GenMesh*).
static Mesh s_shape_mesh[SH_COUNT];
static bool s_shape_ready[SH_COUNT] = {false, false, false, false};
static Mesh getShapeMesh(int shape) {
    if (!s_shape_ready[shape]) {
        switch (shape) {
            case SH_CUBE:
                s_shape_mesh[shape] = GenMeshCube(1.0f, 1.0f, 1.0f);
                break;
            case SH_SPHERE:
                s_shape_mesh[shape] = GenMeshSphere(0.5f, 24, 24);
                break;
            case SH_CYLINDER:
                s_shape_mesh[shape] = GenMeshCylinder(1.0f, 1.0f, 16);
                break;
            default:
                s_shape_mesh[shape] = GenMeshPlane(1.0f, 1.0f, 1, 1);
                break;
        }
        s_shape_ready[shape] = true;
    }
    return s_shape_mesh[shape];
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
static int s_loc_l_en = -1, s_loc_l_type = -1, s_loc_l_pos = -1, s_loc_l_tgt = -1, s_loc_l_col = -1;

// VBO d'instance PERSISTANTS (transfo + couleur) : réutilisés d'une frame à
// l'autre (mis à jour par glBufferSubData), au lieu d'être créés/détruits à
// chaque bucket/frame. Capacités en octets ; agrandissement seulement.
static unsigned int s_inst_vbo_xform = 0, s_inst_vbo_color = 0;
static int s_inst_cap_xform = 0, s_inst_cap_color = 0;

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
        "uniform mat4 mvp;\n"
        "out vec3 fragPosition;\n"
        "out vec2 fragTexCoord;\n"
        "out vec4 fragColor;\n"
        "out vec3 fragNormal;\n"
        "void main() {\n"
        "    mat4 m = instanceTransform;\n"
        "    vec4 wp = m * vec4(vertexPosition, 1.0);\n"
        "    fragPosition = wp.xyz;\n"
        "    fragTexCoord = vertexTexCoord;\n"
        "    fragColor = instanceColor;\n"
        "    mat3 nm = transpose(inverse(mat3(m)));\n"   // matrice de normale : correcte sous rotation / scale non uniforme
        "    fragNormal = normalize(nm * vertexNormal);\n"
        "    gl_Position = mvp * wp;\n"
        "}\n";
    std::string fs = std::string(HDR) +
        "in vec3 fragPosition;\n"
        "in vec2 fragTexCoord;\n"
        "in vec4 fragColor;\n"
        "in vec3 fragNormal;\n"
        "uniform sampler2D texture0;\n"
        "uniform vec4 ambient;\n"
        "uniform vec3 viewPos;\n"
        "struct Light { int enabled; int type; vec3 position; vec3 target; vec4 color; };\n"
        "uniform Light light0;\n"
        "out vec4 finalColor;\n"
        "void main() {\n"
        "    vec4 texel = texture(texture0, fragTexCoord);\n"
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
    s_loc_viewpos = GetShaderLocation(s_lit, "viewPos");
    s_loc_ambient = GetShaderLocation(s_lit, "ambient");
    s_loc_l_en = GetShaderLocation(s_lit, "light0.enabled");
    s_loc_l_type = GetShaderLocation(s_lit, "light0.type");
    s_loc_l_pos = GetShaderLocation(s_lit, "light0.position");
    s_loc_l_tgt = GetShaderLocation(s_lit, "light0.target");
    s_loc_l_col = GetShaderLocation(s_lit, "light0.color");
    s_lit_ready = true;
}

// Bucket courant pour (shape, texture courante) — créé à la demande.
static Bucket3D& bucketFor(int shape) {
    for (auto& b : s_buckets) {
        if (b.shape == shape && b.texId == s_cur_tex3d) {
            return b;
        }
    }
    s_buckets.push_back(Bucket3D{shape, s_cur_tex3d, {}, {}});
    return s_buckets.back();
}

// Empile une instance (transfo translate·scale + couleur fill) dans son bucket.
static void pushInstance(int shape, Vector3 pos, Vector3 size, Color col) {
    Bucket3D& b = bucketFor(shape);
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
}

// Résout un bucket en UN appel instancié (transfo + couleur par instance).
static void flushBucket(const Bucket3D& b) {
    int n = (int)b.xforms.size();
    if (n == 0) {
        return;
    }
    loadLitShader();
    if (s_lit.id == 0) {   // shader indisponible (échec de compilation) → ne rien dessiner
        return;
    }
    Mesh mesh = getShapeMesh(b.shape);
    rlEnableShader(s_lit.id);

    // Uniforms : MVP = view·proj. La vue est celle FIGÉE au begin3d (s_view3d) — pas
    // la modelview courante — pour qu'une transfo « nue » (hors push/pop, qui écrit
    // dans la modelview) ne décale pas rétroactivement TOUS les buckets. La transfo
    // par instance (pile push/pop) est appliquée dans le shader via instanceTransform.
    Matrix matProj = rlGetMatrixProjection();
    Matrix mvp = MatrixMultiply(s_view3d, matProj);
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

    // VBO d'instance PERSISTANTS (mis à jour, pas recréés) : transfo (mat4 = 4
    // attributs vec4) puis couleur (vec4), tous deux divisor 1. Les attributs sont
    // ré-attachés au VAO du mesh à chaque flush (le VBO peut avoir grossi) ; ils ne
    // sont donc jamais laissés pendants sur un buffer libéré.
    std::vector<float16> xf(n);
    for (int i = 0; i < n; i++) {
        xf[i] = MatrixToFloatV(b.xforms[i]);
    }
    rlEnableVertexArray(mesh.vaoId);
    uploadInstanceVBO(s_inst_vbo_xform, s_inst_cap_xform, xf.data(), n * (int)sizeof(float16));
    int locT = s_lit.locs[SHADER_LOC_VERTEX_INSTANCETRANSFORM];
    for (unsigned int i = 0; i < 4; i++) {
        rlEnableVertexAttribute(locT + i);
        rlSetVertexAttribute(locT + i, 4, RL_FLOAT, 0, sizeof(Matrix), i * sizeof(Vector4));
        rlSetVertexAttributeDivisor(locT + i, 1);
    }
    uploadInstanceVBO(s_inst_vbo_color, s_inst_cap_color, b.colors.data(), n * 4 * (int)sizeof(float));
    if (s_loc_instcolor >= 0) {
        rlEnableVertexAttribute(s_loc_instcolor);
        rlSetVertexAttribute(s_loc_instcolor, 4, RL_FLOAT, 0, 0, 0);
        rlSetVertexAttributeDivisor(s_loc_instcolor, 1);
    }
    rlDisableVertexBuffer();
    rlDisableVertexArray();

    // Texture (slot 0).
    rlActiveTextureSlot(0);
    rlEnableTexture(b.texId ? b.texId : whiteTexId());
    int slot = 0;
    rlSetUniform(s_lit.locs[SHADER_LOC_MAP_DIFFUSE], &slot, RL_SHADER_UNIFORM_INT, 1);

    // Dessin instancié (le VAO du mesh porte déjà position/uv/normale [+ indices]).
    rlEnableVertexArray(mesh.vaoId);
    if (mesh.indices != nullptr) {
        rlDrawVertexArrayElementsInstanced(0, mesh.triangleCount * 3, 0, n);
    } else {
        rlDrawVertexArrayInstanced(0, mesh.vertexCount, n);
    }
    rlDisableVertexArray();

    rlActiveTextureSlot(0);
    rlDisableTexture();
    rlDisableShader();
    // VBO d'instance NON déchargés ici : ils sont persistants (réutilisés la frame
    // suivante), libérés seulement par reset3dGraphicsState (destruction du contexte).
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
    for (int i = 0; i < SH_COUNT; i++) {
        if (s_shape_ready[i]) {
            UnloadMesh(s_shape_mesh[i]);
            s_shape_mesh[i] = Mesh{};
            s_shape_ready[i] = false;
        }
    }
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
    s_buckets.clear();
    s_in_3d = false;
    s_cur_tex3d = 0;
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

static Value gfx_begin3d(Value* args, int argc) {
    if (argc < 1)
        throw std::runtime_error("graphics.begin3d: expected a camera (graphics.camera)");
    s_cam3d = cameraFromMap(args[0], "graphics.begin3d");
    s_buckets.clear();
    BeginMode3D(s_cam3d);
    s_view3d = rlGetMatrixModelview();   // vue « pure » (avant toute transfo utilisateur)
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

static Value gfx_end3d(Value* args, int argc) {
    (void)args;
    (void)argc;
    end3dInternal();   // idempotent
    return Value{};
}

// graphics.ambient(v | couleur) : lumière ambiante (active le mode éclairé).
static Value gfx_ambient(Value* args, int argc) {
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

// light.set_dir(x,y,z) : oriente une lumière directionnelle (direction de propagation).
static Value light_set_dir(Value* args, int argc) {
    Value self = args[0];
    self.mapSet(Value(std::string("type")), Value((int64_t)0));
    self.mapSet(Value(std::string("dx")), Value(numArg(args, argc, 1, "Light.set_dir")));
    self.mapSet(Value(std::string("dy")), Value(numArg(args, argc, 2, "Light.set_dir")));
    self.mapSet(Value(std::string("dz")), Value(numArg(args, argc, 3, "Light.set_dir")));
    applyLightFromInstance(self);
    return self;
}

// light.set_pos(x,y,z) : positionne une lumière ponctuelle.
static Value light_set_pos(Value* args, int argc) {
    Value self = args[0];
    self.mapSet(Value(std::string("type")), Value((int64_t)1));
    self.mapSet(Value(std::string("dx")), Value(numArg(args, argc, 1, "Light.set_pos")));
    self.mapSet(Value(std::string("dy")), Value(numArg(args, argc, 2, "Light.set_pos")));
    self.mapSet(Value(std::string("dz")), Value(numArg(args, argc, 3, "Light.set_pos")));
    applyLightFromInstance(self);
    return self;
}

// light.set_color(couleur) : couleur de la lumière.
static Value light_set_color(Value* args, int argc) {
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
static Value light_enable(Value* args, int argc) {
    Value self = args[0];
    bool on = (argc > 1) ? !isFalsy(args[1]) : true;
    self.mapSet(Value(std::string("enabled")), Value((int64_t)(on ? 1 : 0)));
    applyLightFromInstance(self);
    return self;
}

static Value makeLightClass() {
    Value cls = Value::makeClass();
    cls.mapSet(Value(std::string("__name__")), Value(std::string("Light")));
    cls.mapSet(Value(std::string("set_dir")), Value::makeBuiltin(light_set_dir));
    cls.mapSet(Value(std::string("set_pos")), Value::makeBuiltin(light_set_pos));
    cls.mapSet(Value(std::string("set_color")), Value::makeBuiltin(light_set_color));
    cls.mapSet(Value(std::string("enable")), Value::makeBuiltin(light_enable));
    return cls;
}

static Value lightClass() {
    static Value cls = makeLightClass();
    return cls;
}

// graphics.light("dir"|"point", x,y,z [, couleur]) : crée un objet Light et
// l'active. "dir" : (x,y,z) = direction de propagation ; "point" : position.
static Value gfx_light(Value* args, int argc) {
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
static Value gfx_grid(Value* args, int argc) {
    int slices = argc > 0 ? gfxToInt(args[0]) : 10;
    float spacing = argc > 1 ? (float)numArg(args, argc, 1, "graphics.grid") : 1.0f;
    DrawGrid(slices, spacing);
    return Value{};
}

// graphics.texture(img) / graphics.noTexture() : texture 3D courante (handle image).
static Value gfx_texture(Value* args, int argc) {
    if (argc > 0 && args[0].isMap()) {
        Value idv = args[0].mapGet(Value(std::string("id")));
        s_cur_tex3d = idv.isInteger() ? image_gl_texid((int)idv.asInt()) : 0;
    }
    return Value{};
}

static Value gfx_no_texture(Value* args, int argc) {
    (void)args;
    (void)argc;
    s_cur_tex3d = 0;
    return Value{};
}

// graphics.cube(x,y,z, w,h,l) : cube centré en (x,y,z). Plein si fill (instancié,
// éclairé, texturé), arêtes si stroke (immédiat, non éclairé).
static Value gfx_cube(Value* args, int argc) {
    Vector3 pos{(float)numArg(args, argc, 0, "graphics.cube"), (float)numArg(args, argc, 1, "graphics.cube"),
                (float)numArg(args, argc, 2, "graphics.cube")};
    Vector3 size{(float)numArg(args, argc, 3, "graphics.cube"), (float)numArg(args, argc, 4, "graphics.cube"),
                 (float)numArg(args, argc, 5, "graphics.cube")};
    if (gfxHasFill())
        pushInstance(SH_CUBE, pos, size, gfxFillColor());
    if (gfxHasStroke())
        DrawCubeWiresV(pos, size, gfxStrokeColor());
    return Value{};
}

// graphics.sphere(x,y,z, r) : sphère centrée en (x,y,z). Pleine si fill (instanciée,
// éclairée, texturée), fil de fer si stroke (immédiat). Mesh unitaire = rayon 0.5.
static Value gfx_sphere(Value* args, int argc) {
    Vector3 pos{(float)numArg(args, argc, 0, "graphics.sphere"), (float)numArg(args, argc, 1, "graphics.sphere"),
                (float)numArg(args, argc, 2, "graphics.sphere")};
    float r = (float)numArg(args, argc, 3, "graphics.sphere");
    if (gfxHasFill())
        pushInstance(SH_SPHERE, pos, Vector3{2.0f * r, 2.0f * r, 2.0f * r}, gfxFillColor());
    if (gfxHasStroke())
        DrawSphereWires(pos, r, 16, 16, gfxStrokeColor());
    return Value{};
}

// graphics.cylinder(x,y,z, r, h) : cylindre, (x,y,z) = centre de la base, rayon r,
// hauteur h (vers +Y). Plein si fill (instancié), fil de fer si stroke (immédiat).
// Mono-rayon (contrainte de l'instancing : mesh unitaire figé, rayon 1 hauteur 1).
static Value gfx_cylinder(Value* args, int argc) {
    Vector3 pos{(float)numArg(args, argc, 0, "graphics.cylinder"), (float)numArg(args, argc, 1, "graphics.cylinder"),
                (float)numArg(args, argc, 2, "graphics.cylinder")};
    float r = (float)numArg(args, argc, 3, "graphics.cylinder");
    float h = (float)numArg(args, argc, 4, "graphics.cylinder");
    if (gfxHasFill())
        pushInstance(SH_CYLINDER, pos, Vector3{r, h, r}, gfxFillColor());
    if (gfxHasStroke())
        DrawCylinderWires(pos, r, r, h, 16, gfxStrokeColor());
    return Value{};
}

// graphics.plane(x,y,z, sx,sz) : plan horizontal (XZ) centré en (x,y,z), taille
// sx×sz. Instancié + éclairé (utilise la couleur fill ; sinon stroke pour rester visible).
static Value gfx_plane(Value* args, int argc) {
    Vector3 pos{(float)numArg(args, argc, 0, "graphics.plane"), (float)numArg(args, argc, 1, "graphics.plane"),
                (float)numArg(args, argc, 2, "graphics.plane")};
    float sx = (float)numArg(args, argc, 3, "graphics.plane");
    float sz = (float)numArg(args, argc, 4, "graphics.plane");
    if (gfxHasFill() || gfxHasStroke()) {   // rien à dessiner si ni fill ni stroke (cohérent avec cube/sphere)
        Color c = gfxHasFill() ? gfxFillColor() : gfxStrokeColor();
        pushInstance(SH_PLANE, pos, Vector3{sx, 1.0f, sz}, c);
    }
    return Value{};
}

// graphics.line3d(x1,y1,z1, x2,y2,z2) : segment 3D (couleur stroke).
static Value gfx_line3d(Value* args, int argc) {
    Vector3 a{(float)numArg(args, argc, 0, "graphics.line3d"), (float)numArg(args, argc, 1, "graphics.line3d"),
              (float)numArg(args, argc, 2, "graphics.line3d")};
    Vector3 b{(float)numArg(args, argc, 3, "graphics.line3d"), (float)numArg(args, argc, 4, "graphics.line3d"),
              (float)numArg(args, argc, 5, "graphics.line3d")};
    DrawLine3D(a, b, gfxStrokeColor());
    return Value{};
}

// graphics.point3d(x,y,z) : point 3D (couleur stroke).
static Value gfx_point3d(Value* args, int argc) {
    Vector3 p{(float)numArg(args, argc, 0, "graphics.point3d"), (float)numArg(args, argc, 1, "graphics.point3d"),
              (float)numArg(args, argc, 2, "graphics.point3d")};
    DrawPoint3D(p, gfxStrokeColor());
    return Value{};
}

// graphics.rotateq(q) : applique la rotation du quaternion q dans la pile de
// transformation courante — comme rotate/rotateX-Y-Z mais depuis un Quat. Donc
// composable, compatible push/pop, appliqué aux solides instanciés ET immédiats.
// rlMultMatrixf gauche-multiplie (comme rlRotatef) → composition identique.
static Value gfx_rotateq(Value* args, int argc) {
    if (argc < 1)
        throw std::runtime_error("graphics.rotateq: expected a Quat (graphics.quat…)");
    Matrix m = QuaternionToMatrix(quatFromInstance(args[0], "graphics.rotateq"));
    rlMultMatrixf(MatrixToFloatV(m).v);
    return Value{};
}

// Remet la texture 3D courante (appelé chaque frame par resetStyles, côté 2D).
void reset3dFrameState() {
    s_cur_tex3d = 0;
}

// Enregistre les builtins 3D dans le module graphics (appelé par makeGraphicsModule).
void register3dGraphics(Value& m) {
    m.mapSet(Value(std::string("camera")), Value::makeBuiltin(gfx_camera));
    m.mapSet(Value(std::string("begin3d")), Value::makeBuiltin(gfx_begin3d));
    m.mapSet(Value(std::string("end3d")), Value::makeBuiltin(gfx_end3d));
    m.mapSet(Value(std::string("ambient")), Value::makeBuiltin(gfx_ambient));
    m.mapSet(Value(std::string("light")), Value::makeBuiltin(gfx_light));
    m.mapSet(Value(std::string("texture")), Value::makeBuiltin(gfx_texture));
    m.mapSet(Value(std::string("noTexture")), Value::makeBuiltin(gfx_no_texture));
    m.mapSet(Value(std::string("grid")), Value::makeBuiltin(gfx_grid));
    m.mapSet(Value(std::string("cube")), Value::makeBuiltin(gfx_cube));
    m.mapSet(Value(std::string("sphere")), Value::makeBuiltin(gfx_sphere));
    m.mapSet(Value(std::string("cylinder")), Value::makeBuiltin(gfx_cylinder));
    m.mapSet(Value(std::string("plane")), Value::makeBuiltin(gfx_plane));
    m.mapSet(Value(std::string("line3d")), Value::makeBuiltin(gfx_line3d));
    m.mapSet(Value(std::string("point3d")), Value::makeBuiltin(gfx_point3d));
    m.mapSet(Value(std::string("rotateq")), Value::makeBuiltin(gfx_rotateq));
    registerQuat(m);   // quat / quat_axis / quat_euler (classe Quat, graphics_quat.cpp)
}
