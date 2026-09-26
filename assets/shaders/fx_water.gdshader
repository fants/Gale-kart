// 水柱：上涌的水流纹理 + 菲涅尔亮边 + 竖向高光条 + 底部泡沫，表面鼓包向上传播。
// inner = 1 画内壁（配合 next_pass 画外壁），cap = 1 为顶部水冠。柱体网格高 7 m、中心在原点。
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;

uniform vec3 deep : source_color = vec3(0.1, 0.42, 0.95);
uniform vec3 light : source_color = vec3(0.68, 0.92, 1.0);
uniform float inner = 0.0;
uniform float cap = 0.0;
uniform float fade = 1.0;
uniform float height = 7.0;

varying vec3 v_obj;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_obj = VERTEX;
	float ang = atan(VERTEX.z, VERTEX.x);
	float w = sin(VERTEX.y * 1.6 - TIME * 6.0 + ang * 2.0) * 0.045 + sin(TIME * 3.7 + ang * 5.0 + VERTEX.y) * 0.02;
	if (cap > 0.5) {
		w = sin(ang * 6.0 + TIME * 5.0) * 0.04 + sin(VERTEX.y * 5.0 - TIME * 7.0) * 0.03;
	}
	VERTEX.xz *= 1.0 + w;
	if (inner > 0.5) {
		VERTEX.xz *= 0.97;
	}
}

void fragment() {
	float ang = atan(v_obj.z, v_obj.x);
	float nv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float fr = pow(1.0 - nv, 2.0);
	// 竖向拉长的平滑噪声 = 上涌的水流
	float flow = vnoise(vec2(ang * 5.0, v_obj.y * 0.45 - TIME * 2.2)) * 0.6 + vnoise(vec2(ang * 11.0 + 3.0, v_obj.y * 0.9 - TIME * 3.6)) * 0.4;
	float streak = smoothstep(0.55, 0.85, flow);
	// 视空间里固定方向的竖向高光（像光滑的水面反光）
	float spec = smoothstep(0.62, 0.86, dot(NORMAL, normalize(vec3(-0.75, 0.2, 0.62))));
	vec3 c = mix(deep, light, clamp(0.22 + fr * 0.7 + streak * 0.35, 0.0, 1.0));
	c = mix(c, vec3(1.0), spec * 0.5 + streak * 0.12);
	float a = 0.4 + fr * 0.45 + streak * 0.1 + spec * 0.3;
	if (cap > 0.5) {
		// 半球底面在柱子里面，看不到也不画
		if (v_obj.y < 0.02) {
			discard;
		}
		// 顶部水冠：翻滚的泡沫（用水平位置取噪声，避免顶点处出现放射纹）
		float foam = smoothstep(0.48, 0.72, vnoise(v_obj.xz * 1.3 + vec2(TIME * 0.8, -TIME * 0.6)) * 0.6 + vnoise(v_obj.xz * 3.1 - vec2(0.0, TIME * 1.5)) * 0.4);
		c = mix(c, vec3(1.0), foam * 0.85);
		a += foam * 0.35;
	} else {
		// 底部一圈白色泡沫
		float y01 = (v_obj.y + height * 0.5) / height;
		float edge = 0.1 + (vnoise(vec2(ang * 9.0, TIME * 2.5)) - 0.5) * 0.08;
		float foam = smoothstep(edge, edge - 0.06, y01);
		c = mix(c, vec3(1.0), foam * 0.85);
		a += foam * 0.4;
	}
	if (inner > 0.5) {
		c *= 0.7;
		a *= 0.5;
	}
	ALBEDO = c;
	ALPHA = clamp(a, 0.0, 1.0) * fade;
}
