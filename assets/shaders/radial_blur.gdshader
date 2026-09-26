// 读屏幕纹理的效果：氮气径向模糊（中心清晰、边缘拉丝）、水泡时的波动折射、乌云时镜头上的水珠折射。
// 只在需要时由 ScreenFx 显示本层（显示时会整屏拷贝一次屏幕）。
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float blur_amt = 0.0;
uniform float bubble_amt = 0.0;
uniform float rain_amt = 0.0;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float rn = length(c * vec2(aspect, 1.0)) / (0.5 * length(vec2(aspect, 1.0)));

	// 水泡：整屏轻微波动
	uv += bubble_amt * 0.008 * vec2(sin(uv.y * 16.0 + TIME * 3.0), cos(uv.x * 12.0 + TIME * 2.6)) * (0.35 + rn);

	// 镜头水珠：网格里随机出现、慢慢变淡的圆形水珠，把背后的画面放大折射
	float drop_mask = 0.0;
	if (rain_amt > 0.001) {
		vec2 g = vec2(uv.x * aspect, uv.y) * 7.0;
		vec2 cell = floor(g);
		vec2 f = fract(g) - 0.5;
		float h = h21(cell);
		vec2 off = (vec2(h21(cell + 3.1), h21(cell + 7.7)) - 0.5) * 0.5;
		float life = fract(TIME * (0.2 + h * 0.25) + h * 7.0);
		vec2 d = f - off;
		float rad = 0.1 + 0.14 * h;
		drop_mask = smoothstep(rad, rad * 0.75, length(d)) * step(0.4, h) * rain_amt * (1.0 - life);
		uv -= vec2(d.x / aspect, d.y) / 7.0 * drop_mask * 0.6;
	}

	vec3 col;
	if (blur_amt > 0.001) {
		// 采样点加逐像素抖动，避免出现一格一格的重影
		vec3 acc = vec3(0.0);
		float strength = blur_amt * 0.06 * smoothstep(0.12, 0.9, rn);
		float jitter = h21(FRAGCOORD.xy + fract(TIME) * 61.0);
		for (int i = 0; i < 12; i++) {
			float t = (float(i) + jitter) / 12.0;
			acc += textureLod(screen_tex, uv - c * strength * t, 0.0).rgb;
		}
		col = acc / 12.0;
	} else {
		col = textureLod(screen_tex, uv, 0.0).rgb;
	}
	col += vec3(0.12, 0.14, 0.18) * drop_mask;
	COLOR = vec4(col, 1.0);
}
