shader_type spatial;
render_mode unshaded, cull_front;
void vertex() { VERTEX += NORMAL * 0.007; }
void fragment() { ALBEDO = vec3(0.10, 0.16, 0.13); }
