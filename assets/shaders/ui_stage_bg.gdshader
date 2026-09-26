shader_type canvas_item;
// 菜单 3D 舞台的画布背景：竖向渐变 + 围绕主体缓慢旋转的光芒 + 中心柔光 + 波点 + 暗角。
// use_art：底图换成插画（按屏幕比例铺满裁切），再罩一层淡淡的白让前景 UI 更清楚，光芒保留但减弱。

uniform vec4 top_color : source_color = vec4(0.498, 0.839, 1.0, 1.0);
uniform vec4 bottom_color : source_color = vec4(1.0, 0.890, 0.945, 1.0);
uniform vec4 ray_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float ray_alpha = 0.16;
uniform vec2 center = vec2(0.65, 0.55);
uniform float aspect = 1.7778;
uniform float rays = 12.0;
uniform float speed = 0.04;
uniform float glow = 0.28;
uniform float dots = 0.07;
uniform float dot_spacing = 30.0;
uniform bool use_art = false;
uniform sampler2D art : source_color, filter_linear_mipmap;
uniform float art_aspect = 1.7778;
uniform float art_wash = 0.18;

void fragment() {
	vec2 uv = UV;
	vec3 col = mix(top_color.rgb, bottom_color.rgb, smoothstep(0.0, 1.0, uv.y));
	float ray_k = 1.0;
	if (use_art) {
		vec2 tuv = uv - 0.5;
		if (aspect > art_aspect) {
			tuv.y *= art_aspect / aspect;
		} else {
			tuv.x *= aspect / art_aspect;
		}
		col = texture(art, tuv + 0.5).rgb;
		// 左侧（菜单按钮区）多罩一点白
		float wash = art_wash + 0.2 * smoothstep(0.55, 0.0, uv.x);
		col = mix(col, vec3(1.0, 0.99, 0.97), wash);
		ray_k = 0.45;
	}
	vec2 d = (uv - center) * vec2(aspect, 1.0);
	float r = length(d);
	float ang = atan(d.y, d.x) + TIME * speed;
	float s = sin(ang * rays);
	float aa = fwidth(s) * 1.5;
	float ray = smoothstep(-aa, aa, s);
	float fade = smoothstep(1.6, 0.15, r);
	col = mix(col, ray_color.rgb, ray * ray_alpha * fade * ray_k);
	col += vec3(1.0) * glow * ray_k * smoothstep(0.7, 0.0, r);
	vec2 cell = fract(FRAGCOORD.xy / dot_spacing) - 0.5;
	float dm = 1.0 - smoothstep(0.13, 0.17, length(cell));
	col = mix(col, vec3(1.0), dm * dots * ray_k * smoothstep(0.35, 1.0, uv.y));
	float vig = smoothstep(1.25, 0.45, length((uv - 0.5) * vec2(aspect * 0.6, 1.0)));
	col *= mix(0.9, 1.0, vig);
	COLOR = vec4(min(col, vec3(1.0)), 1.0);
}
