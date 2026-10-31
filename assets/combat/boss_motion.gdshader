shader_type canvas_item;
render_mode unshaded;
uniform float animation_clock = 0.0;
uniform float locomotion = 0.0;
uniform float anticipation = 0.0;
uniform float wing_motion = 0.0;
uniform float broken = 0.0;
uniform vec4 element_color : source_color = vec4(1.0,0.7,0.4,1.0);
varying vec4 actor_color;
void vertex() { actor_color = COLOR; }
void fragment() {
    vec2 p = UV;
    float feet = smoothstep(0.56,0.90,p.y);
    float sides = smoothstep(0.16,0.45,abs(p.x-0.5));
    float wings = sides*(1.0-smoothstep(0.52,0.80,p.y));
    p.x += sin(animation_clock*10.0+p.y*19.0)*0.010*feet*locomotion;
    p.y += sin(animation_clock*8.5+p.x*7.0)*0.012*wings*wing_motion;
    p.x += sin(animation_clock*23.0+p.y*10.0)*0.004*broken;
    vec4 texel = texture(TEXTURE,clamp(p,vec2(0.001),vec2(0.999)));
    vec2 px = TEXTURE_PIXEL_SIZE*1.5;
    float neighbor = min(min(texture(TEXTURE,p+vec2(px.x,0)).a,texture(TEXTURE,p-vec2(px.x,0)).a),min(texture(TEXTURE,p+vec2(0,px.y)).a,texture(TEXTURE,p-vec2(0,px.y)).a));
    float rim = clamp(texel.a-neighbor,0.0,1.0);
    vec3 glow = mix(element_color.rgb,vec3(0.70,0.95,1.0),broken);
    texel.rgb += glow*rim*(anticipation*0.9+broken*0.6);
    texel.rgb = mix(texel.rgb,glow,anticipation*0.055);
    COLOR = texel*actor_color;
}
