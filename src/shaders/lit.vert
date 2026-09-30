// Vertex stage of the lit, instanced 3D shader. The "#version" line is NOT here: it depends on
// the target (300 es under emscripten, 330 elsewhere) and is prepended by load_lit_shader.

in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec3 vertexNormal;
in vec4 vertexColor;
in mat4 instanceTransform;
in vec4 instanceColor;
in vec3 instanceTile;
in vec4 instanceCorner;
in vec4 instanceSlopeX;
in vec4 instanceSlopeZ;
in vec4 instanceMix;
uniform mat4 mvp;
uniform vec4 blendColorB;
out vec3 fragPosition;
out vec2 fragTexCoord;
out vec4 fragColor;
out vec3 fragNormal;
flat out vec3 fragTile;

void main() {
    mat4 m = instanceTransform;
    vec3 vp = vertexPosition;
    vec3 vn = vertexNormal;

    // Corner heights (instanceCorner, in LOCAL units): the TOP vertices rise by the bilinear
    // interpolation of the four corners — exact at the corners, the unit mesh's vertices being
    // at ±0.5. The top vertices of the side faces follow the same value, so there is no crack
    // against the top face. The top normal is rebuilt from the slopes, otherwise the relief
    // would still look flat.
    //
    // The whole block is guarded by "this instance CARRIES corner heights", and not by the
    // displacement being zero. Without that guard the normal rebuild ran for EVERY instanced
    // mesh: on a sphere, every vertex of the upper cap (vn.y > 0.5) had its normal replaced by
    // the vertical, so the cap was lit as a flat surface and a staircase seam appeared exactly
    // where vn.y crosses 0.5 along the mesh's rings. Reported on the "Primitives 3D" example.
    if (any(notEqual(instanceCorner, vec4(0.0))) && vp.y > 0.0) {
        float u = vp.x + 0.5;
        float v = vp.z + 0.5;
        vp.y += mix(mix(instanceCorner.x, instanceCorner.y, u),
                    mix(instanceCorner.z, instanceCorner.w, u), v);
        if (vn.y > 0.5) {
            float dhx = (instanceCorner.y + instanceCorner.w - instanceCorner.x - instanceCorner.z) * 0.5;
            float dhz = (instanceCorner.z + instanceCorner.w - instanceCorner.x - instanceCorner.y) * 0.5;
            // Slopes given per corner (graphics.cornerSlopes): this top vertex IS one of the four
            // corners, so the bilinear pick returns its own slope pair, and the normal the
            // fragment stage interpolates is shared with the neighbouring cell — no crease.
            if (any(notEqual(instanceSlopeX, vec4(0.0))) || any(notEqual(instanceSlopeZ, vec4(0.0)))) {
                dhx = mix(mix(instanceSlopeX.x, instanceSlopeX.y, u), mix(instanceSlopeX.z, instanceSlopeX.w, u), v);
                dhz = mix(mix(instanceSlopeZ.x, instanceSlopeZ.y, u), mix(instanceSlopeZ.z, instanceSlopeZ.w, u), v);
            }
            vn = normalize(vec3(-dhx, 1.0, -dhz));
        }
    }

    // Corner colours (instanceMix, graphics.mixCorners): a SECOND colour, blendColorB — one
    // uniform, shared by the whole draw call, not per-instance — mixed in by the bilinear
    // interpolation of four PER-INSTANCE mix factors, the same u/v as the height above. Lets a
    // baked terrain shade road grey into grass green smoothly, pixel by pixel, instead of one
    // flat colour per cube: a flat per-instance blend changes between two adjacent cells no
    // matter how little of the geometry actually crosses the boundary, which reads as speckle at
    // this scale. Guarded the same way as instanceCorner: zero mix everywhere already yields
    // instanceColor unchanged, so the guard is only there to skip the work, not to change the
    // result.
    vec4 baseColor = instanceColor;
    if (any(notEqual(instanceMix, vec4(0.0)))) {
        float mu = vp.x + 0.5;
        float mv = vp.z + 0.5;
        float amt = mix(mix(instanceMix.x, instanceMix.y, mu),
                        mix(instanceMix.z, instanceMix.w, mu), mv);
        baseColor = mix(instanceColor, blendColorB, clamp(amt, 0.0, 1.0));
    }

    vec4 wp = m * vec4(vp, 1.0);
    fragPosition = wp.xyz;
    fragTexCoord = vertexTexCoord;
    fragColor = baseColor * vertexColor;
    fragTile = instanceTile;
    mat3 nm = transpose(inverse(mat3(m)));   // the normal matrix: correct under a rotation or a non-uniform scale
    fragNormal = normalize(nm * vn);
    gl_Position = mvp * wp;
}
