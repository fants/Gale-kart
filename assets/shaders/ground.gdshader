// 地面：地形（顶点色）与路肩（统一颜色）共用。按主题叠加世界空间细节噪声。
shader_type spatial;
render_mode diffuse_burley;
#include "res://assets/shaders/noise.gdshaderinc"

uniform vec3 tint : source_color = vec3(1.0);
uniform bool use_vertex_color = true;
uniform float detail = 0.18;
// 0 草地，1 沙地，2 雪地，3 夜城硬地，4 森林，5 崖壁（横向岩层）
uniform int kind = 0;
uniform float sparkle = 0.0;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col = use_vertex_color ? COLOR.rgb : tint;
	float big = fbm(wpos.xz * 0.045);
	float mid = fbm(wpos.xz * 0.35);
	float fine = vnoise(wpos.xz * 3.1);
	float v = (big - 0.5) * 0.6 + (mid - 0.5) * 0.7 + (fine - 0.5) * 0.5;
	if (kind == 1) {
		// 沙纹
		float rip = sin(wpos.x * 1.3 + wpos.z * 0.6 + big * 9.0) * 0.5 + 0.5;
		v += (rip - 0.5) * 0.35;
	} else if (kind == 0 || kind == 4) {
		// 草丛斑块
		float tuft = smoothstep(0.55, 0.8, vnoise(wpos.xz * 1.2));
		col = mix(col, col * vec3(0.8, 0.95, 0.72), tuft * 0.5);
		if (kind == 4) {
			float moss = smoothstep(0.5, 0.75, fbm(wpos.xz * 0.12 + 3.0));
			col = mix(col, col * vec3(0.72, 0.62, 0.45), moss * 0.35);
		}
	}
	if (kind == 5) {
		// 崖壁：深浅相间的横向岩层，层线随噪声起伏
		float strata = fract(wpos.y * 0.55 + mid * 1.4);
		col = mix(tint * 0.78, tint * 1.12, smoothstep(0.2, 0.8, strata));
		col = mix(col, tint * 0.55, smoothstep(0.93, 1.0, strata) * 0.8);
	}
	col *= 1.0 + v * detail;
	// 陡坡露出岩土
	float steep = 1.0 - smoothstep(0.62, 0.85, wnorm.y);
	vec3 rock = kind == 2 ? vec3(0.72, 0.78, 0.86) : (kind == 1 ? vec3(0.78, 0.6, 0.4) : vec3(0.48, 0.44, 0.4));
	if (kind == 4) {
		// 森林：陡坡是深褐色的横向岩层（悬崖）
		float strata = fract(wpos.y * 0.55 + mid * 1.4);
		vec3 rk = vec3(0.16, 0.085, 0.045);  // 线性空间（顶点色按线性处理）
		vec3 cliff = mix(rk * 0.8, rk * 1.15, smoothstep(0.2, 0.8, strata));
		cliff = mix(cliff, rk * 0.55, smoothstep(0.93, 1.0, strata) * 0.8);
		float st4 = 1.0 - smoothstep(0.7, 0.88, wnorm.y);
		col = mix(col, cliff * (0.9 + 0.2 * mid), st4 * 0.95);
	} else if (kind != 5) {
		col = mix(col, rock * (0.85 + 0.3 * mid), steep * 0.75);
	}
	ALBEDO = col;
	ROUGHNESS = kind == 2 ? 0.55 : 0.95;
	SPECULAR = kind == 2 ? 0.5 : 0.2;
	if (sparkle > 0.0) {
		float sp = step(0.985, hash12(floor(wpos.xz * 9.0) + floor(TIME * 2.0)));
		EMISSION = vec3(sp * sparkle);
	}
}
