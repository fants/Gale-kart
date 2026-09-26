// 金字塔：世界空间分层的砂岩石块（错缝），塔尖一段金色包顶（自发光）。UV.y = 本地高度 0..1。
shader_type spatial;
render_mode diffuse_burley;
#include "res://assets/shaders/noise.gdshaderinc"

uniform vec3 stone_a : source_color = vec3(0.93, 0.76, 0.48);
uniform vec3 stone_b : source_color = vec3(0.84, 0.64, 0.38);
uniform vec3 gold : source_color = vec3(1.0, 0.82, 0.3);
uniform float course_h = 2.4;
uniform float block_w = 4.5;
uniform float cap = 0.9;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float row = floor(wpos.y / course_h);
	float along = (abs(wpos.x) > abs(wpos.z) ? wpos.z : wpos.x) / block_w + row * 0.5;
	vec2 cell = vec2(floor(along), row);
	float fy = fract(wpos.y / course_h);
	float fx = fract(along);
	float mortar = max(smoothstep(0.1, 0.0, fy), smoothstep(0.04, 0.0, min(fx, 1.0 - fx)) * 0.7);
	float tone = hash12(cell);
	vec3 col = mix(stone_a, stone_b, tone * 0.7 + vnoise(wpos.xz * 0.3) * 0.3);
	col *= 1.0 - mortar * 0.3;
	float g = smoothstep(cap - 0.01, cap + 0.01, UV.y);
	ALBEDO = mix(col, gold, g);
	ROUGHNESS = mix(0.95, 0.3, g);
	METALLIC = g * 0.6;
	EMISSION = gold * g * 0.6;
}
