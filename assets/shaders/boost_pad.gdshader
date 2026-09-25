// 加速带：发光箭头向前滚动。UV.x 横向 0..1，UV.y 纵向 0..1（向前）。
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 color_a : source_color = vec3(1.0, 0.72, 0.29);
uniform vec3 color_b : source_color = vec3(1.0, 0.95, 0.6);
uniform float speed = 1.6;

void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	float y = fract(UV.y * 3.0 - TIME * speed);
	float chev = step(abs(y - x * 0.45 - 0.35), 0.16);
	float border = step(0.9, x);
	vec3 col = mix(vec3(0.12, 0.06, 0.02), color_a, chev);
	col = mix(col, color_b, border);
	ALBEDO = col;
	EMISSION = (chev * color_a + border * color_b) * 2.2;
}
