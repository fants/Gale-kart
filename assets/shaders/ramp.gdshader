// 跳台：顶面黄黑斜纹 + V 字箭头；侧面黄黑警示。UV.y 沿跳台 0..1。
// wood：森林主题的木板跳台（横铺木板 + 黄色 V 字箭头，侧面木纹）。
shader_type spatial;
#include "res://assets/shaders/noise.gdshaderinc"
uniform bool side = false;
uniform bool wood = false;

void fragment() {
	vec3 yel = vec3(1.0, 0.78, 0.2);
	vec3 blk = vec3(0.1, 0.1, 0.12);
	vec3 col;
	if (side) {
		col = mix(yel, blk, step(0.5, fract((UV.x + UV.y) * 3.0)));
	} else {
		float x = abs(UV.x - 0.5) * 2.0;
		float chev = step(abs(fract(UV.y * 3.0) - x * 0.4 - 0.3), 0.12);
		float stripe = step(0.5, fract((UV.x * 6.0 + UV.y * 2.0)));
		col = mix(vec3(0.95, 0.95, 0.97), blk, stripe * 0.12);
		col = mix(col, vec3(1.0, 0.3, 0.37), chev);
		float edge = step(0.92, x);
		col = mix(col, mix(yel, blk, step(0.5, fract(UV.y * 8.0))), edge);
	}
	if (wood) {
		vec3 wa = vec3(0.62, 0.43, 0.26);
		vec3 wb = vec3(0.47, 0.31, 0.18);
		if (side) {
			float grain = vnoise(vec2(UV.x * 18.0, UV.y * 3.0));
			col = mix(wb, wa, grain) * 0.85;
		} else {
			float plank = fract(UV.y * 9.0);
			float id = floor(UV.y * 9.0);
			float grain = vnoise(vec2(UV.x * 30.0, id * 7.0));
			col = mix(wb, wa, 0.35 + 0.5 * grain + 0.15 * hash12(vec2(id, 3.0)));
			col *= 0.72 + 0.28 * smoothstep(0.0, 0.08, plank) * smoothstep(1.0, 0.92, plank);
			float x = abs(UV.x - 0.5) * 2.0;
			float chev = step(abs(fract(UV.y * 3.0) - x * 0.4 - 0.3), 0.1) * step(x, 0.7);
			col = mix(col, vec3(1.0, 0.78, 0.2), chev);
		}
	}
	ALBEDO = col;
	ROUGHNESS = wood ? 0.85 : 0.6;
}
