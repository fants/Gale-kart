// 积雪：按世界法线朝上的程度混入白色，保留原材质颜色；边缘带一点噪声，看起来像堆积的雪。
// use_vertex_color：颜色烘焙在顶点色里（alpha = 积雪量），同时乘 MultiMesh 实例色；
// use_instance_color：只乘实例色（如屋顶颜色）。
shader_type spatial;
render_mode diffuse_burley;
#include "res://assets/shaders/noise.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.3, 0.5, 0.4);
uniform bool use_vertex_color = false;
uniform bool use_instance_color = false;
uniform float snow_amount = 1.0;
uniform vec3 snow_color : source_color = vec3(0.95, 0.97, 1.0);

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col = base_color;
	float amount = snow_amount;
	if (use_vertex_color) {
		col *= COLOR.rgb;
		amount *= COLOR.a;
	} else if (use_instance_color) {
		col *= COLOR.rgb;
	}
	float n = vnoise(wpos.xz * 1.7 + wpos.y * 0.9) - 0.5;
	float up = normalize(wnorm).y + n * 0.35;
	float s = smoothstep(0.25, 0.55, up) * amount;
	// 雪面略带蓝色阴影
	vec3 snow = mix(snow_color * vec3(0.86, 0.92, 1.0), snow_color, smoothstep(0.55, 0.95, up));
	ALBEDO = mix(col, snow, s);
	ROUGHNESS = mix(0.9, 0.6, s);
	SPECULAR = mix(0.25, 0.5, s);
}
