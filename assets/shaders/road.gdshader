// 路面：沥青噪点、边线、虚线中线、起终点格子、发车格白线。
// UV.x：横向 0（左边缘）..1（右边缘）；UV.y：沿赛道累计米数。
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://assets/shaders/noise.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.37, 0.4, 0.45);
uniform vec3 speck_color : source_color = vec3(0.44, 0.46, 0.52);
uniform vec3 line_color : source_color = vec3(1.0);
uniform vec3 center_color : source_color = vec3(1.0, 0.85, 0.29);
uniform float half_width = 10.0;
uniform float track_length = 1000.0;
uniform float line_glow = 0.0;
uniform float wet = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float lat = (UV.x - 0.5) * 2.0 * half_width;  // 米，右正
	float along = UV.y;                            // 米
	float n = fbm(wpos.xz * 1.7);
	float fine = hash12(floor(wpos.xz * 22.0));
	vec3 col = mix(base_color, speck_color, smoothstep(0.55, 0.9, n) * 0.8);
	col *= 0.93 + 0.1 * fine;
	// 赛车线上轮胎磨出的暗痕
	float wear = smoothstep(0.6, 0.0, abs(abs(lat) - half_width * 0.35)) * 0.06;
	col *= 1.0 - wear;
	float emit = 0.0;
	// 边线（距边缘 0.35 m，宽 0.25 m）
	float edge = abs(abs(lat) - (half_width - 0.45));
	float edge_line = 1.0 - smoothstep(0.1, 0.14, edge);
	col = mix(col, line_color, edge_line);
	emit += edge_line;
	// 中线虚线：每 7 m 画 3.5 m
	float dash = step(fract(along / 7.0), 0.5);
	float center = (1.0 - smoothstep(0.1, 0.14, abs(lat))) * dash;
	col = mix(col, center_color, center);
	emit += center;
	// 起终点格子：0 m 前后 1.4 m
	float d0 = min(along, track_length - along);
	if (d0 < 1.4 || abs(along - track_length) < 1.4) {
		vec2 cell = floor(vec2(lat / 1.0, along / 0.7));
		float chk = mod(cell.x + cell.y, 2.0);
		col = mix(vec3(0.08), vec3(0.97), chk);
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.82, 0.25, wet);
	SPECULAR = 0.35;
	EMISSION = (edge_line * line_color + center * center_color) * line_glow;
}
