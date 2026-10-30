shader_type spatial;
render_mode specular_disabled;
uniform vec4 ink_color : source_color = vec4(0.45, 0.6, 0.5, 1.0);
uniform float paper_amount = 0.025;
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    float grain = fract(sin(dot(floor(world_pos.xz * 110.0 + world_pos.y * 37.0), vec2(127.1,311.7))) * 43758.5453);
    ALBEDO = ink_color.rgb + (grain - 0.5) * paper_amount;
    ROUGHNESS = 1.0;
}
void light() {
    float level = mix(0.25, 1.0, smoothstep(-0.1, 0.85, dot(NORMAL, LIGHT)));
    DIFFUSE_LIGHT += LIGHT_COLOR * (ATTENUATION / PI) * level;
}
