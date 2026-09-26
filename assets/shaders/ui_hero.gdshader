shader_type canvas_item;
// 首页大图：铺满裁切 + 缓慢推近平移（Ken Burns）+ 右侧斜向流动的速度光线 + 左侧淡淡提亮（放 Logo 和按钮）。

uniform sampler2D art : source_color, filter_linear_mipmap;
uniform float art_aspect = 1.7778;
uniform float wash = 0.22;
uniform float streaks = 0.18;

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 tuv = UV - 0.5;
	if (aspect > art_aspect) {
		tuv.y *= art_aspect / aspect;
	} else {
		tuv.x *= aspect / art_aspect;
	}
	// 推近 4% 左右并向右下缓慢漂移，循环往复
	float z = 1.05 + 0.035 * sin(TIME * 0.12);
	tuv = tuv / z + vec2(0.012 * sin(TIME * 0.09), 0.008 * cos(TIME * 0.07));
	vec3 col = texture(art, tuv + 0.5).rgb;
	// 速度光线：从右上往左下流动的细长亮线，只在画面右半边
	vec2 p = UV * vec2(aspect, 1.0);
	float d = p.x * 0.34 + p.y;
	float lane = fract(d * 9.0);
	float id = floor(d * 9.0);
	float h = fract(sin(id * 91.7) * 4375.5);
	float along = fract(p.x * 0.6 - p.y * 0.2 + TIME * (0.35 + h * 0.4) + h);
	float streak = smoothstep(0.035, 0.0, abs(lane - 0.5) - 0.012) * smoothstep(0.0, 0.25, along) * smoothstep(0.55, 0.25, along);
	streak *= step(0.6, h) * smoothstep(0.45, 0.8, UV.x);
	col += vec3(1.0) * streak * streaks;
	// 左侧提亮 + 四周轻微暗角
	col = mix(col, vec3(1.0, 0.99, 0.96), wash * smoothstep(0.5, 0.0, UV.x));
	float vig = smoothstep(1.3, 0.5, length((UV - 0.5) * vec2(1.2, 1.0)));
	col *= mix(0.88, 1.0, vig);
	COLOR = vec4(col, 1.0);
}
