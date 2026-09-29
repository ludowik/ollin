in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform vec2 texelSize;   // 1 / render texture size, same units as fragTexCoord
uniform float spanMax;    // how far, in texels, the edge search may slide (graphics.antialias size)

// FXAA (Lottes/NVIDIA "PC quality" formulation): find an edge from the luma of the four diagonal
// neighbours, then blur ALONG that edge rather than across it, so a texel straddling a hard
// boundary blends with its neighbour on the same side, not the one on the other side of the edge.
const float EDGE_THRESHOLD_MIN = 1.0 / 128.0;
const float EDGE_THRESHOLD_MUL = 1.0 / 8.0;

float luma(vec3 rgb) {
    return dot(rgb, vec3(0.299, 0.587, 0.114));
}

void main() {
    vec2 uv = fragTexCoord;
    vec3 rgbNW = texture(texture0, uv + vec2(-1.0, -1.0) * texelSize).rgb;
    vec3 rgbNE = texture(texture0, uv + vec2(1.0, -1.0) * texelSize).rgb;
    vec3 rgbSW = texture(texture0, uv + vec2(-1.0, 1.0) * texelSize).rgb;
    vec3 rgbSE = texture(texture0, uv + vec2(1.0, 1.0) * texelSize).rgb;
    vec3 rgbM = texture(texture0, uv).rgb;

    float lumaNW = luma(rgbNW);
    float lumaNE = luma(rgbNE);
    float lumaSW = luma(rgbSW);
    float lumaSE = luma(rgbSE);
    float lumaM = luma(rgbM);

    float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
    float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));

    vec2 dir;
    dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
    dir.y = ((lumaNW + lumaSW) - (lumaNE + lumaSE));

    float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * (0.25 * EDGE_THRESHOLD_MUL), EDGE_THRESHOLD_MIN);
    float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
    dir = clamp(dir * rcpDirMin, vec2(-spanMax), vec2(spanMax)) * texelSize;

    vec3 rgbA =
        0.5 * (texture(texture0, uv + dir * (1.0 / 3.0 - 0.5)).rgb + texture(texture0, uv + dir * (2.0 / 3.0 - 0.5)).rgb);
    vec3 rgbB = rgbA * 0.5 +
                0.25 * (texture(texture0, uv + dir * (0.0 / 3.0 - 0.5)).rgb + texture(texture0, uv + dir * (3.0 / 3.0 - 0.5)).rgb);

    float lumaB = luma(rgbB);
    vec3 rgbOut = (lumaB < lumaMin || lumaB > lumaMax) ? rgbA : rgbB;

    finalColor = vec4(rgbOut, 1.0) * colDiffuse * fragColor;
}
