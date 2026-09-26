// 天使护盾：金色半透明泡泡。菲涅尔金边 + 六边形网格 + 自下而上扫过的亮带；strength 用于出现 / 快结束时闪烁。
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec3 gold : source_color = vec3(1.0, 0.82, 0.3);
uniform float strength = 1.0;

varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
}

// 到六边形格子边缘的距离（格子中心 0.5，边上 0）
float hex_edge(vec2 p) {
	const vec2 s = vec2(1.0, 1.7320508);
	vec4 hc = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
	vec4 h = vec4(p - hc.xy * s, p - (hc.zw + 0.5) * s);
	vec2 q = dot(h.xy, h.xy) < dot(h.zw, h.zw) ? h.xy : h.zw;
	q = abs(q);
	return 0.5 - max(dot(q, s * 0.5), q.x);
}

void fragment() {
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fr = pow(1.0 - nv, 2.4);
	vec2 huv = vec2(atan(v_obj.z, v_obj.x) / 6.2831853 * 16.0, v_obj.y * 4.2);
	float grid = smoothstep(0.07, 0.0, hex_edge(huv));
	float band = smoothstep(0.16, 0.0, abs(fract(v_obj.y * 0.45 - TIME * 0.8) - 0.5));
	vec3 col = gold * (1.15 + fr * 1.4) + vec3(1.0, 0.95, 0.8) * band * 0.6;
	float a = 0.07 + fr * 0.8 + grid * (0.12 + 0.35 * band) + band * 0.1;
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0) * strength;
}
