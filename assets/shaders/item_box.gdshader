// 道具箱：半透明流动彩虹立方体，白色发光边框，每个面中间一个带描边的「?」。
// 用 MultiMesh 绘制；INSTANCE_CUSTOM.x 为每个箱子的色相偏移，.y 为透明度（弹出 / 消失）。
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform float half_size = 0.85;

varying vec3 v_local;
varying vec3 v_nlocal;
varying vec3 v_nworld;
varying float v_seed;
varying float v_alpha;

void vertex() {
	v_local = VERTEX / (half_size * 2.0);
	v_nlocal = NORMAL;
	v_nworld = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_seed = INSTANCE_CUSTOM.x;
	v_alpha = INSTANCE_CUSTOM.y;
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// 「?」的距离场，p 在 [-0.5, 0.5]，y 向上
float question(vec2 p) {
	vec2 c = vec2(0.0, 0.1);
	vec2 q = p - c;
	float r = 0.13;
	float ang = atan(q.y, q.x);
	// 圆弧：从右下（-0.8 rad）逆时针绕过顶部到左侧略低处
	bool on_arc = ang > -0.8 || ang < -2.84;
	float d = on_arc ? abs(length(q) - r) : 1.0;
	vec2 e1 = c + r * vec2(cos(-0.8), sin(-0.8));
	vec2 e2 = c + r * vec2(cos(-2.84), sin(-2.84));
	d = min(d, min(length(p - e1), length(p - e2)));
	// 弯向中间的竖笔
	d = min(d, seg_dist(p, e1, vec2(0.0, -0.07)));
	d = min(d, seg_dist(p, vec2(0.0, -0.07), vec2(0.0, -0.11)));
	float stroke = d - 0.05;
	float dot_d = length(p - vec2(0.0, -0.25)) - 0.058;
	return min(stroke, dot_d);
}

void fragment() {
	vec3 n = v_nlocal;
	vec3 an = abs(n);
	vec2 f;
	if (an.x > 0.5) {
		f = vec2(-v_local.z * sign(n.x), v_local.y);
	} else if (an.z > 0.5) {
		f = vec2(v_local.x * sign(n.z), v_local.y);
	} else {
		f = vec2(v_local.x, -v_local.z * sign(n.y));
	}
	float box_d = max(abs(f.x), abs(f.y));
	// 流动的彩虹色
	float hue = fract(f.x * 0.45 + f.y * 0.6 + TIME * 0.22 + v_seed + dot(v_nlocal, vec3(0.13, 0.27, 0.41)));
	vec3 rainbow = clamp(abs(mod(hue * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	rainbow = mix(vec3(1.0), rainbow, 0.62);
	// 假光照：朝上的面亮一点
	float lit = 0.82 + 0.25 * clamp(v_nworld.y, 0.0, 1.0);
	vec3 col = rainbow * lit;
	float a = 0.58;
	// 内部柔光（中心更亮）
	col += vec3(0.25) * (1.0 - smoothstep(0.0, 0.5, length(f)));
	// 边框
	float frame = smoothstep(0.405, 0.43, box_d);
	col = mix(col, vec3(1.35), frame);
	a = mix(a, 0.95, frame);
	// 「?」：深色描边 + 白色字
	float q = question(f * 1.05);
	float outline = smoothstep(0.035, 0.02, q);
	float glyph = smoothstep(0.008, -0.006, q);
	col = mix(col, vec3(0.106, 0.122, 0.231), outline * (1.0 - glyph));
	col = mix(col, vec3(1.3), glyph);
	a = max(a, outline * 0.95);
	// 轮廓光
	float fr = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	col += vec3(0.4) * fr;
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0) * v_alpha;
}
