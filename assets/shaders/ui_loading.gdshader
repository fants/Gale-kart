shader_type canvas_item;
// 加载页背景：赛道主题色渐变 + 斜向滚动的糖果条纹 + 暗角。
// use_art：底图换成赛道插画（铺满裁切 + 缓慢推近），罩一层淡白，条纹减弱。

uniform vec4 color_a : source_color = vec4(0.247, 0.624, 0.941, 1.0);
uniform vec4 color_b : source_color = vec4(0.812, 0.922, 1.0, 1.0);
uniform vec4 stripe_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float stripe_alpha = 0.12;
uniform float stripe_width = 90.0;
uniform float speed = 60.0;
uniform bool use_art = false;
uniform sampler2D art : source_color, filter_linear_mipmap;
uniform float art_aspect = 1.7778;
uniform float art_wash = 0.3;

void fragment() {
	vec3 col = mix(color_a.rgb, color_b.rgb, smoothstep(0.0, 1.0, UV.y * 0.8 + UV.x * 0.2));
	float sk = 1.0;
	if (use_art) {
		float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
		vec2 tuv = UV - 0.5;
		if (aspect > art_aspect) {
			tuv.y *= art_aspect / aspect;
		} else {
			tuv.x *= aspect / art_aspect;
		}
		tuv /= 1.06 + 0.04 * sin(TIME * 0.15);
		col = mix(texture(art, tuv + 0.5).rgb, color_b.rgb, art_wash);
		sk = 0.5;
	}
	float s = (FRAGCOORD.x + FRAGCOORD.y + TIME * speed) / stripe_width;
	float f = sin(s * 3.14159);
	float aa = fwidth(f) * 1.5;
	col = mix(col, stripe_color.rgb, smoothstep(-aa, aa, f) * stripe_alpha * sk);
	float vig = smoothstep(1.2, 0.35, length(UV - 0.5));
	col *= mix(0.82, 1.0, vig);
	COLOR = vec4(col, 1.0);
}
