shader_type canvas_item;
// 加载页背景：赛道主题色渐变 + 斜向滚动的糖果条纹 + 暗角。

uniform vec4 color_a : source_color = vec4(0.247, 0.624, 0.941, 1.0);
uniform vec4 color_b : source_color = vec4(0.812, 0.922, 1.0, 1.0);
uniform vec4 stripe_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float stripe_alpha = 0.12;
uniform float stripe_width = 90.0;
uniform float speed = 60.0;

void fragment() {
	vec3 col = mix(color_a.rgb, color_b.rgb, smoothstep(0.0, 1.0, UV.y * 0.8 + UV.x * 0.2));
	float s = (FRAGCOORD.x + FRAGCOORD.y + TIME * speed) / stripe_width;
	float f = sin(s * 3.14159);
	float aa = fwidth(f) * 1.5;
	col = mix(col, stripe_color.rgb, smoothstep(-aa, aa, f) * stripe_alpha);
	float vig = smoothstep(1.2, 0.35, length(UV - 0.5));
	col *= mix(0.82, 1.0, vig);
	COLOR = vec4(col, 1.0);
}
