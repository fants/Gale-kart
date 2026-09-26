// 天使翅膀（护盾时出现）：肩部圆弧 + 三层向外上方伸展的羽毛，白色带金边；UV.x 0 为翅根。
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float alpha = 1.0;

float ell(vec2 p, vec2 c, vec2 r, float ang) {
	vec2 q = p - c;
	float cs = cos(ang);
	float sn = sin(ang);
	q = vec2(cs * q.x + sn * q.y, -sn * q.x + cs * q.y);
	return length(q / r) - 1.0;
}

void fragment() {
	vec2 p = vec2(UV.x, 1.0 - UV.y);
	float shoulder = ell(p, vec2(0.28, 0.6), vec2(0.28, 0.2), 0.35);
	float f1 = ell(p, vec2(0.56, 0.68), vec2(0.42, 0.12), 0.45);
	float f2 = ell(p, vec2(0.52, 0.5), vec2(0.4, 0.11), 0.3);
	float f3 = ell(p, vec2(0.45, 0.34), vec2(0.34, 0.1), 0.15);
	float d = min(shoulder, min(f1, min(f2, f3)));
	float inside = smoothstep(0.06, -0.02, d);
	// 外轮廓金边 + 每层羽毛的分隔线
	float rim = smoothstep(-0.18, -0.02, d);
	float lines = max(smoothstep(0.06, 0.0, abs(f2)) * step(f1, 0.0), smoothstep(0.06, 0.0, abs(f3)) * step(f2, 0.0));
	vec3 col = vec3(1.12);
	col = mix(col, vec3(1.0, 0.82, 0.4) * 1.2, max(rim * 0.85, lines * 0.6));
	ALBEDO = col;
	ALPHA = inside * alpha;
}
