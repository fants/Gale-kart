// 圆形软阴影（道具箱、香蕉等悬浮物下方），INSTANCE_CUSTOM.x 为强度。
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 shadow_color : source_color = vec3(0.08, 0.09, 0.16);
uniform float strength = 0.38;

varying float v_k;

void vertex() {
	v_k = INSTANCE_CUSTOM.x;
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	ALBEDO = shadow_color;
	ALPHA = (1.0 - smoothstep(0.15, 1.0, r)) * strength * v_k;
}
