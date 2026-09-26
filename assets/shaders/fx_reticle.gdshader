// 导弹 / 水苍蝇锁定准星：红色断口圆环（顺转）+ 四个刻度（逆转）+ 中心点，带深色描边；公告板，不做深度测试。
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.2, 0.26);
uniform float amount = 1.0;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x) + TIME * 1.8;
	float quad = fract(ang / 1.5707963);
	float ring = abs(r - 0.8) - 0.055;
	if (abs(quad - 0.5) < 0.09) {
		ring = 1.0;
	}
	float c = cos(-TIME * 1.2);
	float s = sin(-TIME * 1.2);
	vec2 q = abs(vec2(p.x * c - p.y * s, p.x * s + p.y * c));
	if (q.y > q.x) {
		q = q.yx;
	}
	float tick = seg(q, vec2(0.36, 0.0), vec2(0.6, 0.0)) - 0.05;
	float dotd = r - 0.08;
	float d = min(min(ring, tick), dotd);
	float fill = smoothstep(0.012, -0.012, d);
	float outline = smoothstep(0.05, 0.03, d);
	vec3 col = mix(vec3(0.1, 0.02, 0.04), color * 1.7, fill);
	ALBEDO = col;
	ALPHA = max(fill, outline * 0.85) * amount;
}
