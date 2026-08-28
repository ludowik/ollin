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
uniform mat4 mvp;
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
            vn = normalize(vec3(-dhx, 1.0, -dhz));
        }
    }

    vec4 wp = m * vec4(vp, 1.0);
    fragPosition = wp.xyz;
    fragTexCoord = vertexTexCoord;
    fragColor = instanceColor * vertexColor;
    fragTile = instanceTile;
    mat3 nm = transpose(inverse(mat3(m)));   // the normal matrix: correct under a rotation or a non-uniform scale
    fragNormal = normalize(nm * vn);
    gl_Position = mvp * wp;
}
