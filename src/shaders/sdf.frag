in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

uniform sampler2D texture0;

// The engine fonts are signed distance fields (tools/gen_ui_font.cpp): the alpha of a texel is its
// distance to the outline, 0.5 ON the outline. Redrawing the edge from that distance keeps it crisp at
// any size, where the glyph's own coverage would just be stretched. The width of the transition is how
// much the distance changes across ONE screen pixel, so the edge is exactly one pixel soft whatever the
// scale — and the density of the screen.
void main() {
    float distance = texture(texture0, fragTexCoord).a - 0.5;
    float width = max(length(vec2(dFdx(distance), dFdy(distance))), 0.0001);
    float coverage = smoothstep(-width, width, distance);
    finalColor = vec4(fragColor.rgb, fragColor.a * coverage);
}
