shader_type canvas_item;
// 转场擦除：多色斜向色带从左向右扫过（progress 0→1 盖住，1→2 揭开）。

uniform float progress = 0.0;
uniform float aspect = 1.7778;
uniform vec4 c0 : source_color = vec4(1.0, 0.788, 0.235, 1.0);
uniform vec4 c1 : source_color = vec4(0.243, 0.776, 1.0, 1.0);
uniform vec4 c2 : source_color = vec4(1.0, 0.302, 0.369, 1.0);
uniform vec4 c3 : source_color = vec4(0.106, 0.122, 0.231, 1.0);

void fragment() {
	// 斜向坐标：0 在左上角，约 1 在右下角
	float x = (UV.x * aspect + (1.0 - UV.y) * 0.35) / (aspect + 0.35);
	float band = 0.09;
	vec4 col = c3;
	float cover;
	if (progress <= 1.0) {
		cover = progress * (1.0 + band * 3.0);
		float d = cover - x;
		if (d < 0.0) discard;
		col = d < band ? c0 : (d < band * 2.0 ? c1 : (d < band * 3.0 ? c2 : c3));
	} else {
		float p = progress - 1.0;
		cover = p * (1.0 + band * 3.0);
		float d = x - cover + band * 3.0;
		if (d < 0.0) discard;
		col = d < band ? c2 : (d < band * 2.0 ? c1 : (d < band * 3.0 ? c0 : c3));
	}
	COLOR = col;
}
