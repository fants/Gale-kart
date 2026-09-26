// 夜城楼宇：City Kit 贴图集里玻璃色块（UV 0.625..0.75 × 0.25..0.5）当作窗户。
// 按世界坐标把立面切成窗格，随机点亮（暖黄 / 冷白 / 粉紫混合，自发光可被辉光放大），未点亮的是反光的深色玻璃。
shader_type spatial;
render_mode diffuse_burley;
#include "res://assets/shaders/noise.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 glass_rect = vec4(0.625, 0.25, 0.75, 0.5);
uniform float lit_ratio = 0.5;
uniform float intensity = 2.4;
uniform vec3 warm : source_color = vec3(1.0, 0.8, 0.48);
uniform vec3 cool : source_color = vec3(0.6, 0.85, 1.0);
uniform vec3 pink : source_color = vec3(1.0, 0.55, 0.9);
uniform vec2 cell_size = vec2(3.0, 3.4);
uniform float wall_dim = 0.8;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	bool glass = UV.x > glass_rect.x && UV.x < glass_rect.z && UV.y > glass_rect.y && UV.y < glass_rect.w;
	if (glass) {
		vec3 an = abs(wnrm);
		bool xface = an.x > an.z;
		vec2 f = xface ? vec2(wpos.z, wpos.y) : vec2(wpos.x, wpos.y);
		vec2 cell = floor(f / cell_size);
		// 同一立面平面上的窗格共享随机数；不同立面（按法线与所在平面位置）错开
		float plane = xface ? floor(wpos.x * 0.5) + sign(wnrm.x) * 91.0 : floor(wpos.z * 0.5) + sign(wnrm.z) * 57.0;
		float h = hash12(cell + vec2(plane * 13.1, plane * 7.7));
		float on = step(1.0 - lit_ratio, h);
		float h2 = hash12(cell * 1.37 + vec2(plane, 3.1));
		vec3 lc = h2 < 0.55 ? warm : (h2 < 0.85 ? cool : pink);
		float bright = 0.55 + 0.45 * hash12(cell + vec2(9.0, plane));
		ALBEDO = c * 0.12;
		EMISSION = lc * on * intensity * bright;
		ROUGHNESS = 0.12;
		METALLIC = 0.5;
	} else {
		ALBEDO = c * wall_dim;
		ROUGHNESS = 0.85;
	}
}
