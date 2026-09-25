// 风格化天空：顶部 → 地平线渐变、太阳光晕、程序化云；夜晚模式有星星与月亮。
shader_type sky;
#include "res://assets/shaders/noise.gdshaderinc"

uniform vec3 top_color : source_color = vec3(0.25, 0.62, 0.94);
uniform vec3 horizon_color : source_color = vec3(0.81, 0.92, 1.0);
uniform vec3 ground_color : source_color = vec3(0.55, 0.62, 0.55);
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.84);
uniform float sun_size = 0.035;
uniform float cloud_amount = 0.45;
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform bool night = false;
uniform float exposure = 1.0;

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.55));
	} else {
		col = mix(horizon_color, ground_color, clamp(-h * 4.0, 0.0, 1.0));
	}
	vec3 sd = LIGHT0_ENABLED ? LIGHT0_DIRECTION : normalize(vec3(0.5, 0.6, 0.3));
	float sdot = max(dot(d, sd), 0.0);
	if (!night) {
		col += sun_color * pow(sdot, 12.0) * 0.35;
		col += sun_color * pow(sdot, 220.0) * 1.2;
		col += sun_color * smoothstep(1.0 - sun_size * 0.1, 1.0 - sun_size * 0.08, sdot) * 6.0;
	} else {
		// 星空与月亮
		vec2 sp = d.xz / max(d.y + 0.15, 0.05) * 60.0;
		float star = step(0.9965, hash12(floor(sp))) * smoothstep(0.0, 0.3, h);
		col += vec3(star) * (0.6 + 0.4 * sin(TIME * 3.0 + hash12(floor(sp)) * 40.0));
		col += sun_color * smoothstep(0.9993, 0.9996, sdot) * 2.0;
		col += sun_color * pow(sdot, 60.0) * 0.25;
	}
	if (h > 0.0 && cloud_amount > 0.0 && AT_CUBEMAP_PASS == false) {
		vec2 cp = d.xz / (h + 0.12) * 1.3 + vec2(TIME * 0.004, 0.0);
		float c = fbm(cp * 1.6);
		c = smoothstep(1.0 - cloud_amount, 1.0 - cloud_amount + 0.25, c);
		vec3 cc = mix(cloud_color, cloud_color * 0.75 + horizon_color * 0.25, 1.0 - h);
		col = mix(col, cc, c * smoothstep(0.0, 0.18, h) * 0.9);
	}
	COLOR = col * exposure;
}
