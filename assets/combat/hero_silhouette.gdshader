shader_type canvas_item;
render_mode unshaded;
void fragment() {
    float body = texture(TEXTURE,UV).a;
    vec2 px = TEXTURE_PIXEL_SIZE*1.5;
    float surround = max(max(texture(TEXTURE,UV+vec2(px.x,0)).a,texture(TEXTURE,UV-vec2(px.x,0)).a),max(texture(TEXTURE,UV+vec2(0,px.y)).a,texture(TEXTURE,UV-vec2(0,px.y)).a));
    COLOR = vec4(0.64,1.0,0.88,clamp(surround-body,0.0,1.0)*0.85+body*0.18);
}
