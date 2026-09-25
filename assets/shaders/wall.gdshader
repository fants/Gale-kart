// 主题护墙。UV.x 沿赛道（米），UV.y：0 地面 .. 1 墙顶（地下部分为负）。
// style: 0 栅栏 1 石墙 2 冰墙 3 霓虹 4 原木 5 轮胎墙
shader_type spatial;
render_mode cull_disabled;
#include "res://assets/shaders/noise.gdshaderinc"

uniform int style = 0;
uniform vec3 color_a : source_color = vec3(1.0);
uniform vec3 color_b : source_color = vec3(0.24, 0.78, 1.0);

void fragment() {
	float u = UV.x;
	float v = clamp(UV.y, 0.0, 1.0);
	vec3 col = color_a;
	vec3 emit = vec3(0.0);
	float rough = 0.8;
	if (style == 0) {
		// 白柱 + 蓝色横板
		float post = step(fract(u / 2.5), 0.12);
		float board = step(0.25, fract(v * 2.0)) * step(fract(v * 2.0), 0.8);
		col = mix(color_a * 0.92, color_b, board * (1.0 - post));
		col = mix(col, color_a, post);
	} else if (style == 1) {
		// 砖石
		vec2 bc = vec2(u / 1.2, v * 3.0);
		bc.x += step(1.0, mod(floor(bc.y), 2.0)) * 0.5;
		vec2 f = fract(bc);
		float mortar = step(f.x, 0.04) + step(f.y, 0.08);
		float tone = hash12(floor(bc));
		col = mix(color_a, color_b, tone * 0.8);
		col = mix(col, color_b * 0.6, clamp(mortar, 0.0, 1.0));
	} else if (style == 2) {
		// 冰：高光 + 裂纹
		float crack = smoothstep(0.02, 0.0, abs(vnoise(vec2(u, v * 2.0) * 3.0) - 0.5));
		col = mix(color_b, color_a, v) + crack * 0.4;
		rough = 0.08;
		emit = color_a * 0.12;
	} else if (style == 3) {
		// 霓虹：深色墙体 + 两道发光条，按段交替颜色
		vec3 neon = mix(color_a, color_b, step(0.5, fract(u / 24.0)));
		float strip = smoothstep(0.06, 0.0, abs(v - 0.82)) + smoothstep(0.04, 0.0, abs(v - 0.3)) * 0.6;
		col = mix(vec3(0.09, 0.1, 0.16), neon, strip);
		emit = neon * strip * 3.5;
	} else if (style == 4) {
		// 原木：横向圆木，明暗条纹
		float logv = fract(v * 3.0);
		float shade = sin(logv * 3.14159);
		float grain = vnoise(vec2(u * 3.0, v * 30.0));
		col = mix(color_b, color_a, shade) * (0.85 + 0.2 * grain);
	} else if (style == 5) {
		// 轮胎墙：黑色轮胎堆，顶部一圈红白涂装
		float tire = fract(u / 0.7);
		float ring = smoothstep(0.0, 0.2, tire) * smoothstep(1.0, 0.8, tire);
		col = vec3(0.07) + vec3(0.06) * ring;
		float paint = step(0.72, v);
		vec3 stripe = mix(color_b, vec3(0.95), step(0.5, fract(u / 2.8)));
		col = mix(col, stripe, paint);
		rough = 0.9;
	}
	// 底部接地处稍暗
	col *= 0.7 + 0.3 * smoothstep(0.0, 0.25, v);
	ALBEDO = col;
	ROUGHNESS = rough;
	EMISSION = emit;
}
