// 天气粒子（绘制）：朝向相机的小面片。shape: 0 柔和圆点 1 树叶（自转、翻飞）2 大团烟尘 3 发光点。
// use_custom_size 时尺寸取 INSTANCE_CUSTOM.y（天气粒子），否则取粒子变换的缩放（水雾等内置粒子材质）。
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform int shape = 0;
uniform bool use_custom_size = true;
uniform float glow = 1.0;
uniform float near_fade = 1.5;

varying vec4 pcol;
varying float fade;

void vertex() {
	float size = use_custom_size ? INSTANCE_CUSTOM.y : length(MODEL_MATRIX[0].xyz);
	vec2 q = VERTEX.xy * size;
	if (shape == 1) {
		// 树叶：面内自转 + 宽度随翻转变化
		float a = TIME * INSTANCE_CUSTOM.z + INSTANCE_CUSTOM.x * 6.2832;
		q.x *= 0.55 + 0.45 * abs(sin(TIME * 2.1 + INSTANCE_CUSTOM.x * 9.0));
		q = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * q;
	}
	vec3 wp = MODEL_MATRIX[3].xyz;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = wp + right * q.x + up * q.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	pcol = COLOR;
	// 离相机太近的淡出，免得糊在镜头上
	float d = distance(wp, INV_VIEW_MATRIX[3].xyz);
	fade = smoothstep(near_fade * 0.4, near_fade, d);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float a;
	if (shape == 1) {
		// 叶形：两端尖的椭圆 + 叶脉
		float w = 1.0 - uv.y * uv.y;
		a = smoothstep(0.02, -0.08, abs(uv.x) - w * 0.55);
		a *= 1.0 - smoothstep(0.0, 0.08, abs(uv.x)) * 0.25;
	} else if (shape == 2) {
		a = pow(max(1.0 - dot(uv, uv), 0.0), 1.6);
	} else {
		a = smoothstep(1.0, 0.25, length(uv));
	}
	vec3 c = pcol.rgb;
	if (shape == 3) {
		c *= glow;
	}
	ALBEDO = c;
	ALPHA = a * pcol.a * fade;
}
