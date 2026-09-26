// 光束：mode 0 为飞碟的锥形光（UV.y 0 顶 → 1 底，向下移动的光环）；mode 1 为磁铁吸引线（流向车头的虚线）。
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.72, 0.55, 1.0);
uniform float energy = 1.0;
uniform int mode = 0;
uniform float length_m = 10.0;
uniform float flow = 1.0;

void fragment() {
	float nv = abs(dot(NORMAL, VIEW));
	float a;
	if (mode == 0) {
		float edge = pow(1.0 - nv, 1.4);
		float rings = 0.6 + 0.4 * smoothstep(0.35, 0.8, abs(fract(UV.y * 5.0 - TIME * 1.8) - 0.5) * 2.0);
		a = (0.1 + edge * 0.6) * rings * smoothstep(0.0, 0.06, UV.y) * (0.55 + 0.45 * UV.y);
	} else {
		float dash = smoothstep(0.35, 0.5, fract(UV.y * length_m * 0.9 + TIME * 5.0 * flow));
		a = (0.25 + 0.75 * dash) * (0.35 + 0.65 * nv);
	}
	ALBEDO = color * energy;
	ALPHA = clamp(a, 0.0, 1.0);
}
