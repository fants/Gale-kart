// 水柱底部的水洼：向外扩散的波纹圈 + 边缘泡沫，外圈淡出。
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 water : source_color = vec3(0.3, 0.62, 1.0);
uniform float fade = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ring = smoothstep(0.75, 1.0, sin(r * 22.0 - TIME * 7.0) * 0.5 + 0.5);
	float edge = smoothstep(0.62, 0.78, r) * smoothstep(1.0, 0.86, r);
	vec3 c = mix(water, vec3(0.9, 0.98, 1.0), ring * 0.6 + edge * 0.7);
	float a = (0.38 + ring * 0.25 + edge * 0.4) * smoothstep(1.0, 0.9, r);
	ALBEDO = c;
	ALPHA = clamp(a, 0.0, 1.0) * fade;
}
