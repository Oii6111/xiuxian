shader_type spatial;
render_mode cull_disabled, specular_disabled;
uniform vec4 ink_color : source_color = vec4(0.57, 0.7, 0.58, 1.0);
void vertex() {
    VERTEX.x += sin(TIME * 2.3 + UV.y * 7.0) * UV.y * 0.08;
    VERTEX.y += sin(TIME * 2.0 + UV.y * 5.0) * UV.y * 0.07;
}
void fragment() { ALBEDO = ink_color.rgb * (0.97 + sin(UV.y * 40.0) * 0.025); ROUGHNESS = 1.0; }
void light() {
    float level = mix(0.25, 1.0, smoothstep(-0.1, 0.85, dot(NORMAL, LIGHT)));
    DIFFUSE_LIGHT += LIGHT_COLOR * (ATTENUATION / PI) * level;
}
