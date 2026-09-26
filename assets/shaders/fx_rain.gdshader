// 乌云下的雨丝：网格里每个四边形共用一个中心（UV2 = 水平位置，COLOR.r = 相位），
// 顶点着色器让它循环下落并绕 Y 轴朝向相机，CPU 零开销。
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, world_vertex_coords;

uniform float top = 3.7;
uniform float height = 3.5;
uniform float speed = 2.4;
uniform float drop_len = 0.6;
uniform float drop_width = 0.035;
uniform float amount = 1.0;

varying float v_a;

void vertex() {
	float ph = fract(TIME * speed + COLOR.r);
	vec3 c = (MODEL_MATRIX * vec4(UV2.x, top - ph * height, UV2.y, 1.0)).xyz;
	vec3 side = cross(vec3(0.0, 1.0, 0.0), CAMERA_POSITION_WORLD - c);
	side = normalize(side + vec3(0.00001, 0.0, 0.0));
	VERTEX = c + side * (UV.x - 0.5) * drop_width + vec3(0.0, -1.0, 0.0) * UV.y * drop_len;
	v_a = smoothstep(0.0, 0.08, ph) * smoothstep(1.0, 0.85, ph) * amount;
}

void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;
	ALBEDO = vec3(0.78, 0.85, 0.98);
	ALPHA = (1.0 - across) * v_a * 0.75 * (0.35 + 0.65 * (1.0 - UV.y));
}
