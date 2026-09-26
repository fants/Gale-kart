// 天气粒子（处理着色器）：粒子常驻在以相机为中心的盒子里，越界后取模绕回，相机跑多快周围都有粒子。
// mode: 0 飘雪 1 落叶 2 沙尘 3 萤火虫。CUSTOM.x = 随机相位，CUSTOM.y = 尺寸，CUSTOM.z = 旋转速度。
shader_type particles;

uniform int mode = 0;
uniform vec3 box_size = vec3(100.0, 50.0, 100.0);
uniform vec3 center = vec3(0.0);
uniform vec3 wind = vec3(0.6, 0.0, 0.2);
uniform float fall_speed = 2.2;
uniform float size_min = 0.08;
uniform float size_max = 0.18;
uniform vec4 color_a : source_color = vec4(1.0);
uniform vec4 color_b : source_color = vec4(1.0);

float rnd(uint n) {
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 0x7fffffffu) / float(0x7fffffff);
}

void start() {
	uint s = NUMBER * 7919u + RANDOM_SEED;
	vec3 r = vec3(rnd(s), rnd(s + 1u), rnd(s + 2u));
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xyz = center + (r - 0.5) * box_size;
	CUSTOM.x = rnd(s + 3u);
	CUSTOM.y = mix(size_min, size_max, rnd(s + 4u));
	CUSTOM.z = (rnd(s + 5u) - 0.5) * 6.0;
	COLOR = mix(color_a, color_b, rnd(s + 6u));
	VELOCITY = vec3(0.0);
}

void process() {
	vec3 p = TRANSFORM[3].xyz;
	float ph = CUSTOM.x * 6.2832;
	vec3 v = vec3(0.0);
	if (mode == 0) {
		v = vec3(sin(TIME * 1.3 + ph) * 0.7, -fall_speed * (0.7 + 0.6 * CUSTOM.x), cos(TIME * 1.1 + ph * 1.7) * 0.7) + wind;
	} else if (mode == 1) {
		// 落叶：左右摇摆着慢慢飘落
		v = vec3(sin(TIME * 1.7 + ph) * 1.6, -fall_speed * (0.6 + 0.5 * CUSTOM.x) + sin(TIME * 2.3 + ph) * 0.5, cos(TIME * 1.3 + ph) * 1.2) + wind;
	} else if (mode == 2) {
		// 沙尘：贴地顺风飘移，轻微起伏
		v = wind * (0.7 + 0.6 * CUSTOM.x) + vec3(0.0, sin(TIME * 0.7 + ph) * 0.35, 0.0);
	} else {
		// 萤火虫：缓慢游走 + 明灭
		v = vec3(sin(TIME * 0.6 + ph) + sin(TIME * 1.7 + ph * 3.1) * 0.5, sin(TIME * 0.9 + ph * 2.0) * 0.5, cos(TIME * 0.5 + ph) + cos(TIME * 1.3 + ph * 2.3) * 0.5) * 0.9;
		float blink = smoothstep(0.2, 0.9, sin(TIME * (1.1 + CUSTOM.x) + ph * 5.0) * 0.5 + 0.5);
		COLOR.a = mix(0.15, 1.0, blink);
	}
	p += v * DELTA;
	vec3 rel = p - center + box_size * 0.5;
	rel = mod(rel, box_size);
	TRANSFORM[3].xyz = center + rel - box_size * 0.5;
}
