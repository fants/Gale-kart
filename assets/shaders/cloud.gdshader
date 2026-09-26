// 卡通乌云：底部深、顶部稍亮，带轮廓光；flash 为打闪电时的整体提亮。
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform vec3 top_color : source_color = vec3(0.47, 0.49, 0.62);
uniform vec3 bottom_color : source_color = vec3(0.14, 0.15, 0.22);
uniform float flash = 0.0;

void fragment() {
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float up = smoothstep(-0.55, 0.9, wn.y);
	vec3 col = mix(bottom_color, top_color, up);
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col += vec3(0.22, 0.24, 0.34) * fr;
	col += vec3(0.95, 0.95, 1.0) * flash * (0.55 + 0.45 * up);
	ALBEDO = col;
}
