// 漂移胎痕：深色半透明条带，边缘柔和，带轻微胎纹；按生成时刻淡出。
// UV.x = 生成时刻（秒，SkidMarks 的时钟），UV.y = 横向 0..1，UV2.x = 沿胎痕的累计距离（米）。
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 mark_color : source_color = vec4(0.07, 0.07, 0.09, 0.42);
uniform float now = 0.0;
uniform float fade_time = 8.0;

varying float v_fade;

void vertex() {
	float age = now - UV.x;
	float u = clamp(age / fade_time, 0.0, 1.0);
	v_fade = 1.0 - u * u;
	// 往相机方向挪一点，避免与路面深度冲突
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += normalize(CAMERA_POSITION_WORLD - wp) * 0.03;
}

void fragment() {
	float edge = smoothstep(0.0, 0.3, UV.y) * smoothstep(1.0, 0.7, UV.y);
	float tread = 0.82 + 0.18 * step(0.5, fract(UV2.x * 3.0));
	ALBEDO = mark_color.rgb;
	ALPHA = mark_color.a * v_fade * (0.3 + 0.7 * edge) * tread;
}
