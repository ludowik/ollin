// Vertex stage of the lit, instanced 3D shader. The "#version" line is NOT here: it depends on
// the target (300 es under emscripten, 330 elsewhere) and is prepended by load_lit_shader.

in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec3 vertexNormal;
in vec4 vertexColor;
in mat4 instanceTransform;
in vec4 instanceColor;
in vec3 instanceTile;
uniform mat4 mvp;
out vec3 fragPosition;
out vec2 fragTexCoord;
out vec4 fragColor;
out vec3 fragNormal;
flat out vec3 fragTile;

void main() {
    mat4 m = instanceTransform;
    vec4 wp = m * vec4(vertexPosition, 1.0);
    fragPosition = wp.xyz;
    fragTexCoord = vertexTexCoord;
    fragColor = instanceColor * vertexColor;
    fragTile = instanceTile;
    mat3 nm = transpose(inverse(mat3(m)));   // the normal matrix: correct under a rotation or a non-uniform scale
    fragNormal = normalize(nm * vertexNormal);
    gl_Position = mvp * wp;
}
