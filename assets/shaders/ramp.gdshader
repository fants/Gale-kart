// 跳台：顶面黄黑斜纹 + V 字箭头；侧面黄黑警示。UV.y 沿跳台 0..1。
shader_type spatial;
uniform bool side = false;

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
	ALBEDO = col;
	ROUGHNESS = 0.6;
}
