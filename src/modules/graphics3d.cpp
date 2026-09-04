// Module graphics — 3D PART. The 2D drawing, the window and render loop, the styles and the
// transforms live in graphics_module.cpp; the boundary between the two units is
// graphics_internal.h. Compiled only in the raylib/WASM builds.
#include "graphics_internal.h"
#include "../paths.h"
#include "shader_sources.h"
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

// 3D state private to this unit.
// s_in_3d: true between begin3d and end3d. s_cur_tex3d: current 3D texture
// (0 = white), reset every frame by reset3d_frame_state().
static bool s_in_3d = false;
static unsigned int s_cur_tex3d = 0;

// Tile atlas (voxel terrain): one texture as a grid (cols×rows). Each cube carries a
// triple of tiles (top/side/bottom); the shader picks according to the normal and samples
// the atlas. s_cur_tile = tiles of the next cube (state, like fill); -1 = no tile
// (plain colour / ordinary texture0).
static unsigned int s_atlas_texid = 0;
// Whether the atlas's rows are bottom-up, answered ONCE when the atlas is declared: the two chunk
// draws asked per call, and image_gl_flipped scans every image — a hundred scans a frame for a
// texture that cannot change until the next tileset().
static bool s_atlas_flipped = false;
static float s_atlas_grid[2] = {1.0f, 1.0f};
static float s_cur_tile[3] = {-1.0f, -1.0f, -1.0f};
// Heights of the four top corners of the next cube (state, like s_cur_tile), in local
// units: (-x,-z), (+x,-z), (-x,+z), (+x,+z). All zero = an ordinary cube.
static float s_cur_corner[4] = {0.0f, 0.0f, 0.0f, 0.0f};
static float s_anim_tile = -1.0f;   // the animated tile, whose UV scrolls, water for one; -1 means none
// Ripple parameters of the animated tile: {scroll, wave speed, spatial frequency,
// amplitude}. Defaults give a water look; tunable through graphics.tileAnim(t, ...).
static float s_anim_params[4] = {0.09f, 1.6f, 8.0f, 0.045f};

// 3D display rests DIRECTLY on raylib's API (Camera3D / BeginMode3D…).
// The camera is a first-class value (a map) built by graphics.camera; begin3d/end3d
// bracket the 3D drawing inside draw(). The shapes follow the fill/stroke state exactly
// as the 2D primitives do (solid if fill, wireframe if stroke, both if both). Depth is
// cleared by a graphics.clear(opaque colour) at the start of the frame (ClearBackground
// clears the colour buffer AND the depth buffer, through rlClearScreenBuffers).

// Rebuilds a raylib Camera3D from the map handle (graphics.camera). Default up = +Y,
// perspective projection, raylib's default near/far.
static Camera3D camera_from_map(const Value& v, const char* fn) {
    if (!v.is_map())
        throw std::runtime_error(std::string(fn) + ": expected a camera (graphics.camera)");
    auto get = [&](const char* k, double def) -> float {
        Value f = v.map_get(Value(std::string(k)));
        return f.is_number() ? (float)f.as_num() : (float)def;
    };
    bool ortho = v.map_get(Value(std::string("ortho"))).is_number() && v.map_get(Value(std::string("ortho"))).as_num() != 0.0;
    Camera3D cam{};
    cam.position = Vector3{get("px", 0), get("py", 0), get("pz", 0)};
    cam.target = Vector3{get("tx", 0), get("ty", 0), get("tz", 0)};
    cam.up = Vector3{get("ux", 0), get("uy", 1), get("uz", 0)};
    cam.fovy = get("fovy", ortho ? 10.0f : 45.0f);
    cam.projection = ortho ? CAMERA_ORTHOGRAPHIC : CAMERA_PERSPECTIVE;
    return cam;
}

// Camera class (native, like Color).
// A camera is a class INSTANCE (a map with __class__) carrying px,py,pz (position),
// tx,ty,tz (target) and fovy. Since an instance is still a T_MAP, camera_from_map reads
// it unchanged. The methods MUTATE self in place (a camera is mutable between frames)
// and return self, so calls chain.
static double cam_field(const Value& self, const char* k) {
    Value v = self.map_get(Value(std::string(k)));
    return v.is_number() ? v.as_num() : 0.0;
}

// cam.setPos(x,y,z): sets the camera position.
static int cam_set_pos(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Value self = args[0];
    self.map_set(Value(std::string("px")), Value(num_arg(args, argc, 1, "Camera.setPos")));
    self.map_set(Value(std::string("py")), Value(num_arg(args, argc, 2, "Camera.setPos")));
    self.map_set(Value(std::string("pz")), Value(num_arg(args, argc, 3, "Camera.setPos")));
    return ctx.ret(self);
}

// cam.lookAt(x,y,z): aims the camera at the target point (x,y,z).
static int cam_look_at(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Value self = args[0];
    self.map_set(Value(std::string("tx")), Value(num_arg(args, argc, 1, "Camera.lookAt")));
    self.map_set(Value(std::string("ty")), Value(num_arg(args, argc, 2, "Camera.lookAt")));
    self.map_set(Value(std::string("tz")), Value(num_arg(args, argc, 3, "Camera.lookAt")));
    return ctx.ret(self);
}

// cam.move(dx,dy,dz): translates the camera AND its target by the same delta, so the
// viewing direction is preserved (a sideways or forward move of the viewpoint).
static int cam_move(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Value self = args[0];
    double dx = num_arg(args, argc, 1, "Camera.move");
    double dy = num_arg(args, argc, 2, "Camera.move");
    double dz = num_arg(args, argc, 3, "Camera.move");
    self.map_set(Value(std::string("px")), Value(cam_field(self, "px") + dx));
    self.map_set(Value(std::string("py")), Value(cam_field(self, "py") + dy));
    self.map_set(Value(std::string("pz")), Value(cam_field(self, "pz") + dz));
    self.map_set(Value(std::string("tx")), Value(cam_field(self, "tx") + dx));
    self.map_set(Value(std::string("ty")), Value(cam_field(self, "ty") + dy));
    self.map_set(Value(std::string("tz")), Value(cam_field(self, "tz") + dz));
    return ctx.ret(self);
}

// cam.zoom(factor): multiplies the size of the visible world (ortho: fovy *= factor;
// perspective: moves the position along the viewing axis).
static int cam_zoom(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Value self = args[0];
    double factor = num_arg(args, argc, 1, "Camera.zoom");
    if (factor <= 0.0) return ctx.ret(self);
    bool ortho = self.map_get(Value(std::string("ortho"))).is_number() && self.map_get(Value(std::string("ortho"))).as_num() != 0.0;
    if (ortho) {
        double fovy = cam_field(self, "fovy");
        self.map_set(Value(std::string("fovy")), Value(std::max(0.01, fovy * factor)));
    } else {
        double tx = cam_field(self, "tx"), ty = cam_field(self, "ty"), tz = cam_field(self, "tz");
        double px = cam_field(self, "px"), py = cam_field(self, "py"), pz = cam_field(self, "pz");
        double dx = px - tx, dy = py - ty, dz = pz - tz;
        self.map_set(Value(std::string("px")), Value(tx + dx * factor));
        self.map_set(Value(std::string("py")), Value(ty + dy * factor));
        self.map_set(Value(std::string("pz")), Value(tz + dz * factor));
    }
    return ctx.ret(self);
}

// cam.orbit(angle, radius [, height]): puts the camera in orbit around its target, on a
// circle of the XZ plane. `angle` is in RADIANS (composable with elapsedTime and
// math.cos/sin). The optional `height` is the altitude ABOVE the target (by default the
// current height is kept).
static int cam_orbit(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Value self = args[0];
    double angle = num_arg(args, argc, 1, "Camera.orbit");
    double radius = num_arg(args, argc, 2, "Camera.orbit");
    double tx = cam_field(self, "tx");
    double ty = cam_field(self, "ty");
    double tz = cam_field(self, "tz");
    double py = (argc > 3) ? ty + num_arg(args, argc, 3, "Camera.orbit") : cam_field(self, "py");
    self.map_set(Value(std::string("px")), Value(tx + std::cos(angle) * radius));
    self.map_set(Value(std::string("py")), Value(py));
    self.map_set(Value(std::string("pz")), Value(tz + std::sin(angle) * radius));
    return ctx.ret(self);
}

// cam.getViewDir(): NORMALISED viewing direction (target - position), as a map {x,y,z}.
// A target equal to the position (a null vector) returns {x:0, y:0, z:0}.
static int cam_get_view_dir(CallCtx& ctx) {
    Value self = ctx.args[0];
    double dx = cam_field(self, "tx") - cam_field(self, "px");
    double dy = cam_field(self, "ty") - cam_field(self, "py");
    double dz = cam_field(self, "tz") - cam_field(self, "pz");
    double len = std::sqrt(dx * dx + dy * dy + dz * dz);
    if (len > 0.0) {
        dx /= len;
        dy /= len;
        dz /= len;
    }
    Value dir = Value::make_map();
    dir.map_set(Value(std::string("x")), Value(dx));
    dir.map_set(Value(std::string("y")), Value(dy));
    dir.map_set(Value(std::string("z")), Value(dz));
    return ctx.ret(dir);
}

static Value make_camera_class() {
    return MapBuilder(Value::make_class())
        .str("__name__", "Camera")
        .fn("setPos", cam_set_pos)
        .fn("lookAt", cam_look_at)
        .fn("move", cam_move)
        .fn("orbit", cam_orbit)
        .fn("zoom", cam_zoom)
        .fn("getViewDir", cam_get_view_dir)
        .done();
}

// Shared Camera class, built once and reused by every instance.
static Value camera_class() {
    static Value cls = make_camera_class();
    return cls;
}

// graphics.camera(px,py,pz, tx,ty,tz [, fovy]): a Camera class INSTANCE. Looks at
// (tx,ty,tz) from (px,py,pz), up = +Y, fovy = vertical field of view (45° by default).
// Mutable through its methods (setPos/lookAt/move/orbit/zoom); getViewDir returns the viewing direction {x,y,z}.
static int gfx_camera(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Value cam = Value::make_map();
    cam.map_set(Value(std::string("__class__")), camera_class());
    cam.map_set(Value(std::string("px")), Value(num_arg(args, argc, 0, "graphics.camera")));
    cam.map_set(Value(std::string("py")), Value(num_arg(args, argc, 1, "graphics.camera")));
    cam.map_set(Value(std::string("pz")), Value(num_arg(args, argc, 2, "graphics.camera")));
    cam.map_set(Value(std::string("tx")), Value(num_arg(args, argc, 3, "graphics.camera")));
    cam.map_set(Value(std::string("ty")), Value(num_arg(args, argc, 4, "graphics.camera")));
    cam.map_set(Value(std::string("tz")), Value(num_arg(args, argc, 5, "graphics.camera")));
    cam.map_set(Value(std::string("fovy")), Value(argc > 6 ? num_arg(args, argc, 6, "graphics.camera") : 45.0));
    return ctx.ret(cam);
}

// graphics.cameraOrtho(px,py,pz, tx,ty,tz [, size]): an orthographic camera. No
// perspective — the visible world is `size` units tall (10 by default). Same methods as
// camera(); zoom() adjusts size.
static int gfx_camera_ortho(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Value cam = Value::make_map();
    cam.map_set(Value(std::string("__class__")), camera_class());
    cam.map_set(Value(std::string("px")), Value(num_arg(args, argc, 0, "graphics.cameraOrtho")));
    cam.map_set(Value(std::string("py")), Value(num_arg(args, argc, 1, "graphics.cameraOrtho")));
    cam.map_set(Value(std::string("pz")), Value(num_arg(args, argc, 2, "graphics.cameraOrtho")));
    cam.map_set(Value(std::string("tx")), Value(num_arg(args, argc, 3, "graphics.cameraOrtho")));
    cam.map_set(Value(std::string("ty")), Value(num_arg(args, argc, 4, "graphics.cameraOrtho")));
    cam.map_set(Value(std::string("tz")), Value(num_arg(args, argc, 5, "graphics.cameraOrtho")));
    cam.map_set(Value(std::string("fovy")), Value(argc > 6 ? num_arg(args, argc, 6, "graphics.cameraOrtho") : 10.0));
    cam.map_set(Value(std::string("ortho")), Value((int64_t)1));
    return ctx.ret(cam);
}

// Instanced and lit 3D batcher.
// begin3d opens the collection; cube/sphere/… PUSH an instance {transform, tint} into the
// bucket of their (mesh, texture); end3d resolves each bucket into ONE custom
// DrawMeshInstanced (transform + colour PER INSTANCE, through two instance VBOs) with the
// Blinn-Phong shader. N shapes sharing a (mesh, texture) therefore cost one draw call.

enum Shape3D { SH_CUBE = 0, SH_SPHERE = 1, SH_CYLINDER = 2, SH_PLANE = 3, SH_CONE = 4, SH_TORUS = 5, SH_COUNT = 6 };

struct Bucket3D {
    unsigned int vaoId;          // the mesh key: it identifies the GPU mesh, a primitive OR an external model
    Mesh mesh;                   // the mesh to draw: a unit primitive, or one of a model's meshes
    unsigned int texId;
    bool flip_v;                // the texture's rows are bottom-up (painted by image.beginDraw)
    std::vector<Matrix> xforms;
    std::vector<float> colors;   // 4 floats (rgba 0..1) par instance
    std::vector<float> tiles;    // 3 floats per instance (top/side/bottom, -1 = none)
    std::vector<float> corners;  // 4 floats per instance: the top's corner heights
};
static std::vector<Bucket3D> s_buckets;
static Camera3D s_cam3d{};   // the current begin3d block's camera, for viewPos

// External models, declared here because reset3d_graphics_state refers to them (definitions further down).
struct PendingModel {
    std::vector<unsigned char> bytes;
    std::string ext;   // with the dot, e.g. ".obj"
};
static std::map<std::string, PendingModel> s_model_bytes;   // the preloaded bytes, by name
static std::map<std::string, Model> s_model_cache;          // the models loaded into the GPU, lazily

// BAKED instance groups (retained geometry).
// beginChunk/endChunk record cubes ONCE into persistent VBOs; drawChunk redraws them
// every frame in a single call, so Ollin no longer has to re-emit each cube every frame
// (per-chunk culling on the script side).
static bool s_recording = false;
static std::vector<Matrix> s_rec_x;   // the recorded local transforms, OPAQUE group
static std::vector<float> s_rec_c;    // the recorded rgba values, 0..1, OPAQUE group
static std::vector<float> s_rec_t;    // the recorded tiles, three floats per instance, OPAQUE group
static std::vector<float> s_rec_k;    // the recorded corner heights, four floats per instance, OPAQUE group
static std::vector<Matrix> s_rec_xw;  // the same, for TRANSPARENT instances (alpha < 1, water for one)
static std::vector<float> s_rec_cw;
static std::vector<float> s_rec_tw;
static std::vector<float> s_rec_kw;
static Mesh s_rec_mesh{};             // the recorded mesh, OPAQUE group: a cube
static Mesh s_rec_mesh_w{};           // the recorded mesh, TRANSPARENT group: a plane, for water
struct InstGroup {
    Mesh mesh;
    unsigned int vbo_x;   // the transforms VBO, persistent
    unsigned int vbo_c;   // the colours VBO, persistent
    unsigned int vbo_t;   // the tiles VBO, persistent, 3 floats per instance
    unsigned int vbo_k;   // the corner heights VBO, persistent, 4 floats per instance
    int count;
};
static std::vector<InstGroup> s_groups;   // the baked groups (index+1 = id)
static std::vector<int> s_free_groups;    // freed slots, reusable, which bounds s_groups while streaming
static Matrix s_view3d = MatrixIdentity();   // the view frozen at begin3d, for the solids' MVP; the identity by default, as a fail-safe should a flush precede begin3d
static Matrix s_proj3d = MatrixIdentity();   // the perspective projection frozen at begin3d, for inFrustum called OUTSIDE the 3D block, where rlGetMatrixProjection returns the 2D ortho restored by end3d

// Mesh cache keyed by (shape, segments): several resolutions coexist, so a
// push→segments(8)→sphere→pop does not invalidate the 64-segment sphere of the same frame.
static std::map<std::pair<int,int>, Mesh> s_shape_cache;

void reset3d_shape_cache() {
    for (auto& kv : s_shape_cache)
        UnloadMesh(kv.second);
    s_shape_cache.clear();
}

static Mesh get_shape_mesh(int shape) {
    int seg = gfx_segments();
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

// White 1×1 texture: "no texture" yields a white sample, so texture × tint = tint.
static Texture2D s_white_tex{};
static bool s_white_ready = false;
static unsigned int white_tex_id() {
    if (!s_white_ready) {
        Image img = GenImageColor(1, 1, WHITE);
        s_white_tex = LoadTextureFromImage(img);
        UnloadImage(img);
        s_white_ready = true;
    }
    return s_white_tex.id;
}

// Lighting state (phase 1: ambient + one directional light). Opt-in: as long as no light
// or ambient is set, the render is FLAT (white ambient, light off).
static bool s_lighting_used = false;
static float s_amb3d[4] = {0.15f, 0.15f, 0.15f, 1.0f};
static bool s_light_on = false;
static int s_light_type = 0;   // 0 = directional, 1 = point
static Vector3 s_light_pos = {0.0f, 0.0f, 0.0f};
static Vector3 s_light_tgt = {0.0f, -1.0f, 0.0f};
static float s_light_col[4] = {1.0f, 1.0f, 1.0f, 1.0f};

// Instanced Blinn-Phong shader (per-instance transform and colour) plus a texture.
static Shader s_lit{};
static bool s_lit_ready = false;
static int s_loc_vertcolor = -1;
static int s_loc_instcolor = -1, s_loc_viewpos = -1, s_loc_ambient = -1;
static int s_loc_instcorner = -1;
static int s_loc_insttile = -1, s_loc_atlasgrid = -1, s_loc_utime = -1, s_loc_animtile = -1;
static int s_loc_animparams = -1, s_loc_flipv = -1;
static int s_loc_l_en = -1, s_loc_l_type = -1, s_loc_l_pos = -1, s_loc_l_tgt = -1, s_loc_l_col = -1;

// PERSISTENT instance VBOs (transform + colour): reused from one frame to the next
// (updated by glBufferSubData) instead of being created and destroyed for every
// bucket and frame. Capacities are in bytes, and only ever grow.
static unsigned int s_inst_vbo_xform = 0, s_inst_vbo_color = 0, s_inst_vbo_tile = 0, s_inst_vbo_corner = 0;
static int s_inst_cap_xform = 0, s_inst_cap_color = 0, s_inst_cap_tile = 0, s_inst_cap_corner = 0;

// Creates (first time, or on growth) or updates an instance VBO, and leaves the VBO
// bound on exit, for the rlSetVertexAttribute that follows.
static void upload_instance_vbo(unsigned int& vbo, int& cap, const void* data, int bytes) {
    if (vbo == 0 || bytes > cap) {
        if (vbo != 0)
            rlUnloadVertexBuffer(vbo);
        vbo = rlLoadVertexBuffer(data, bytes, true);   // GL_DYNAMIC_DRAW, and it leaves the buffer bound
        cap = bytes;
    } else {
        rlEnableVertexBuffer(vbo);
        rlUpdateVertexBuffer(vbo, data, bytes, 0);
    }
}

static void load_lit_shader() {
    if (s_lit_ready) {
        return;
    }
#ifdef __EMSCRIPTEN__
    const char* HDR = "#version 300 es\nprecision highp float;\n";
#else
    const char* HDR = "#version 330\n";
#endif
    // The GLSL lives in src/shaders/lit.vert and lit.frag, pasted into a generated header at
    // configure time (see CMakeLists). Only the version line, which depends on the target, is
    // added here.
    std::string vs = std::string(HDR) + k_lit_vertex_src;
    std::string fs = std::string(HDR) + k_lit_fragment_src;
    s_lit = LoadShaderFromMemory(vs.c_str(), fs.c_str());
    if (s_lit.locs[SHADER_LOC_VERTEX_INSTANCETRANSFORM] <= 0) {
        s_lit.locs[SHADER_LOC_VERTEX_INSTANCETRANSFORM] = GetShaderLocationAttrib(s_lit, "instanceTransform");
    }
    s_loc_vertcolor = GetShaderLocationAttrib(s_lit, "vertexColor");
    s_loc_instcolor = GetShaderLocationAttrib(s_lit, "instanceColor");
    s_loc_insttile = GetShaderLocationAttrib(s_lit, "instanceTile");
    s_loc_instcorner = GetShaderLocationAttrib(s_lit, "instanceCorner");
    s_loc_atlasgrid = GetShaderLocation(s_lit, "atlasGrid");
    s_loc_utime = GetShaderLocation(s_lit, "uTime");
    s_loc_animtile = GetShaderLocation(s_lit, "animTile");
    s_loc_animparams = GetShaderLocation(s_lit, "animParams");
    s_loc_flipv = GetShaderLocation(s_lit, "uFlipV");
    s_loc_viewpos = GetShaderLocation(s_lit, "viewPos");
    s_loc_ambient = GetShaderLocation(s_lit, "ambient");
    s_loc_l_en = GetShaderLocation(s_lit, "light0.enabled");
    s_loc_l_type = GetShaderLocation(s_lit, "light0.type");
    s_loc_l_pos = GetShaderLocation(s_lit, "light0.position");
    s_loc_l_tgt = GetShaderLocation(s_lit, "light0.target");
    s_loc_l_col = GetShaderLocation(s_lit, "light0.color");
    s_lit_ready = true;
}

// Current bucket for (mesh, current texture), created on demand. Keyed by mesh.vaoId, so
// unit primitives AND the meshes of external models share the same instanced, lit path
// (N shapes of the same (mesh, texture) = one draw call).
static Bucket3D& bucket_for(const Mesh& mesh, unsigned int texId) {
    for (auto& b : s_buckets) {
        if (b.vaoId == mesh.vaoId && b.texId == texId) {
            return b;
        }
    }
    s_buckets.push_back(Bucket3D{mesh.vaoId, mesh, texId, image_gl_flipped(texId), {}, {}, {}, {}});
    return s_buckets.back();
}

// Pushes an instance (translate·scale transform plus colour) into its (mesh, texId) bucket.
static void push_instance(const Mesh& mesh, unsigned int texId, Vector3 pos, Vector3 size, Color col) {
    if (s_recording) {
        // Recording mode (beginChunk): we bake the LOCAL (world) transform and the colour;
        // texId is ignored, a baked group being a white texture plus a per-instance colour.
        (void)texId;
        Matrix rm = MatrixMultiply(MatrixScale(size.x, size.y, size.z), MatrixTranslate(pos.x, pos.y, pos.z));
        // OPAQUE versus TRANSPARENT routing according to the colour's alpha (water = alpha < 1).
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
            for (int k = 0; k < 4; k++) {
                s_rec_kw.push_back(s_cur_corner[k]);
            }
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
        for (int k = 0; k < 4; k++) {
            s_rec_k.push_back(s_cur_corner[k]);
        }
        return;
    }
    Bucket3D& b = bucket_for(mesh, texId);
    // Local placement (scale then translate) THEN the current transform, captured HERE, so
    // that each instance freezes its own. begin3d having opened the transform mode,
    // rlGetMatrixTransform() reflects translate/rotate/scale whether they are bracketed by
    // push/pop or left "bare" (accumulated over the block) — the same semantics as the
    // immediate primitives.
    Matrix local = MatrixMultiply(MatrixScale(size.x, size.y, size.z), MatrixTranslate(pos.x, pos.y, pos.z));
    b.xforms.push_back(MatrixMultiply(local, rlGetMatrixTransform()));
    b.colors.push_back(col.r / 255.0f);
    b.colors.push_back(col.g / 255.0f);
    b.colors.push_back(col.b / 255.0f);
    b.colors.push_back(col.a / 255.0f);
    b.tiles.push_back(s_cur_tile[0]);
    b.tiles.push_back(s_cur_tile[1]);
    b.tiles.push_back(s_cur_tile[2]);
    for (int k = 0; k < 4; k++) {
        b.corners.push_back(s_cur_corner[k]);
    }
}

// Activates the lit shader and sets the frame's uniforms (MVP = the view·proj frozen at
// begin3d, camera position, lighting). Returns false if the shader is unavailable.
// Shared by flush_bucket (collected instances) AND draw_chunk (a baked group).
static bool lit_begin_draw() {
    load_lit_shader();
    if (s_lit.id == 0) {
        return false;
    }
    rlEnableShader(s_lit.id);
    // A mesh WITHOUT per-vertex colours leaves attribute location 3 unfed, and OpenGL then serves
    // the generic value, (0, 0, 0, 1) by default: every model would come out black. The constant
    // is posted white once per draw; a mesh that HAS the buffer overrides it from its own VAO.
    if (s_loc_vertcolor >= 0) {
        float white[4] = {1.0f, 1.0f, 1.0f, 1.0f};
        rlSetVertexAttributeDefault(s_loc_vertcolor, white, SHADER_ATTRIB_VEC4, 4);
    }
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

// Binds the instance attributes (transform mat4 = 4 vec4, colour vec4, tiles vec3, corners
// vec4; divisor 1) from VBOs ALREADY FILLED. The VAO is assumed to be active. Shared by
// lit_bind_instances (a baked group) and flush_bucket (shared VBOs).
static void bind_instance_vbos(unsigned int vbo_x, unsigned int vbo_c, unsigned int vbo_t, unsigned int vbo_k) {
    int loc_t = s_lit.locs[SHADER_LOC_VERTEX_INSTANCETRANSFORM];
    rlEnableVertexBuffer(vbo_x);
    for (unsigned int i = 0; i < 4; i++) {
        rlEnableVertexAttribute(loc_t + i);
        rlSetVertexAttribute(loc_t + i, 4, RL_FLOAT, 0, sizeof(Matrix), i * sizeof(Vector4));
        rlSetVertexAttributeDivisor(loc_t + i, 1);
    }
    rlEnableVertexBuffer(vbo_c);
    if (s_loc_instcolor >= 0) {
        rlEnableVertexAttribute(s_loc_instcolor);
        rlSetVertexAttribute(s_loc_instcolor, 4, RL_FLOAT, 0, 0, 0);
        rlSetVertexAttributeDivisor(s_loc_instcolor, 1);
    }
    if (s_loc_insttile >= 0 && vbo_t != 0) {
        rlEnableVertexBuffer(vbo_t);
        rlEnableVertexAttribute(s_loc_insttile);
        rlSetVertexAttribute(s_loc_insttile, 3, RL_FLOAT, 0, 0, 0);
        rlSetVertexAttributeDivisor(s_loc_insttile, 1);
    }
    if (s_loc_instcorner >= 0 && vbo_k != 0) {
        rlEnableVertexBuffer(vbo_k);
        rlEnableVertexAttribute(s_loc_instcorner);
        rlSetVertexAttribute(s_loc_instcorner, 4, RL_FLOAT, 0, 0, 0);
        rlSetVertexAttributeDivisor(s_loc_instcorner, 1);
    }
}

// Same binding, but on the mesh's VAO, which it activates and releases itself.
static void lit_bind_instances(unsigned int vaoId, unsigned int vbo_x, unsigned int vbo_c, unsigned int vbo_t,
                              unsigned int vbo_k) {
    rlEnableVertexArray(vaoId);
    bind_instance_vbos(vbo_x, vbo_c, vbo_t, vbo_k);
    rlDisableVertexBuffer();
    rlDisableVertexArray();
}

// Instanced draw (shader and attributes already in place). Binds the texture, then draws.
static void lit_draw_instanced(const Mesh& mesh, unsigned int texId, int n, bool flip_v) {
    rlActiveTextureSlot(0);
    rlEnableTexture(texId ? texId : white_tex_id());
    int slot = 0;
    rlSetUniform(s_lit.locs[SHADER_LOC_MAP_DIFFUSE], &slot, RL_SHADER_UNIFORM_INT, 1);
    // An image painted by RENDERING has its rows bottom-up (OpenGL's framebuffer origin), and
    // the 3D path samples the texture directly: without this the picture came out upside down.
    // Set per DRAW, the texture being part of a bucket's key.
    if (s_loc_flipv >= 0) {
        float fv = flip_v ? 1.0f : 0.0f;
        rlSetUniform(s_loc_flipv, &fv, RL_SHADER_UNIFORM_FLOAT, 1);
    }
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

// Resolves a bucket (the instances collected THIS frame) into ONE instanced call.
static void flush_bucket(const Bucket3D& b) {
    int n = (int)b.xforms.size();
    if (n == 0) {
        return;
    }
    if (!lit_begin_draw()) {
        return;
    }
    Mesh mesh = b.mesh;
    // A reused scratch buffer (no allocation per bucket or frame) plus SHARED persistent
    // instance VBOs (uploaded per frame, not recreated).
    static std::vector<float16> xf;
    xf.resize(n);
    for (int i = 0; i < n; i++) {
        xf[i] = MatrixToFloatV(b.xforms[i]);
    }
    rlEnableVertexArray(mesh.vaoId);
    upload_instance_vbo(s_inst_vbo_xform, s_inst_cap_xform, xf.data(), n * (int)sizeof(float16));
    upload_instance_vbo(s_inst_vbo_color, s_inst_cap_color, b.colors.data(), n * 4 * (int)sizeof(float));
    upload_instance_vbo(s_inst_vbo_tile, s_inst_cap_tile, b.tiles.data(), n * 3 * (int)sizeof(float));
    upload_instance_vbo(s_inst_vbo_corner, s_inst_cap_corner, b.corners.data(), n * 4 * (int)sizeof(float));
    bind_instance_vbos(s_inst_vbo_xform, s_inst_vbo_color, s_inst_vbo_tile, s_inst_vbo_corner);
    rlDisableVertexBuffer();
    rlDisableVertexArray();
    lit_draw_instanced(mesh, b.texId, n, b.flip_v);
    rlDisableShader();
}

void reset3d_lighting_state() {
    s_lighting_used = false;
    s_light_on = false;
    s_cur_tex3d = 0;
    s_amb3d[0] = 0.15f;
    s_amb3d[1] = 0.15f;
    s_amb3d[2] = 0.15f;
    s_amb3d[3] = 1.0f;
}

// Frees ALL cached 3D GL resources (shader, unit meshes, white texture, instance VBOs)
// and clears the caches. To be called by gfx_canvas BEFORE destroying the GL context
// (CloseWindow): otherwise the GL ids would survive in the caches and point at objects of
// a context destroyed by the next run (playground), giving corrupt 3D or a crash. This is
// the 3D counterpart of image_reset().
// It only makes GL calls when a context is current (the IsWindowReady guard sits in the
// caller); on the first run the *_ready flags are false, so it is a no-op.
void reset3d_graphics_state() {
    if (s_lit_ready) {
        UnloadShader(s_lit);
        s_lit = Shader{};
        s_lit_ready = false;
    }
    reset3d_shape_cache();
    // Models loaded into the GPU: invalid once the context is destroyed, so we unload them
    // and clear the cache (they are reloaded lazily from the bytes on next use).
    for (auto& kv : s_model_cache) {
        UnloadModel(kv.second);
    }
    s_model_cache.clear();
    // Baked instance groups: their VBOs belong to the context, so we free and clear them
    // (the script bakes them again in setup on the next run).
    for (auto& g : s_groups) {
        if (g.vbo_x) {
            rlUnloadVertexBuffer(g.vbo_x);
        }
        if (g.vbo_c) {
            rlUnloadVertexBuffer(g.vbo_c);
        }
        if (g.vbo_t) {
            rlUnloadVertexBuffer(g.vbo_t);
        }
        if (g.vbo_k) {
            rlUnloadVertexBuffer(g.vbo_k);
        }
    }
    s_groups.clear();
    s_free_groups.clear();
    s_recording = false;
    s_rec_x.clear();
    s_rec_c.clear();
    s_rec_t.clear();
    s_rec_k.clear();
    s_rec_xw.clear();
    s_rec_cw.clear();
    s_rec_tw.clear();
    s_rec_kw.clear();
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
    if (s_inst_vbo_corner != 0) {
        rlUnloadVertexBuffer(s_inst_vbo_corner);
        s_inst_vbo_corner = 0;
        s_inst_cap_corner = 0;
    }
    s_buckets.clear();
    s_in_3d = false;
    s_cur_tex3d = 0;
    s_atlas_texid = 0;
    s_atlas_flipped = false;
    s_atlas_grid[0] = 1.0f;
    s_atlas_grid[1] = 1.0f;
    s_cur_tile[0] = -1.0f;
    s_cur_tile[1] = -1.0f;
    s_cur_tile[2] = -1.0f;
    for (int k = 0; k < 4; k++) {
        s_cur_corner[k] = 0.0f;
    }
    s_anim_tile = -1.0f;
    s_anim_params[0] = 0.09f;
    s_anim_params[1] = 1.6f;
    s_anim_params[2] = 8.0f;
    s_anim_params[3] = 0.045f;
}

static void flush3d_buckets() {
    // Flush the pending immediate batch (wireframe and grid, drawn during the collection)
    // before our instanced draw calls, so the order stays consistent.
    rlDrawRenderBatchActive();
    for (const auto& b : s_buckets) {
        flush_bucket(b);
    }
    s_buckets.clear();
}

void end3d_internal() {
    if (!s_in_3d) {
        return;
    }
    flush3d_buckets();   // still in Mode3D, so the view and projection matrices are available
    rlPopMatrix();      // closes the transform mode begin3d opened (rlPushMatrix)
    EndMode3D();
    s_in_3d = false;
}

static int gfx_begin3d(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 1)
        throw std::runtime_error("graphics.begin3d: expected a camera (graphics.camera)");
    s_cam3d = camera_from_map(args[0], "graphics.begin3d");
    s_buckets.clear();
    BeginMode3D(s_cam3d);
    s_view3d = rlGetMatrixModelview();   // the view ALONE, before any transform the user applied
    s_proj3d = rlGetMatrixProjection();  // the perspective projection is frozen, so inFrustum is right even outside the 3D block
    // Enters rlgl's "transform" mode for the WHOLE 3D block, so that translate/rotate/scale
    // — WITH OR WITHOUT push/pop — write into RLGL.State.transform (world space, read by
    // rlGetMatrixTransform) instead of into the modelview. The instanced solids (baked) AND
    // the immediate primitives (transform_required) then receive the same transform, which is
    // consistent without requiring push/pop. Closed again by end3d_internal's rlPopMatrix.
    rlPushMatrix();
    s_in_3d = true;
    return ctx.ret(Value{});
}

static int gfx_end3d(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    end3d_internal();   // idempotent
    return ctx.ret(Value{});
}

// graphics.ambient(v | colour): ambient light, which turns the lit mode on.
static int gfx_ambient(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc > 0 && (args[0].is_map() || args[0].is_class())) {
        Color c = gfx_to_color(args[0]);
        s_amb3d[0] = c.r / 255.0f;
        s_amb3d[1] = c.g / 255.0f;
        s_amb3d[2] = c.b / 255.0f;
        s_amb3d[3] = 1.0f;
    } else {
        float v = argc > 0 ? (float)num_arg(args, argc, 0, "graphics.ambient") : 0.15f;
        s_amb3d[0] = v;
        s_amb3d[1] = v;
        s_amb3d[2] = v;
        s_amb3d[3] = 1.0f;
    }
    s_lighting_used = true;
    return ctx.ret(Value{});
}

// Light class (native, like Camera and Color).
// Phase 1: a single active light, directional or point. A Light object carries its own
// configuration (type, direction or position, colour, enabled) and, on every mutation,
// pushes it into the global lighting state (last written wins).
static double inst_field(const Value& self, const char* k, double def) {
    Value v = self.map_get(Value(std::string(k)));
    return v.is_number() ? v.as_num() : def;
}

static void apply_light_from_instance(const Value& self) {
    int type = (int)inst_field(self, "type", 0);
    float x = (float)inst_field(self, "dx", 0.0);
    float y = (float)inst_field(self, "dy", -1.0);
    float z = (float)inst_field(self, "dz", 0.0);
    // A directional light with a NULL direction is refused: the shader would compute
    // normalize(vec3(0)), which is undefined — measured as "the light contributes nothing" on one
    // driver, but nothing guarantees that elsewhere. A meaningless argument is refused, never
    // silently ignored. A point light has no such case: its position is a place, not a direction.
    if (type == 0 && x == 0.0f && y == 0.0f && z == 0.0f)
        throw std::runtime_error("graphics.light: a directional light needs a direction, and (0, 0, 0) is none");
    s_light_type = type;
    if (type == 1) {
        s_light_pos = Vector3{x, y, z};
        s_light_tgt = Vector3{0.0f, 0.0f, 0.0f};
    } else {
        s_light_pos = Vector3{0.0f, 0.0f, 0.0f};
        s_light_tgt = Vector3{x, y, z};
    }
    s_light_col[0] = (float)inst_field(self, "r", 1.0);
    s_light_col[1] = (float)inst_field(self, "g", 1.0);
    s_light_col[2] = (float)inst_field(self, "b", 1.0);
    s_light_col[3] = (float)inst_field(self, "a", 1.0);
    s_light_on = !is_falsy(self.map_get(Value(std::string("enabled"))));
    s_lighting_used = true;
}

// light.setDir(x,y,z): aims a directional light (direction of propagation).
static int light_set_dir(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Value self = args[0];
    self.map_set(Value(std::string("type")), Value((int64_t)0));
    self.map_set(Value(std::string("dx")), Value(num_arg(args, argc, 1, "Light.setDir")));
    self.map_set(Value(std::string("dy")), Value(num_arg(args, argc, 2, "Light.setDir")));
    self.map_set(Value(std::string("dz")), Value(num_arg(args, argc, 3, "Light.setDir")));
    apply_light_from_instance(self);
    return ctx.ret(self);
}

// light.setPos(x,y,z): places a point light.
static int light_set_pos(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Value self = args[0];
    self.map_set(Value(std::string("type")), Value((int64_t)1));
    self.map_set(Value(std::string("dx")), Value(num_arg(args, argc, 1, "Light.setPos")));
    self.map_set(Value(std::string("dy")), Value(num_arg(args, argc, 2, "Light.setPos")));
    self.map_set(Value(std::string("dz")), Value(num_arg(args, argc, 3, "Light.setPos")));
    apply_light_from_instance(self);
    return ctx.ret(self);
}

// light.setColor(colour): the light's colour.
static int light_set_color(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Value self = args[0];
    if (argc > 1 && (args[1].is_map() || args[1].is_class())) {
        Color c = gfx_to_color(args[1]);
        self.map_set(Value(std::string("r")), Value(c.r / 255.0));
        self.map_set(Value(std::string("g")), Value(c.g / 255.0));
        self.map_set(Value(std::string("b")), Value(c.b / 255.0));
        self.map_set(Value(std::string("a")), Value(c.a / 255.0));
    }
    apply_light_from_instance(self);
    return ctx.ret(self);
}

// light.enable(bool): turns the light on or off (on by default).
static int light_enable(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Value self = args[0];
    bool on = (argc > 1) ? !is_falsy(args[1]) : true;
    self.map_set(Value(std::string("enabled")), Value::make_bool(on));
    apply_light_from_instance(self);
    return ctx.ret(self);
}

static Value make_light_class() {
    return MapBuilder(Value::make_class())
        .str("__name__", "Light")
        .fn("setDir", light_set_dir)
        .fn("setPos", light_set_pos)
        .fn("setColor", light_set_color)
        .fn("enable", light_enable)
        .done();
}

static Value light_class() {
    static Value cls = make_light_class();
    return cls;
}

// graphics.light("dir"|"point", x,y,z [, colour]): creates a Light object and enables it.
// For "dir", (x,y,z) is the direction of propagation; for "point", the position.
static int gfx_light(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    // The kind is an IDENTIFIER: anything else used to become "dir" in silence, so a mistyped call
    // lit the scene the wrong way with no word said.
    if (argc > 0 && !args[0].is_string())
        throw std::runtime_error("graphics.light: expected \"dir\" or \"point\"");
    std::string type = argc > 0 ? args[0].as_string() : "dir";
    if (type != "dir" && type != "point")
        throw std::runtime_error("graphics.light: unknown kind '" + type + "' — expected \"dir\" or \"point\"");
    float x = (float)num_arg(args, argc, 1, "graphics.light");
    float y = (float)num_arg(args, argc, 2, "graphics.light");
    float z = (float)num_arg(args, argc, 3, "graphics.light");
    Color c = (argc > 4 && (args[4].is_map() || args[4].is_class())) ? gfx_to_color(args[4]) : WHITE;
    Value inst = Value::make_map();
    inst.map_set(Value(std::string("__class__")), light_class());
    inst.map_set(Value(std::string("type")), Value((int64_t)(type == "point" ? 1 : 0)));
    inst.map_set(Value(std::string("dx")), Value((double)x));
    inst.map_set(Value(std::string("dy")), Value((double)y));
    inst.map_set(Value(std::string("dz")), Value((double)z));
    inst.map_set(Value(std::string("r")), Value(c.r / 255.0));
    inst.map_set(Value(std::string("g")), Value(c.g / 255.0));
    inst.map_set(Value(std::string("b")), Value(c.b / 255.0));
    inst.map_set(Value(std::string("a")), Value(c.a / 255.0));
    inst.map_set(Value(std::string("enabled")), Value::make_bool(true));
    apply_light_from_instance(inst);
    return ctx.ret(inst);
}

// graphics.grid(slices, spacing): a ground grid (XZ plane) centred on the origin. Its
// grey is raylib's own and fixed (it uses neither fill nor stroke).
static int gfx_grid(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    int slices = argc > 0 ? gfx_to_int(args[0]) : 10;
    float spacing = argc > 1 ? (float)num_arg(args, argc, 1, "graphics.grid") : 1.0f;
    DrawGrid(slices, spacing);
    return ctx.ret(Value{});
}

// graphics.texture(img) / graphics.noTexture(): the current 3D texture (an image handle).
static int gfx_texture(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc > 0 && args[0].is_map()) {
        Value idv = args[0].map_get(Value(std::string("id")));
        s_cur_tex3d = idv.is_integer() ? image_gl_texid((int)idv.as_int()) : 0;
    }
    return ctx.ret(Value{});
}

static int gfx_no_texture(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    s_cur_tex3d = 0;
    return ctx.ret(Value{});
}

// graphics.tileset(img, cols, rows): declares the tile atlas (voxel terrain). A single
// grid texture, sampled tile by tile according to the cube's face.
static int gfx_tileset(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc > 0 && args[0].is_map()) {
        Value idv = args[0].map_get(Value(std::string("id")));
        s_atlas_texid = idv.is_integer() ? image_gl_texid((int)idv.as_int()) : 0;
        s_atlas_flipped = image_gl_flipped(s_atlas_texid);
    }
    s_atlas_grid[0] = argc > 1 ? (float)num_arg(args, argc, 1, "graphics.tileset") : 1.0f;
    s_atlas_grid[1] = argc > 2 ? (float)num_arg(args, argc, 2, "graphics.tileset") : 1.0f;
    if (s_atlas_texid != 0) {
        // Crisp pixels (the voxel look): NEAREST filtering, no mipmap.
        rlTextureParameters(s_atlas_texid, RL_TEXTURE_MAG_FILTER, RL_TEXTURE_FILTER_NEAREST);
        rlTextureParameters(s_atlas_texid, RL_TEXTURE_MIN_FILTER, RL_TEXTURE_FILTER_NEAREST);
    }
    return ctx.ret(Value{});
}

// graphics.tiles(top, side, bottom): tiles of the next cube (state, like fill).
static int gfx_tiles(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    s_cur_tile[0] = argc > 0 ? (float)num_arg(args, argc, 0, "graphics.tiles") : -1.0f;
    s_cur_tile[1] = argc > 1 ? (float)num_arg(args, argc, 1, "graphics.tiles") : s_cur_tile[0];
    s_cur_tile[2] = argc > 2 ? (float)num_arg(args, argc, 2, "graphics.tiles") : s_cur_tile[1];
    return ctx.ret(Value{});
}

// graphics.corners(a, b, c, d): heights of the four TOP corners of the next cube, in units
// of its height: (-x,-z), (+x,-z), (-x,+z), (+x,+z). State, like graphics.tile. With no
// argument (or all zero) the top is flat, an ordinary cube. Two neighbouring cubes giving
// the same value to the corner they share form a continuous surface.
static int gfx_corners(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    for (int k = 0; k < 4; k++) {
        s_cur_corner[k] = argc > k ? (float)num_arg(args, argc, k, "graphics.corners") : 0.0f;
    }
    return ctx.ret(Value{});
}

// graphics.tile(t): the same tile on all six faces (a shorthand). tile(-1) = none.
static int gfx_tile(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    float t = argc > 0 ? (float)num_arg(args, argc, 0, "graphics.tile") : -1.0f;
    s_cur_tile[0] = t;
    s_cur_tile[1] = t;
    s_cur_tile[2] = t;
    return ctx.ret(Value{});
}

// graphics.tileAnim(t [, scroll, speed, frequency, amplitude]): a tile whose UV scrolls and
// ripples over time (water). -1 = none. The four optional parameters tune the ripple
// (defaults give a water look); the spatial phase is in world coordinates.
static int gfx_tile_anim(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    s_anim_tile = argc > 0 ? (float)num_arg(args, argc, 0, "graphics.tileAnim") : -1.0f;
    if (argc > 1) {
        s_anim_params[0] = (float)num_arg(args, argc, 1, "graphics.tileAnim");
    }
    if (argc > 2) {
        s_anim_params[1] = (float)num_arg(args, argc, 2, "graphics.tileAnim");
    }
    if (argc > 3) {
        s_anim_params[2] = (float)num_arg(args, argc, 3, "graphics.tileAnim");
    }
    if (argc > 4) {
        s_anim_params[3] = (float)num_arg(args, argc, 4, "graphics.tileAnim");
    }
    return ctx.ret(Value{});
}

// graphics.cube(x,y,z, w,h,l): a cube centred on (x,y,z). Solid if fill (instanced, lit,
// textured), edges if stroke (immediate, unlit).
static int gfx_cube(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Vector3 pos{(float)num_arg(args, argc, 0, "graphics.cube"), (float)num_arg(args, argc, 1, "graphics.cube"),
                (float)num_arg(args, argc, 2, "graphics.cube")};
    Vector3 size{(float)num_arg(args, argc, 3, "graphics.cube"), (float)num_arg(args, argc, 4, "graphics.cube"),
                 (float)num_arg(args, argc, 5, "graphics.cube")};
    if (gfx_has_fill())
        push_instance(get_shape_mesh(SH_CUBE), s_cur_tex3d, pos, size, gfx_fill_color());
    if (gfx_has_stroke())
        DrawCubeWiresV(pos, size, gfx_stroke_color());
    return ctx.ret(Value{});
}

// graphics.sphere(x,y,z, r): a sphere centred on (x,y,z). Solid if fill (instanced, lit,
// textured), wireframe if stroke (immediate). The unit mesh has radius 0.5.
static int gfx_sphere(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Vector3 pos{(float)num_arg(args, argc, 0, "graphics.sphere"), (float)num_arg(args, argc, 1, "graphics.sphere"),
                (float)num_arg(args, argc, 2, "graphics.sphere")};
    float r = (float)num_arg(args, argc, 3, "graphics.sphere");
    if (gfx_has_fill())
        push_instance(get_shape_mesh(SH_SPHERE), s_cur_tex3d, pos, Vector3{2.0f * r, 2.0f * r, 2.0f * r}, gfx_fill_color());
    if (gfx_has_stroke())
        DrawSphereWires(pos, r, 16, 16, gfx_stroke_color());
    return ctx.ret(Value{});
}

// graphics.cylinder(x,y,z, r, h): a cylinder, (x,y,z) being the centre of the base, of
// radius r and height h (towards +Y). Solid if fill (instanced), wireframe if stroke
// (immediate). Single-radius, a constraint of the instancing: the unit mesh is frozen at radius 1, height 1.
static int gfx_cylinder(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Vector3 pos{(float)num_arg(args, argc, 0, "graphics.cylinder"), (float)num_arg(args, argc, 1, "graphics.cylinder"),
                (float)num_arg(args, argc, 2, "graphics.cylinder")};
    float r = (float)num_arg(args, argc, 3, "graphics.cylinder");
    float h = (float)num_arg(args, argc, 4, "graphics.cylinder");
    if (gfx_has_fill())
        push_instance(get_shape_mesh(SH_CYLINDER), s_cur_tex3d, pos, Vector3{r, h, r}, gfx_fill_color());
    if (gfx_has_stroke())
        DrawCylinderWires(pos, r, r, h, 16, gfx_stroke_color());
    return ctx.ret(Value{});
}

// graphics.cone(x,y,z, r, h): a cone, (x,y,z) being the centre of the base, of radius r and height h (towards +Y).
static int gfx_cone(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Vector3 pos{(float)num_arg(args, argc, 0, "graphics.cone"), (float)num_arg(args, argc, 1, "graphics.cone"),
                (float)num_arg(args, argc, 2, "graphics.cone")};
    float r = (float)num_arg(args, argc, 3, "graphics.cone");
    float h = (float)num_arg(args, argc, 4, "graphics.cone");
    if (gfx_has_fill())
        push_instance(get_shape_mesh(SH_CONE), s_cur_tex3d, pos, Vector3{r, h, r}, gfx_fill_color());
    if (gfx_has_stroke())
        DrawCylinderWires(pos, r, 0.0f, h, 16, gfx_stroke_color());
    return ctx.ret(Value{});
}

// graphics.torus(x,y,z, r, tube): a torus centred on (x,y,z), of major radius r and tube radius tube.
// The unit mesh has r=0.5 and tube=0.25, hence a uniform scale with tube/r fixed at 0.5.
// To expose the two parameters independently, X and Z scale on r, and Y on tube.
static int gfx_torus(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Vector3 pos{(float)num_arg(args, argc, 0, "graphics.torus"), (float)num_arg(args, argc, 1, "graphics.torus"),
                (float)num_arg(args, argc, 2, "graphics.torus")};
    float r    = (float)num_arg(args, argc, 3, "graphics.torus");
    float tube = (float)num_arg(args, argc, 4, "graphics.torus");
    // Mesh: major=1 (XY), tube=0.3 (Z), hence XY scaled by r and Z by tube/0.3.
    if (gfx_has_fill())
        push_instance(get_shape_mesh(SH_TORUS), s_cur_tex3d, pos, {r, r, tube / 0.3f}, gfx_fill_color());
    if (gfx_has_stroke())
        DrawCircle3D(pos, r, {1, 0, 0}, 90.0f, gfx_stroke_color());
    return ctx.ret(Value{});
}

// graphics.plane(x,y,z, sx,sz): a horizontal plane (XZ) centred on (x,y,z), of size sx×sz.
// Instanced and lit (it uses the fill colour, falling back to stroke to stay visible).
static int gfx_plane(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Vector3 pos{(float)num_arg(args, argc, 0, "graphics.plane"), (float)num_arg(args, argc, 1, "graphics.plane"),
                (float)num_arg(args, argc, 2, "graphics.plane")};
    float sx = (float)num_arg(args, argc, 3, "graphics.plane");
    float sz = (float)num_arg(args, argc, 4, "graphics.plane");
    if (gfx_has_fill() || gfx_has_stroke()) {   // nothing to draw without fill or stroke, consistently with cube and sphere
        Color c = gfx_has_fill() ? gfx_fill_color() : gfx_stroke_color();
        push_instance(get_shape_mesh(SH_PLANE), s_cur_tex3d, pos, Vector3{sx, 1.0f, sz}, c);
    }
    return ctx.ret(Value{});
}

// graphics.line3d(x1,y1,z1, x2,y2,z2): a 3D segment, drawn as a cylinder (radius = strokeSize * 0.02).
static int gfx_line3d(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Vector3 a{(float)num_arg(args, argc, 0, "graphics.line3d"), (float)num_arg(args, argc, 1, "graphics.line3d"),
              (float)num_arg(args, argc, 2, "graphics.line3d")};
    Vector3 b{(float)num_arg(args, argc, 3, "graphics.line3d"), (float)num_arg(args, argc, 4, "graphics.line3d"),
              (float)num_arg(args, argc, 5, "graphics.line3d")};
    float r = gfx_stroke_size() * 0.02f;
    DrawCylinderEx(a, b, r, r, 6, gfx_stroke_color());
    return ctx.ret(Value{});
}

// graphics.point3d(x,y,z): a 3D point, drawn as a small sphere (radius = strokeSize * 0.015).
static int gfx_point3d(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    float x = (float)num_arg(args, argc, 0, "graphics.point3d");
    float y = (float)num_arg(args, argc, 1, "graphics.point3d");
    float z = (float)num_arg(args, argc, 2, "graphics.point3d");
    float r = gfx_stroke_size() * 0.015f;
    push_instance(get_shape_mesh(SH_SPHERE), s_cur_tex3d, {x, y, z}, {2.0f * r, 2.0f * r, 2.0f * r}, gfx_stroke_color());
    return ctx.ret(Value{});
}

// graphics.rotateq(q): applies the quaternion q's rotation in the current transformation
// stack — like rotate/rotateX-Y-Z but from a Quat. It therefore composes, works with
// push/pop, and applies to instanced solids AS WELL AS immediate ones. rlMultMatrixf
// left-multiplies (like rlRotatef), so the composition is identical.
static int gfx_rotateq(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 1)
        throw std::runtime_error("graphics.rotateq: expected a Quat (graphics.quat…)");
    Matrix m = QuaternionToMatrix(quat_from_instance(args[0], "graphics.rotateq"));
    rlMultMatrixf(MatrixToFloatV(m).v);
    return ctx.ret(Value{});
}

// External models (OBJ, GLTF…).
// raylib has no LoadModel from memory, so we store the preloaded BYTES by name and, on
// first use (once the GL context is ready), write them to the FS and call LoadModel.
// The GPU load is LAZY (after graphics.canvas, hence after InitWindow) and cached. The
// rendering reuses the batcher: draw_model pushes the model's meshes as instances, so
// they get the same lighting, fill and instancing as the primitives.
// (PendingModel, s_model_bytes and s_model_cache are declared above, because
// reset3d_graphics_state refers to them.)

// Preloading from JS or native code: keeps the raw bytes, the GPU load being deferred.
void model_preload_bytes(const std::string& name, std::vector<unsigned char> bytes, const std::string& ext) {
    s_model_bytes[name] = PendingModel{std::move(bytes), ext};
}

// Fetches the model `name`, loading it into the GPU on demand. It looks in the cache,
// then in the preloaded bytes (write to the FS, then LoadModel), then as a direct file
// path (native, or an asset written into MEMFS). Returns nullptr if not found or unreadable.
static Model* model_get(const std::string& name) {
    auto c = s_model_cache.find(name);
    if (c != s_model_cache.end()) {
        return &c->second;
    }
    Model m{};
    auto p = s_model_bytes.find(name);
    if (p != s_model_bytes.end()) {
        // raylib's LoadModel reads a FILE, so we write the bytes into the FS (MEMFS on WASM),
        // load them, then clean up the working file.
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
        // Straight from a path (native, or an asset in MEMFS), searched where asset_candidates
        // says. The file is PROBED before being loaded: a failed LoadModel still allocates a
        // default material to undo, and writes a warning of its own.
        for (const std::string& path : asset_candidates(name)) {
            if (!FileExists(path.c_str()))
                continue;
            m = LoadModel(path.c_str());
            if (m.meshCount > 0)
                break;
            UnloadModel(m);   // the file exists but does not load: try the next place
            m = Model{};
        }
    }
    if (m.meshCount <= 0) {
        UnloadModel(m);
        return nullptr;
    }
    s_model_cache[name] = m;
    return &s_model_cache[name];
}

// graphics.model(name): returns a handle {name} to a preloaded model (or a loadable path).
// It triggers the load, and raises an error if the model cannot be found.
static int gfx_model(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 1 || !args[0].is_string()) {
        throw std::runtime_error("graphics.model: expected a model name (string)");
    }
    const std::string& name = args[0].as_string();
    if (!model_get(name)) {
        throw std::runtime_error("graphics.model: model not found or unreadable: " + name);
    }
    Value h = Value::make_map();
    h.map_set(Value(std::string("name")), Value(name));
    return ctx.ret(h);
}

// graphics.drawModel(handle [, x, y, z [, scale]]): inside a begin3d block, pushes the
// model's meshes as instances (current transform · translate · scale, tint = fill), hence
// the batcher's lighting and instancing.
static int gfx_draw_model(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 1 || !args[0].is_map()) {
        throw std::runtime_error("graphics.drawModel: expected a model handle (graphics.model)");
    }
    Value name_v = args[0].map_get(Value(std::string("name")));
    if (!name_v.is_string()) {
        throw std::runtime_error("graphics.drawModel: invalid model handle");
    }
    Model* mdl = model_get(name_v.as_string());
    if (!mdl) {
        throw std::runtime_error("graphics.drawModel: model not found: " + name_v.as_string());
    }
    float x = argc > 1 ? (float)num_arg(args, argc, 1, "graphics.drawModel") : 0.0f;
    float y = argc > 2 ? (float)num_arg(args, argc, 2, "graphics.drawModel") : 0.0f;
    float z = argc > 3 ? (float)num_arg(args, argc, 3, "graphics.drawModel") : 0.0f;
    float s = argc > 4 ? (float)num_arg(args, argc, 4, "graphics.drawModel") : 1.0f;
    Vector3 pos{x, y, z};
    Vector3 size{s, s, s};
    // fill is a GLOBAL tint (a multiplier): a white fill leaves the model its own colours and
    // textures, a coloured fill tints it.
    Color fill = gfx_has_fill() ? gfx_fill_color() : WHITE;
    for (int i = 0; i < mdl->meshCount; i++) {
        // The mesh's material (GLB/GLTF): diffuse texture plus base colour.
        unsigned int texId = s_cur_tex3d;   // by default the current 3D texture, or white
        Color base = WHITE;
        int mi = mdl->meshMaterial ? mdl->meshMaterial[i] : 0;
        if (mdl->materials && mi >= 0 && mi < mdl->materialCount) {
            const MaterialMap& diff = mdl->materials[mi].maps[MATERIAL_MAP_DIFFUSE];
            if (diff.texture.id != 0) {
                texId = diff.texture.id;   // the material's texture, which wins
            }
            base = diff.color;             // baseColorFactor (glTF); white by default, as for OBJ
        }
        // tint = the material's base colour times fill, component by component.
        Color tint{(unsigned char)(base.r * fill.r / 255), (unsigned char)(base.g * fill.g / 255),
                   (unsigned char)(base.b * fill.b / 255), (unsigned char)(base.a * fill.a / 255)};
        push_instance(mdl->meshes[i], texId, pos, size, tint);
    }
    return ctx.ret(Value{});
}

// graphics.modelSize(handle): the model's dimensions (its bounding box), as a map
// { w, h, d, cx, cy, cz, radius }, radius being that of the bounding sphere (half the
// diagonal). To be called ONCE: walking the vertices is not free.
static int gfx_model_size(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 1 || !args[0].is_map()) {
        throw std::runtime_error("graphics.modelSize: expected a model handle (graphics.model)");
    }
    Value name_v = args[0].map_get(Value(std::string("name")));
    if (!name_v.is_string()) {
        throw std::runtime_error("graphics.modelSize: invalid model handle");
    }
    Model* mdl = model_get(name_v.as_string());
    if (!mdl) {
        throw std::runtime_error("graphics.modelSize: model not found: " + name_v.as_string());
    }
    BoundingBox bb = GetModelBoundingBox(*mdl);
    float w = bb.max.x - bb.min.x;
    float h = bb.max.y - bb.min.y;
    float d = bb.max.z - bb.min.z;
    Value r = Value::make_map();
    r.map_set(Value(std::string("w")), Value((double)w));
    r.map_set(Value(std::string("h")), Value((double)h));
    r.map_set(Value(std::string("d")), Value((double)d));
    r.map_set(Value(std::string("cx")), Value((double)((bb.min.x + bb.max.x) * 0.5f)));
    r.map_set(Value(std::string("cy")), Value((double)((bb.min.y + bb.max.y) * 0.5f)));
    r.map_set(Value(std::string("cz")), Value((double)((bb.min.z + bb.max.z) * 0.5f)));
    r.map_set(Value(std::string("radius")), Value((double)(0.5f * std::sqrt(w * w + h * h + d * d))));
    return ctx.ret(r);
}

// graphics.fitDistance(radius [, fovy]): the camera distance at which a sphere of radius
// `radius` fits ENTIRELY in the view, given the current screen RATIO (portrait or
// landscape) and the vertical field of view `fovy` (in degrees, 45 by default). In
// landscape the constraint is vertical, in portrait horizontal, so we take the smaller
// half-angle. Cheap enough to call every frame, which follows screen rotations.
static int gfx_fit_distance(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    double radius = num_arg(args, argc, 0, "graphics.fitDistance");
    double fovy = argc > 1 ? num_arg(args, argc, 1, "graphics.fitDistance") : 45.0;
    int sh = GetScreenHeight();
    int sw = GetScreenWidth();
    double aspect = (sh > 0) ? (double)sw / (double)sh : 1.0;
    double half_v = fovy * DEG2RAD * 0.5;
    double half_h = std::atan(std::tan(half_v) * aspect);
    double half = half_v < half_h ? half_v : half_h;
    double s = std::sin(half);
    return ctx.ret(Value((s > 1e-4) ? radius / s : radius * 10.0));
}

// graphics.inFrustum(x, y, z [, radius]): is the sphere (centre, radius) at least partly
// INSIDE the current camera's field of view? It answers true (visible) or false (off
// screen), which serves per-chunk culling: only the visible part is drawn. To be called
// INSIDE a begin3d/end3d block, where the frame's view and projection are set. The test
// is exact: the six frustum planes are extracted from view·projection.
static int gfx_in_frustum(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    float x = (float)num_arg(args, argc, 0, "graphics.inFrustum");
    float y = (float)num_arg(args, argc, 1, "graphics.inFrustum");
    float z = (float)num_arg(args, argc, 2, "graphics.inFrustum");
    float r = argc > 3 ? (float)num_arg(args, argc, 3, "graphics.inFrustum") : 0.0f;
    // Uses the projection FROZEN at begin3d (s_proj3d), not rlGetMatrixProjection() live:
    // per-chunk culling happens BEFORE begin3d, where the current projection is the 2D ortho
    // restored by the previous end3d, giving a wrong frustum (distant chunks wrongly culled;
    // they "appear" as one draws near).
    Matrix vp = MatrixMultiply(s_view3d, s_proj3d);
    // Rows of VP (clip.x/y/z/w = row · (x,y,z,1)), in raylib's column-major layout.
    float rows[4][4] = {
        {vp.m0, vp.m4, vp.m8, vp.m12},   // clip.x
        {vp.m1, vp.m5, vp.m9, vp.m13},   // clip.y
        {vp.m2, vp.m6, vp.m10, vp.m14},  // clip.z
        {vp.m3, vp.m7, vp.m11, vp.m15},  // clip.w
    };
    // Six planes = row_w ± row_i (left/right, bottom/top, near/far).
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
                return ctx.ret(Value::make_bool(false));   // entirely on the wrong side of a plane, hence off screen
            }
        }
    }
    return ctx.ret(Value::make_bool(true));
}

// graphics.beginChunk(): starts recording a group of cubes. The graphics.cube(...) calls
// that follow are BAKED, not drawn. To be called in setup, the GL context having to be
// ready, hence after graphics.canvas.
static int gfx_begin_chunk(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    s_recording = true;
    s_rec_x.clear();
    s_rec_c.clear();
    s_rec_t.clear();
    s_rec_k.clear();
    s_rec_xw.clear();
    s_rec_cw.clear();
    s_rec_tw.clear();
    s_rec_kw.clear();
    return ctx.ret(Value{});
}

// Builds an InstGroup (persistent VBOs) from vectors of baked instances.
static InstGroup build_group(const Mesh& mesh, const std::vector<Matrix>& xs, const std::vector<float>& cs,
                            const std::vector<float>& ts, const std::vector<float>& ks) {
    InstGroup g{};
    g.mesh = mesh;
    g.count = (int)xs.size();
    if (g.count > 0) {
        std::vector<float16> xf(g.count);
        for (int i = 0; i < g.count; i++) {
            xf[i] = MatrixToFloatV(xs[i]);
        }
        g.vbo_x = rlLoadVertexBuffer(xf.data(), g.count * (int)sizeof(float16), false);
        g.vbo_c = rlLoadVertexBuffer(cs.data(), g.count * 4 * (int)sizeof(float), false);
        g.vbo_t = rlLoadVertexBuffer(ts.data(), g.count * 3 * (int)sizeof(float), false);
        g.vbo_k = rlLoadVertexBuffer(ks.data(), g.count * 4 * (int)sizeof(float), false);
    }
    return g;
}

// Stores a baked group in s_groups, reusing a freed slot when one is available, which
// bounds the growth under endless streaming; otherwise it grows. Returns the 1-based id.
static int place_group(const InstGroup& g) {
    if (!s_free_groups.empty()) {
        int idx = s_free_groups.back();
        s_free_groups.pop_back();
        s_groups[idx] = g;
        return idx + 1;
    }
    s_groups.push_back(g);
    return (int)s_groups.size();
}

// graphics.endChunk(): bakes the recorded cubes into persistent VBOs and returns a handle
// { id, idw, count, wcount }. `id` is the OPAQUE group, `idw` the TRANSPARENT one (water,
// idw = 0 if there is none). It is redrawn every frame: drawChunk (opaque), then, after
// ALL the opaque, drawChunkAlpha (water).
static int gfx_end_chunk(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    s_recording = false;
    InstGroup g = build_group(s_rec_mesh, s_rec_x, s_rec_c, s_rec_t, s_rec_k);
    InstGroup w = build_group(s_rec_mesh_w, s_rec_xw, s_rec_cw, s_rec_tw, s_rec_kw);
    int id_o = place_group(g);
    int id_w = 0;                       // no slot without water, which avoids an empty group
    if (w.count > 0) {
        id_w = place_group(w);
    }
    s_rec_x.clear();
    s_rec_c.clear();
    s_rec_t.clear();
    s_rec_k.clear();
    s_rec_xw.clear();
    s_rec_cw.clear();
    s_rec_tw.clear();
    s_rec_kw.clear();
    Value h = Value::make_map();
    h.map_set(Value(std::string("id")), Value((int64_t)id_o));
    h.map_set(Value(std::string("idw")), Value((int64_t)id_w));
    h.map_set(Value(std::string("count")), Value((int64_t)g.count));
    h.map_set(Value(std::string("wcount")), Value((int64_t)w.count));
    return ctx.ret(h);
}

// graphics.drawChunk(handle): redraws a baked group in ONE instanced, lit call. To be
// called INSIDE a begin3d block. It re-emits NO cube from Ollin.
static int gfx_draw_chunk(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 1 || !args[0].is_map()) {
        throw std::runtime_error("graphics.drawChunk: expected a chunk handle (graphics.endChunk)");
    }
    Value idv = args[0].map_get(Value(std::string("id")));
    if (!idv.is_integer()) {
        throw std::runtime_error("graphics.drawChunk: invalid chunk handle");
    }
    int id = (int)idv.as_int();
    if (id < 1 || id > (int)s_groups.size()) {
        return ctx.ret(Value{});
    }
    InstGroup& g = s_groups[id - 1];
    if (g.count <= 0 || g.vbo_x == 0) {
        return ctx.ret(Value{});
    }
    if (!lit_begin_draw()) {
        return ctx.ret(Value{});
    }
    lit_bind_instances(g.mesh.vaoId, g.vbo_x, g.vbo_c, g.vbo_t, g.vbo_k);
    // The atlas is bound if declared (tiles >= 0 sample it), otherwise white (plain colour).
    // CONTRACT: with a tileset active, give a tile to EVERY cube of the chunk — a cube with
    // tile -1 would sample the atlas at fragTexCoord (tile 0) instead of a plain colour.
    lit_draw_instanced(g.mesh, s_atlas_texid, g.count, s_atlas_flipped);
    rlDisableShader();
    return ctx.ret(Value{});
}

// graphics.drawChunkAlpha(handle): draws the chunk's TRANSPARENT group (water) in alpha
// blending, so the opaque background already drawn shows through. Depth test and write
// are kept, so the water surface occludes itself cleanly, with no accumulation between
// layers. To be called INSIDE begin3d AFTER drawing ALL the chunks' opaque parts.
static int gfx_draw_chunk_alpha(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 1 || !args[0].is_map()) {
        return ctx.ret(Value{});
    }
    Value idv = args[0].map_get(Value(std::string("idw")));
    if (!idv.is_integer()) {
        return ctx.ret(Value{});
    }
    int id = (int)idv.as_int();
    if (id < 1 || id > (int)s_groups.size()) {
        return ctx.ret(Value{});
    }
    InstGroup& g = s_groups[id - 1];
    if (g.count <= 0 || g.vbo_x == 0) {
        return ctx.ret(Value{});
    }
    if (!lit_begin_draw()) {
        return ctx.ret(Value{});
    }
    BeginBlendMode(BLEND_ALPHA);
    lit_bind_instances(g.mesh.vaoId, g.vbo_x, g.vbo_c, g.vbo_t, g.vbo_k);
    lit_draw_instanced(g.mesh, s_atlas_texid, g.count, s_atlas_flipped);
    rlDisableShader();
    EndBlendMode();
    return ctx.ret(Value{});
}

// graphics.freeChunk(handle): frees a baked group's VBOs (an unloaded distant chunk),
// reclaiming GPU memory. The handle becomes a no-op when drawn. This is what makes an
// ENDLESS world possible: the chunks around the player are baked, the others freed.
static void free_group_by_id(Value& handle, const char* key) {
    Value idv = handle.map_get(Value(std::string(key)));
    if (!idv.is_integer()) {
        return;
    }
    int id = (int)idv.as_int();
    if (id < 1 || id > (int)s_groups.size()) {
        return;
    }
    InstGroup& g = s_groups[id - 1];
    bool live = g.vbo_x != 0 || g.vbo_c != 0 || g.vbo_t != 0 || g.vbo_k != 0 || g.count != 0;
    if (g.vbo_x) {
        rlUnloadVertexBuffer(g.vbo_x);
        g.vbo_x = 0;
    }
    if (g.vbo_c) {
        rlUnloadVertexBuffer(g.vbo_c);
        g.vbo_c = 0;
    }
    if (g.vbo_t) {
        rlUnloadVertexBuffer(g.vbo_t);
        g.vbo_t = 0;
    }
    if (g.vbo_k) {
        rlUnloadVertexBuffer(g.vbo_k);
        g.vbo_k = 0;
    }
    g.count = 0;
    // The slot returns to the pool ONLY if it was alive, which makes a double free idempotent
    // (a second free of the same handle is a no-op, with no duplicate slot in the pool).
    if (live) {
        s_free_groups.push_back(id - 1);
    }
}

static int gfx_free_chunk(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 1 || !args[0].is_map()) {
        return ctx.ret(Value{});
    }
    free_group_by_id(args[0], "id");    // the opaque group
    free_group_by_id(args[0], "idw");   // the transparent group (water)
    return ctx.ret(Value{});
}

// Resets the current 3D texture (called every frame by reset_styles, on the 2D side).
void reset3d_frame_state() {
    // Once per FRAME, not per chunk drawn: the two chunk draws asked per call and
    // image_gl_flipped scans every image, which is a hundred scans a frame for one texture. Asked
    // here and not only at tileset() time, because a script may paint the atlas by RENDERING into
    // it after declaring it, which changes the answer.
    if (s_atlas_texid != 0)
        s_atlas_flipped = image_gl_flipped(s_atlas_texid);
    s_cur_tex3d = 0;
    s_cur_tile[0] = -1.0f;
    s_cur_tile[1] = -1.0f;
    s_cur_tile[2] = -1.0f;
    for (int k = 0; k < 4; k++) {
        s_cur_corner[k] = 0.0f;
    }
}

// Current 3D texture, exposed for style save and restore (push/pushStyle).
unsigned int gfx3d_get_texture() {
    return s_cur_tex3d;
}
void gfx3d_set_texture(unsigned int id) {
    s_cur_tex3d = id;
}

// Registers the 3D builtins in the graphics module (called by make_graphics_module).
void register3d_graphics(Value& m) {
    m.map_set(Value(std::string("camera")), Value::make_builtin(gfx_camera));
    m.map_set(Value(std::string("cameraOrtho")), Value::make_builtin(gfx_camera_ortho));
    m.map_set(Value(std::string("begin3d")), Value::make_builtin(gfx_begin3d));
    m.map_set(Value(std::string("end3d")), Value::make_builtin(gfx_end3d));
    m.map_set(Value(std::string("ambient")), Value::make_builtin(gfx_ambient));
    m.map_set(Value(std::string("light")), Value::make_builtin(gfx_light));
    m.map_set(Value(std::string("texture")), Value::make_builtin(gfx_texture));
    m.map_set(Value(std::string("noTexture")), Value::make_builtin(gfx_no_texture));
    m.map_set(Value(std::string("tileset")), Value::make_builtin(gfx_tileset));
    m.map_set(Value(std::string("tiles")), Value::make_builtin(gfx_tiles));
    m.map_set(Value(std::string("tile")), Value::make_builtin(gfx_tile));
    m.map_set(Value(std::string("tileAnim")), Value::make_builtin(gfx_tile_anim));
    m.map_set(Value(std::string("corners")), Value::make_builtin(gfx_corners));
    m.map_set(Value(std::string("grid")), Value::make_builtin(gfx_grid));
    m.map_set(Value(std::string("cube")), Value::make_builtin(gfx_cube));
    m.map_set(Value(std::string("sphere")), Value::make_builtin(gfx_sphere));
    m.map_set(Value(std::string("cylinder")), Value::make_builtin(gfx_cylinder));
    m.map_set(Value(std::string("cone")), Value::make_builtin(gfx_cone));
    m.map_set(Value(std::string("torus")), Value::make_builtin(gfx_torus));
    m.map_set(Value(std::string("plane")), Value::make_builtin(gfx_plane));
    m.map_set(Value(std::string("model")), Value::make_builtin(gfx_model));
    m.map_set(Value(std::string("drawModel")), Value::make_builtin(gfx_draw_model));
    m.map_set(Value(std::string("modelSize")), Value::make_builtin(gfx_model_size));
    m.map_set(Value(std::string("fitDistance")), Value::make_builtin(gfx_fit_distance));
    m.map_set(Value(std::string("inFrustum")), Value::make_builtin(gfx_in_frustum));
    m.map_set(Value(std::string("beginChunk")), Value::make_builtin(gfx_begin_chunk));
    m.map_set(Value(std::string("endChunk")), Value::make_builtin(gfx_end_chunk));
    m.map_set(Value(std::string("drawChunk")), Value::make_builtin(gfx_draw_chunk));
    m.map_set(Value(std::string("drawChunkAlpha")), Value::make_builtin(gfx_draw_chunk_alpha));
    m.map_set(Value(std::string("freeChunk")), Value::make_builtin(gfx_free_chunk));
    m.map_set(Value(std::string("line3d")), Value::make_builtin(gfx_line3d));
    m.map_set(Value(std::string("point3d")), Value::make_builtin(gfx_point3d));
    m.map_set(Value(std::string("rotateq")), Value::make_builtin(gfx_rotateq));
    register_quat(m);   // quat / quatAxis / quatEuler (the Quat class, graphics_quat.cpp)
}
