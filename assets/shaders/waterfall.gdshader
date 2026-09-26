// 瀑布水帘：竖直面片，UV.y 0 顶 → 1 底。向下滚动的拉长噪声条纹，两侧渐隐，底部翻白沫，顶部略带水流弧光。
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley;
#include "res://assets/shaders/noise.gdshaderinc"

uniform vec3 water_color : source_color = vec3(0.45, 0.82, 0.86);
uniform vec3 foam_color : source_color = vec3(0.95, 0.99, 1.0);
uniform float speed = 1.4;
uniform float width_m = 10.0;
uniform float height_m = 10.0;

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;
	// 条纹：横向高频、纵向低频，随时间下落（越往下越快）
	float fall = uv.y * height_m * 0.12;
	vec2 q = vec2(uv.x * width_m * 0.9, fall - t * (1.0 + uv.y * 0.8));
	float s1 = vnoise(vec2(q.x * 1.3, q.y * 1.1));
	float s2 = vnoise(vec2(q.x * 3.1 + 5.0, q.y * 2.3));
	float streak = smoothstep(0.35, 0.85, s1 * 0.6 + s2 * 0.4);
	vec3 col = mix(water_color, foam_color, streak * 0.75 + 0.1);
	// 底部白沫
	float bottom = smoothstep(0.72, 1.0, uv.y);
	col = mix(col, foam_color, bottom * (0.6 + 0.4 * vnoise(vec2(uv.x * width_m * 1.5, t * 2.0))));
	float side = smoothstep(0.0, 0.12, uv.x) * smoothstep(1.0, 0.88, uv.x);
	ALBEDO = col;
	EMISSION = col * 0.18;
	ROUGHNESS = 0.2;
	SPECULAR = 0.5;
	ALPHA = side * mix(0.78, 0.95, streak) * smoothstep(0.0, 0.03, uv.y);
}
