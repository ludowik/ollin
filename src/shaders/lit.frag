// Fragment stage of the lit, instanced 3D shader. The "#version" line is NOT here: it depends on
// the target (300 es under emscripten, 330 elsewhere) and is prepended by load_lit_shader.

in vec3 fragPosition;
in vec2 fragTexCoord;
in vec4 fragColor;
in vec3 fragNormal;
flat in vec3 fragTile;
uniform sampler2D texture0;
uniform vec2 atlasGrid;
uniform float uTime;
uniform float animTile;
uniform vec4 animParams;
// 1.0 when the bound texture's rows are bottom-up — an image painted by image.beginDraw, OpenGL's
// framebuffer origin being at the bottom. abs(uFlipV - v) is the flip without a branch: v when
// uFlipV is 0, 1 - v when it is 1.
uniform float uFlipV;
uniform vec4 ambient;
uniform vec3 viewPos;
struct Light { int enabled; int type; vec3 position; vec3 target; vec4 color; };
uniform Light light0;
out vec4 finalColor;

void main() {
    vec4 texel;
    if (fragTile.x >= 0.0) {                          // an atlas cube: the tile follows the face, from the normal
        float t = fragTile.y;                         //   the side face by default
        if (fragNormal.y > 0.5) t = fragTile.x;       //   the top face
        else if (fragNormal.y < -0.5) t = fragTile.z; //   the bottom face
        float cols = atlasGrid.x;
        vec2 cell = vec2(mod(t, cols), floor(t / cols));
        vec2 uv = fract(fragTexCoord);
        // The animated tile, water: scrolling plus a sine ripple. sc is the scroll, ws the wave
        // speed, wf the spatial frequency and wa the amplitude. The phase is taken in WORLD
        // coordinates (fragPosition), so the ripple carries on from one tile to the next.
        if (animTile >= 0.0 && abs(t - animTile) < 0.5) {
            float sc = animParams.x; float ws = animParams.y;
            float wf = animParams.z; float wa = animParams.w;
            uv = fract(uv + vec2(uTime * sc + sin(uTime * ws + fragPosition.z * wf) * wa,
                                 uTime * sc * 0.66 + cos(uTime * ws * 0.8 + fragPosition.x * wf) * wa));
        }
        uv = clamp(uv, 0.002, 0.998);   // a slight inset, which avoids bleeding between tiles
        vec2 auv = (cell + uv) / atlasGrid;
        auv.y = abs(uFlipV - auv.y);    // the WHOLE atlas is flipped, so the cell moves with it
        texel = texture(texture0, auv);
        // Alpha test (pierced foliage): a hole in the TILE pierces the cube. Sharp rather than
        // faded, hence independent of draw order — the cubes stay opaque and need no sorting.
        // Limited to the atlas path: a semi-transparent texture laid on a model keeps its fade.
        if (texel.a < 0.5) discard;
    } else {                            // the ordinary path: models, and the immediate texture
        texel = texture(texture0, vec2(fragTexCoord.x, abs(uFlipV - fragTexCoord.y)));
    }

    vec4 tint = fragColor;
    vec3 base = (texel * tint).rgb;
    vec3 normal = normalize(fragNormal);
    vec3 result = base * ambient.rgb;
    if (light0.enabled == 1) {
        vec3 l;
        if (light0.type == 0) l = -normalize(light0.target - light0.position);
        else l = normalize(light0.position - fragPosition);
        float ndl = max(dot(normal, l), 0.0);
        result += base * light0.color.rgb * ndl;
        if (ndl > 0.0) {
            vec3 viewD = normalize(viewPos - fragPosition);
            float spec = pow(max(dot(viewD, reflect(-l, normal)), 0.0), 16.0);
            result += light0.color.rgb * spec * 0.3;
        }
    }
    finalColor = vec4(result, texel.a * tint.a);
}
