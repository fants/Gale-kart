shader_type spatial;
// 车库展示圈：平放在车下的发光圆环 + 一圈随转台转动的光点，柔和的中心光晕。加色混合、不写深度。
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 ring_color : source_color = vec4(0.62, 0.9, 1.0, 1.0);
uniform vec4 dot_color : source_color = vec4(1.0, 0.86, 0.35, 1.0);
uniform float intensity = 1.5;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	// 主光环 + 外侧细光环
	float ring = exp(-pow((r - 0.86) / 0.022, 2.0)) + 0.45 * exp(-pow((r - 0.95) / 0.012, 2.0));
	// 光点：24 个，随节点旋转
	float seg = fract(a / 6.2831853 * 24.0);
	float dots = smoothstep(0.35, 0.0, abs(seg - 0.5) - 0.12) * exp(-pow((r - 0.78) / 0.018, 2.0));
	// 中心柔和光晕
	float glow = 0.18 * smoothstep(0.9, 0.0, r);
	vec3 col = ring_color.rgb * (ring + glow) + dot_color.rgb * dots * 0.9;
	float fade = smoothstep(1.0, 0.97, r);
	ALBEDO = col * intensity * fade;
	ALPHA = 1.0;
}
