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
uniform vec2 specular;   // the highlight: strength, then the exponent that narrows it (graphics.specular)
uniform vec2 bump;       // relief read from the texture: the height of a white texel, then of the grain (graphics.bump)
uniform vec3 viewPos;
struct Light { int enabled; int type; vec3 position; vec3 target; vec4 color; };
uniform Light light0;
out vec4 finalColor;

// A value noise, smooth enough for its slope to be taken.
float hash12(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}
float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

// The normal bent by a height that varies over the surface. The height's slope comes from the screen
// derivatives of the height and of the position, so that no tangent is needed.
vec3 bent_normal(vec3 n, float h) {
    vec3 dpx = dFdx(fragPosition);
    vec3 dpy = dFdy(fragPosition);
    vec3 r1 = cross(dpy, n);
    vec3 r2 = cross(n, dpx);
    float det = dot(dpx, r1);
    vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
    return normalize(abs(det) * n - grad);
}

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
    if (fragTile.x < 0.0 && (bump.x > 0.0 || bump.y > 0.0)) {
        vec2 texture_size = vec2(textureSize(texture0, 0));
        // The blank 1x1 texture of an untextured surface has no relief to read: the grain would be laid on it all the same.
        if (max(texture_size.x, texture_size.y) > 1.0) {
            vec2 texels = vec2(fragTexCoord.x, abs(uFlipV - fragTexCoord.y)) * texture_size;
            float lum = dot(texel.rgb, vec3(0.299, 0.587, 0.114));
            // The grain only appears where a texel covers more than a pixel, and grows as it covers more.
            float per_pixel = max(length(dFdx(texels)), length(dFdy(texels)));
            float magnified = 1.0 - smoothstep(0.25, 1.0, per_pixel);
            float grain = 0.0;
            if (bump.y > 0.0 && magnified > 0.0) {
                grain = (value_noise(texels * 1.5) + 0.5 * value_noise(texels * 3.5) - 0.75) * (0.3 + lum);
            }
            float height = lum * bump.x + grain * magnified * bump.y;
            normal = bent_normal(normal, height);
        }
    }
    vec3 result = base * ambient.rgb;
    if (light0.enabled == 1) {
        vec3 l;
        if (light0.type == 0) l = -normalize(light0.target - light0.position);
        else l = normalize(light0.position - fragPosition);
        float ndl = max(dot(normal, l), 0.0);
        result += base * light0.color.rgb * ndl;
        if (ndl > 0.0) {
            vec3 viewD = normalize(viewPos - fragPosition);
            float spec = pow(max(dot(viewD, reflect(-l, normal)), 0.0), specular.y);
            result += light0.color.rgb * spec * specular.x;
        }
    }
    finalColor = vec4(result, texel.a * tint.a);
}
