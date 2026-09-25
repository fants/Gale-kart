// 发车格标记：白色 U 形框。UV 0..1。
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never;
void fragment() {
	vec2 u = UV;
	float frame = step(u.x, 0.08) + step(0.92, u.x) + step(0.9, u.y);
	ALBEDO = vec3(1.0);
	ALPHA = clamp(frame, 0.0, 1.0) * 0.9;
}
