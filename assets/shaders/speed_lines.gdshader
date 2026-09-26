// 屏幕叠加层（不读屏幕纹理）：速度线、氮气边缘蓝光、乌云压暗 + 顶部云团 + 雨丝、水泡泛蓝 + 泡泡边缘、导弹锁定红边。
// 各强度 0..1 由 ScreenFx 平滑后传入；全部为 0 时 ScreenFx 隐藏本层。
shader_type canvas_item;
render_mode unshaded;

uniform float speed_amt = 0.0;
uniform float boost_amt = 0.0;
uniform vec3 boost_color : source_color = vec3(0.45, 0.8, 1.0);
uniform float lock_amt = 0.0;
uniform float cloud_amt = 0.0;
uniform float bubble_amt = 0.0;

float h11(float n) {
	return fract(sin(n * 127.1 + 11.3) * 43758.5453);
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// 把 src（非预乘）叠到累积结果 acc（预乘）上
vec4 over(vec4 acc, vec3 c, float a) {
	a = clamp(a, 0.0, 1.0);
	return vec4(c * a + acc.rgb * (1.0 - a), a + acc.a * (1.0 - a));
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 c = (UV - 0.5) * vec2(aspect, 1.0);
	float r = length(c);
	// 0 屏幕中心 → 1 屏幕角
	float rn = r / (0.5 * length(vec2(aspect, 1.0)));
	vec4 acc = vec4(0.0);

	// —— 乌云：整体压暗、顶部垂下的云团、斜向雨丝 ——
	if (cloud_amt > 0.001) {
		acc = over(acc, vec3(0.04, 0.05, 0.1), cloud_amt * (0.22 + 0.38 * smoothstep(0.25, 1.0, rn)));
		float n = vnoise(vec2(UV.x * aspect * 3.2 + TIME * 0.06, TIME * 0.05)) * 0.65 + vnoise(vec2(UV.x * aspect * 8.0 - TIME * 0.1, 3.0)) * 0.35;
		float edge = cloud_amt * (0.1 + 0.13 * n);
		float band = smoothstep(edge, edge - 0.05, UV.y);
		acc = over(acc, mix(vec3(0.1, 0.11, 0.17), vec3(0.2, 0.21, 0.3), smoothstep(edge - 0.1, edge, UV.y)), band * 0.95);
		vec2 ruv = vec2(UV.x * aspect + UV.y * 0.16, UV.y);
		float col_id = floor(ruv.x * 70.0);
		float fx = fract(ruv.x * 70.0);
		float rh = h11(col_id);
		float y = fract(ruv.y * 1.3 - TIME * (1.4 + rh * 1.2) + rh * 10.0);
		float drop = smoothstep(0.3, 0.0, abs(fx - 0.5)) * smoothstep(0.0, 0.02, y) * smoothstep(0.16, 0.06, y) * step(0.45, rh);
		acc = over(acc, vec3(0.8, 0.86, 1.0), drop * 0.4 * cloud_amt);
	}

	// —— 水泡：泛蓝 + 泡泡边缘的彩虹光圈 + 高光 ——
	if (bubble_amt > 0.001) {
		acc = over(acc, vec3(0.2, 0.55, 1.0), bubble_amt * 0.16);
		float rim = smoothstep(0.62, 0.98, rn);
		vec3 irid = 0.5 + 0.5 * cos(6.2831853 * (rn * 1.6 + TIME * 0.2 + vec3(0.0, 0.33, 0.67)));
		acc = over(acc, mix(vec3(0.45, 0.8, 1.0), irid, 0.35), rim * 0.5 * bubble_amt);
		vec2 hp = (c - vec2(-0.42 * aspect, -0.3)) * vec2(1.0, 1.8);
		float spot = smoothstep(0.1, 0.02, length(hp));
		acc = over(acc, vec3(1.0), spot * 0.55 * bubble_amt);
	}

	// —— 氮气：边缘蓝光 ——
	if (boost_amt > 0.001) {
		acc = over(acc, boost_color, boost_amt * smoothstep(0.55, 1.05, rn) * 0.28);
	}

	// —— 速度线：从屏幕边缘指向中心的放射线，每秒随机刷新 24 次 ——
	if (speed_amt > 0.001) {
		float ang = atan(c.y, c.x) / 6.2831853 + 0.5;
		float cells = 150.0;
		float cell = floor(ang * cells);
		float fa = fract(ang * cells);
		float tick = floor(TIME * 24.0);
		float h1 = h11(cell * 1.37 + tick * 0.173);
		float h2 = h11(cell * 7.11 + tick * 0.311);
		float show = step(h1, 0.1 + 0.4 * speed_amt);
		float w = 0.2 + 0.4 * h2;
		float line = 1.0 - smoothstep(w * 0.45, w, abs(fa - 0.5) * 2.0);
		float start = mix(1.0, 0.6, speed_amt) - 0.15 * h2;
		float len_mask = smoothstep(start, start + 0.22, rn);
		vec3 lc = mix(vec3(1.0), boost_color * 1.1, boost_amt * 0.6);
		acc = over(acc, lc, line * len_mask * show * speed_amt * 0.55);
	}

	// —— 导弹锁定：脉动的红色边缘 ——
	if (lock_amt > 0.001) {
		float pulse = 0.55 + 0.45 * sin(TIME * 13.0);
		acc = over(acc, vec3(1.0, 0.08, 0.14), lock_amt * smoothstep(0.68, 1.1, rn) * (0.18 + 0.27 * pulse));
		float bd = min(min(UV.x, 1.0 - UV.x) * aspect, min(UV.y, 1.0 - UV.y));
		acc = over(acc, vec3(1.0, 0.2, 0.25), lock_amt * smoothstep(0.012, 0.004, bd) * (0.4 + 0.6 * pulse));
	}

	COLOR = vec4(acc.rgb / max(acc.a, 0.0001), acc.a);
}
