// 特效粒子的绘制（fx_sprite_mix / fx_sprite_add 共用）：四边形按模式摆放，形状在片元里用距离场画出。
// 粒子数据约定见 fx_particles.gdshader。
// 形状：0 柔光点 1 烟团 2 星星 3 火花 4 圆环 5 水滴 6 碎片 7 彩带 8 十字闪光
//       9 火球 10 电弧 11 光柱 12 风线 13 碎屑 14 花瓣 15 雪花

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// 软粒子：与场景表面相交处的淡出距离（米）
uniform float soft_dist = 0.5;

varying vec4 v_col;
varying flat int v_shape;
varying float v_age;
varying float v_rnd;
varying float v_rot;
varying float v_shade;

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	int code = int(cd.x + 0.5);
	int mode = code / 16;
	v_shape = code - mode * 16;
	v_age = cd.y;
	v_rnd = cd.w;
	v_rot = cd.z;
	v_col = COLOR;
	v_shade = 1.0;
	vec3 pos = MODEL_MATRIX[3].xyz;
	vec3 ax = MODEL_MATRIX[0].xyz;
	vec3 ay = MODEL_MATRIX[1].xyz;
	vec3 az = MODEL_MATRIX[2].xyz;
	vec3 cam_r = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_u = INV_VIEW_MATRIX[1].xyz;
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - pos);
	if (mode == 0) {
		float s = length(ax);
		float c = cos(cd.z);
		float sn = sin(cd.z);
		ax = (cam_r * c + cam_u * sn) * s;
		ay = (-cam_r * sn + cam_u * c) * s;
		az = to_cam;
	} else if (mode == 1) {
		// 头部在粒子位置，尾巴拖在后面
		float w = length(ax);
		vec3 side = cross(ay, to_cam);
		float sl = length(side);
		side = sl > 0.00001 ? side / sl : cam_r;
		pos -= ay * 0.5;
		ax = side * w;
		az = to_cam;
	} else if (mode == 2) {
		vec3 n = normalize(cross(ax, ay));
		v_shade = 0.6 + 0.55 * abs(dot(n, normalize(vec3(0.3, 0.9, 0.25))));
	} else if (mode == 4) {
		// 竖直光柱：底部在粒子位置，绕 Y 轴朝向相机
		float w = length(ax);
		vec3 side = cross(vec3(0.0, 1.0, 0.0), to_cam);
		float sl = length(side);
		side = sl > 0.00001 ? side / sl : cam_r;
		pos += ay * 0.5;
		ax = side * w;
		az = to_cam;
	}
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(ax, 0.0), vec4(ay, 0.0), vec4(az, 0.0), vec4(pos, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

float fx_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float fx_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(fx_hash(i), fx_hash(i + vec2(1.0, 0.0)), f.x), mix(fx_hash(i + vec2(0.0, 1.0)), fx_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// 五角星距离场（Inigo Quilez）
float sd_star5(vec2 p, float r, float rf) {
	const vec2 k1 = vec2(0.809016994375, -0.587785252292);
	const vec2 k2 = vec2(-k1.x, k1.y);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	p.y -= r;
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
	float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
	return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// t：沿长轴 0 尾 → 1 头（拉伸 / 光柱模式）
	float t = 1.0 - UV.y;
	float r = length(p);
	vec3 col = v_col.rgb;
	float a = 0.0;
	bool soft = false;
	if (v_shape == 0) {
		a = smoothstep(1.0, 0.0, r);
		a *= a;
		soft = true;
	} else if (v_shape == 1) {
		// 烟团：噪声边缘 + 顶部受光
		float n = fx_noise(p * 2.3 + v_rnd * 37.0) * 0.6 + fx_noise(p * 5.1 - v_rnd * 13.0) * 0.4;
		float edge = 0.86 + (n - 0.5) * 0.42;
		a = smoothstep(edge, edge - 0.45, r);
		float up = p.x * sin(v_rot) - p.y * cos(v_rot);
		col *= 0.84 + 0.2 * up + 0.12 * n;
		soft = true;
	} else if (v_shape == 2) {
		float d = sd_star5(vec2(p.x, -p.y), 0.9, 0.45);
		a = smoothstep(0.05, -0.02, d);
		// 描边 + 中心高光
		float rim = smoothstep(-0.16, -0.08, d);
		col = mix(col * 1.25 + vec3(0.25), col * 0.55, rim);
	} else if (v_shape == 3) {
		// 火花：头部粗亮、尾部变细，中心偏白
		float across = abs(p.x) / mix(0.3, 1.0, t);
		a = smoothstep(1.0, 0.45, across) * (0.25 + 0.75 * t);
		col = mix(col, vec3(max(col.r, max(col.g, col.b))) * vec3(1.0, 0.98, 0.9), (1.0 - smoothstep(0.0, 0.5, across)) * 0.55);
	} else if (v_shape == 4) {
		// 冲击环：内侧白、外侧彩色，越扩越细
		float w = mix(0.24, 0.05, v_age);
		float d = r - 0.8;
		a = smoothstep(w, w * 0.35, abs(d)) + 0.14 * smoothstep(0.8, 0.2, r) * (1.0 - v_age);
		col = mix(col, vec3(max(1.0, max(col.r, max(col.g, col.b)))), smoothstep(w * 0.2, -w, d) * 0.85);
		soft = true;
	} else if (v_shape == 5) {
		a = smoothstep(1.0, 0.72, r);
		col = mix(col, vec3(1.0), smoothstep(0.45, 0.0, length(p - vec2(-0.3, -0.35))) * 0.8);
		col *= 0.85 + 0.15 * (1.0 - p.y);
	} else if (v_shape == 6) {
		// 三角碎片（彩虹玻璃）
		vec2 q = vec2(abs(p.x), p.y);
		float d = max(q.x * 0.866 + p.y * 0.5, -p.y) - 0.5;
		a = smoothstep(0.04, 0.0, d);
		col = col * v_shade + vec3(0.35) * smoothstep(-0.12, 0.0, d);
	} else if (v_shape == 7) {
		a = step(abs(p.x), 0.92) * step(abs(p.y), 0.42);
		col *= v_shade;
	} else if (v_shape == 8) {
		float core = smoothstep(0.55, 0.0, r);
		float rays = max(1.0 - abs(p.x) * 9.0, 0.0) * (1.0 - abs(p.y)) + max(1.0 - abs(p.y) * 9.0, 0.0) * (1.0 - abs(p.x));
		a = clamp(core * core + rays, 0.0, 1.0);
	} else if (v_shape == 9) {
		// 火球：翻滚的噪声边缘，中心更亮更白
		float n = fx_noise(p * 2.6 + v_rnd * 23.0 + vec2(0.0, v_age * 2.0)) * 0.65 + fx_noise(p * 6.0 - v_rnd * 7.0) * 0.35;
		float edge = 0.9 + (n - 0.5) * 0.5;
		a = smoothstep(edge, edge - 0.5, r);
		// 边缘偏暗红、中心黄亮，卡通火团更有层次
		col *= mix(0.55, 1.0, smoothstep(edge, edge - 0.35, r));
		col = mix(col, vec3(1.0, 0.85, 0.4) * 1.5, smoothstep(0.55, 0.0, r) * (1.0 - v_age) * n);
		soft = true;
	} else if (v_shape == 10) {
		// 电弧：锯齿线
		float z = fract(t * 5.0 + v_rnd * 9.0);
		float off = (abs(z - 0.5) * 2.0 - 0.5) * 0.7 + (fx_hash(vec2(floor(t * 5.0 + v_rnd * 9.0), v_rnd)) - 0.5) * 0.5;
		float d = abs(p.x - off);
		a = smoothstep(0.22, 0.0, d) + smoothstep(0.8, 0.0, d) * 0.35;
		a *= smoothstep(0.0, 0.08, t) * smoothstep(1.0, 0.92, t);
		col = mix(col, vec3(1.0) * 2.0, smoothstep(0.1, 0.0, d));
	} else if (v_shape == 11) {
		// 光柱：中心亮、两侧柔，向上流动的亮纹，顶端淡出
		float across = 1.0 - abs(p.x);
		float flow = 0.75 + 0.25 * sin(t * 18.0 - TIME * 14.0 + v_rnd * 6.0);
		a = pow(across, 1.6) * flow * smoothstep(1.0, 0.55, t) * smoothstep(0.0, 0.04, t);
		col = mix(col, vec3(1.0) * 1.6, pow(across, 6.0));
	} else if (v_shape == 12) {
		a = (1.0 - smoothstep(0.2, 1.0, abs(p.x))) * sin(clamp(t, 0.0, 1.0) * 3.14159);
	} else if (v_shape == 13) {
		// 不规则碎屑
		float ang = atan(p.y, p.x);
		float rr = 0.72 + 0.2 * sin(ang * 3.0 + v_rnd * 20.0) + 0.1 * sin(ang * 5.0 - v_rnd * 9.0);
		a = smoothstep(rr + 0.04, rr - 0.02, r);
		col *= v_shade * (0.9 + 0.2 * (1.0 - r));
	} else if (v_shape == 14) {
		// 花瓣 / 果皮：弯月形
		float d1 = length(p * vec2(1.0, 2.1));
		float d2 = length((p - vec2(0.0, 0.28)) * vec2(1.1, 2.3));
		a = smoothstep(1.0, 0.94, d1) * smoothstep(0.9, 0.96, d2);
		col *= v_shade;
	} else {
		// 雪花 / 六芒亮片
		float ang = atan(p.y, p.x);
		float arms = pow(abs(cos(ang * 3.0)), 14.0);
		a = max(smoothstep(0.32, 0.0, r), arms * smoothstep(1.0, 0.15, r));
	}
	if (soft) {
		float depth = texture(depth_tex, SCREEN_UV).r;
		vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		vp.xyz /= vp.w;
		a *= clamp((VERTEX.z - vp.z) / soft_dist, 0.0, 1.0);
	}
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0) * v_col.a;
}
