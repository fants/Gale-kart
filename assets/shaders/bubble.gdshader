// 泡泡 / 水体：边缘（菲涅尔）更不透明并带薄膜彩虹色，中间通透；固定的「窗口」高光点；可选表面晃动。
// 用于水泡（困住赛车）、水炸弹、水苍蝇身体。
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

uniform vec3 tint : source_color = vec3(0.35, 0.72, 1.0);
uniform float base_alpha = 0.16;
uniform float rim_alpha = 0.85;
uniform float iridescence = 1.0;
uniform float wobble = 0.0;
uniform float fade = 1.0;

void vertex() {
	float w = sin(VERTEX.y * 4.5 + TIME * 6.0) * cos(VERTEX.x * 3.5 - TIME * 5.0) + sin(VERTEX.z * 4.0 + TIME * 4.0) * 0.5;
	VERTEX += NORMAL * w * wobble;
}

void fragment() {
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fr = pow(1.0 - nv, 2.2);
	vec3 irid = 0.5 + 0.5 * cos(6.2831853 * (fr * 1.3 + TIME * 0.12 + vec3(0.0, 0.33, 0.67)));
	vec3 rim = mix(tint, irid, iridescence * 0.65);
	// 视空间里固定方向的高光点（像反射的窗户）
	float spot = smoothstep(0.94, 0.975, dot(NORMAL, normalize(vec3(-0.45, 0.55, 0.7))));
	float spot2 = smoothstep(0.985, 0.995, dot(NORMAL, normalize(vec3(0.5, -0.35, 0.8))));
	ALBEDO = tint * 0.35;
	ROUGHNESS = 0.06;
	SPECULAR = 0.9;
	EMISSION = rim * fr * 1.3 + tint * 0.1 + vec3(1.0) * (spot * 1.6 + spot2 * 0.8);
	ALPHA = clamp(mix(base_alpha, rim_alpha, fr) + spot * 0.85 + spot2 * 0.5, 0.0, 1.0) * fade;
}
