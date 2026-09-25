// 弯道路缘：两色 2 m 交替，外沿略暗。UV.y 为米。
shader_type spatial;
uniform vec3 color_a : source_color = vec3(1.0, 0.3, 0.37);
uniform vec3 color_b : source_color = vec3(1.0);
uniform float glow = 0.0;

void fragment() {
	float band = step(0.5, fract(UV.y / 4.0));
	vec3 col = mix(color_a, color_b, band);
	col *= 0.85 + 0.15 * smoothstep(0.0, 0.3, UV.x);
	ALBEDO = col;
	ROUGHNESS = 0.7;
	EMISSION = col * glow * (1.0 - band * 0.5);
}
