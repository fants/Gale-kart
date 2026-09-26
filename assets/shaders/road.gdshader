// 路面：沥青噪点、边线、虚线中线、起终点格子、发车格白线。
// 土路赛道（unpaved）：顶点色 r/g/b 为土路 / 草路 / 泥泞的权重，画车辙、碎石、草皮、水坑，边缘不规则地过渡到草地。
// UV.x：横向 0（左边缘）..1（右边缘）；UV.y：沿赛道累计米数；UV2.x：该处路面半宽（路宽逐点变化）。
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
uniform bool unpaved = false;
// 起终点格子（支路不画）
uniform bool checker = true;
// 土路：网格比路面每侧宽 verge 米，外侧过渡到路边草
uniform float verge = 1.6;
uniform vec3 dirt_a : source_color = vec3(0.65, 0.49, 0.33);
uniform vec3 dirt_b : source_color = vec3(0.54, 0.39, 0.26);
uniform vec3 grass_a : source_color = vec3(0.49, 0.70, 0.30);
uniform vec3 grass_b : source_color = vec3(0.37, 0.60, 0.23);
uniform vec3 mud_a : source_color = vec3(0.37, 0.27, 0.19);
uniform vec3 mud_b : source_color = vec3(0.29, 0.21, 0.15);
uniform vec3 verge_color : source_color = vec3(0.47, 0.69, 0.28);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 车辙：四条随里程轻微摆动的轮胎印（两条行车线各一对）
float ruts(float lat, float along, float hw) {
	float wob = (vnoise(vec2(along * 0.045, 1.7)) - 0.5) * 1.1;
	float k = hw / 7.5;
	float r = 0.0;
	for (int i = 0; i < 4; i++) {
		float c = (i < 2 ? -1.0 : 1.0) * (i % 2 == 0 ? 3.1 : 1.7) * k + wob;
		float wid = 0.32 + 0.12 * vnoise(vec2(along * 0.3, float(i) * 3.1));
		r = max(r, smoothstep(wid, wid * 0.35, abs(lat - c)));
	}
	return r;
}

void dirt_road(float lat, float along, float edge_half, vec3 wc, out vec3 o_col, out float o_rough, out float o_spec) {
	vec3 w = wc / max(wc.r + wc.g + wc.b, 0.001);
	float n = fbm(wpos.xz * 0.55);
	float n2 = fbm(wpos.xz * 2.4 + 7.0);
	float fine = hash12(floor(wpos.xz * 18.0));
	float rut = ruts(lat, along, edge_half);
	// 土路：明暗斑驳 + 碎石点 + 车辙
	vec3 dirt = mix(dirt_a, dirt_b, smoothstep(0.3, 0.75, n));
	dirt *= 0.9 + 0.2 * n2;
	vec2 pc = floor(wpos.xz * 3.2);
	float peb = step(0.93, hash12(pc)) * smoothstep(0.42, 0.2, length(fract(wpos.xz * 3.2) - 0.5));
	dirt = mix(dirt, dirt_a * 1.35, peb * 0.8);
	dirt *= 1.0 - rut * 0.22;
	// 草路：中间长草，车辙处露出土
	vec3 grass = mix(grass_a, grass_b, smoothstep(0.35, 0.7, n2));
	float bald = smoothstep(0.52, 0.72, fbm(wpos.xz * 0.3 + 11.0));
	float worn = max(rut * 0.9, bald * 0.8);
	grass = mix(grass, dirt_b * 0.95, worn);
	// 泥泞：深色湿泥，车辙积水，大块水坑
	vec3 mud = mix(mud_a, mud_b, smoothstep(0.3, 0.7, n2));
	float puddle = smoothstep(0.56, 0.6, fbm(wpos.xz * 0.16 + 3.0));
	float wet_rut = rut * 0.8;
	float water = max(puddle, wet_rut * step(0.45, n));
	mud = mix(mud, mud_b * 0.55, rut * 0.6);
	mud = mix(mud, vec3(0.2, 0.2, 0.19), water * 0.85);
	vec3 col = dirt * w.r + grass * w.g + mud * w.b;
	float rough = mix(mix(0.95, 0.85, w.g), mix(0.6, 0.06, water), w.b);
	// 路边：不规则草边
	float en = (fbm(wpos.xz * 0.45) - 0.5) * 2.2 + (vnoise(wpos.xz * 2.6) - 0.5) * 0.6;
	float vg = smoothstep(edge_half - 0.5, edge_half + 0.8, abs(lat) + en);
	vec3 vc = verge_color * (0.88 + 0.24 * n2);
	col = mix(col, vc, vg);
	rough = mix(rough, 0.95, vg);
	// 起终点：地上一排黑白格
	float d0 = min(along, track_length - along);
	if (checker && (d0 < 1.4 || abs(along - track_length) < 1.4) && abs(lat) < edge_half) {
		vec2 cell = floor(vec2(lat / 1.0, along / 0.7));
		col = mix(vec3(0.1), vec3(0.93), mod(cell.x + cell.y, 2.0));
		rough = 0.8;
	}
	o_col = col;
	o_rough = rough;
	o_spec = mix(0.25, 0.6, w.b * water);
}

void fragment() {
	if (unpaved) {
		vec3 c;
		float r;
		float sp;
		float eh = UV2.x > 0.0 ? UV2.x : half_width - verge;
		dirt_road((UV.x - 0.5) * 2.0 * (eh + verge), UV.y, eh, COLOR.rgb, c, r, sp);
		ALBEDO = c;
		ROUGHNESS = r;
		SPECULAR = sp;
	} else {
		float hwv = UV2.x > 0.0 ? UV2.x : half_width;
		float lat = (UV.x - 0.5) * 2.0 * hwv;  // 米，右正
		float along = UV.y;                            // 米
		float n = fbm(wpos.xz * 1.7);
		float fine = hash12(floor(wpos.xz * 22.0));
		vec3 col = mix(base_color, speck_color, smoothstep(0.55, 0.9, n) * 0.8);
		col *= 0.93 + 0.1 * fine;
		// 赛车线上轮胎磨出的暗痕
		float wear = smoothstep(0.6, 0.0, abs(abs(lat) - hwv * 0.35)) * 0.06;
		col *= 1.0 - wear;
		float emit = 0.0;
		// 边线（距边缘 0.35 m，宽 0.25 m）
		float edge = abs(abs(lat) - (hwv - 0.45));
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
		if (checker && (d0 < 1.4 || abs(along - track_length) < 1.4)) {
			vec2 cell = floor(vec2(lat / 1.0, along / 0.7));
			float chk = mod(cell.x + cell.y, 2.0);
			col = mix(vec3(0.08), vec3(0.97), chk);
		}
		ALBEDO = col;
		ROUGHNESS = mix(0.82, 0.25, wet);
		SPECULAR = 0.35;
		EMISSION = (edge_line * line_color + center * center_color) * line_glow;
	}
}
