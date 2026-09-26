// 河流 / 水潭水面：两层顺流滚动的噪声扰动法线，深浅按场景深度混色，浅处与岸边起泡沫，顺流白色水纹。
// flow_dir 为世界 XZ 上的流向；UV 不用，全部按世界坐标计算。
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://assets/shaders/noise.gdshaderinc"

uniform vec3 deep_color : source_color = vec3(0.07, 0.42, 0.45);
uniform vec3 shallow_color : source_color = vec3(0.3, 0.78, 0.72);
uniform vec3 foam_color : source_color = vec3(0.92, 0.98, 1.0);
uniform vec2 flow_dir = vec2(0.0, -1.0);
uniform float flow_speed = 1.6;
uniform float depth_range = 2.2;
uniform float edge_foam = 0.55;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

varying vec3 wpos;

float h2(vec2 p, float t) {
	vec2 f = flow_dir * t;
	return vnoise(p * 0.35 - f * 0.35) * 0.6 + vnoise(p * 0.9 - f * 0.8 + 7.3) * 0.4;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * flow_speed;
	vec2 p = wpos.xz;
	// 由高度噪声求法线
	float e = 0.25;
	float c0 = h2(p, t);
	float cx = h2(p + vec2(e, 0.0), t);
	float cz = h2(p + vec2(0.0, e), t);
	vec3 n_world = normalize(vec3((c0 - cx) * 1.6, 1.0, (c0 - cz) * 1.6));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// 场景深度 → 水深
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	vec4 vp = INV_PROJECTION_MATRIX * ndc;
	vp.xyz /= vp.w;
	float depth = clamp(VERTEX.z - vp.z, 0.0, 50.0);
	float k = smoothstep(0.0, depth_range, depth);
	vec3 col = mix(shallow_color, deep_color, k);

	// 顺流水纹：沿流向拉长的噪声
	vec2 across = vec2(-flow_dir.y, flow_dir.x);
	vec2 q = vec2(dot(p, across) * 0.9, dot(p, flow_dir) * 0.18 - t * 0.9);
	float streak = smoothstep(0.62, 0.8, vnoise(q * 2.0) * 0.7 + vnoise(q * 5.0) * 0.3);
	float foam = streak * 0.55;
	// 岸边泡沫
	foam = max(foam, (1.0 - smoothstep(0.0, edge_foam, depth)) * (0.6 + 0.4 * vnoise(p * 2.5 + t)));
	col = mix(col, foam_color, clamp(foam, 0.0, 1.0));

	ALBEDO = col;
	ROUGHNESS = mix(0.06, 0.4, foam);
	SPECULAR = 0.6;
	ALPHA = clamp(mix(0.72, 0.95, k) + foam * 0.3, 0.0, 1.0) * smoothstep(0.0, 0.12, depth);
}
