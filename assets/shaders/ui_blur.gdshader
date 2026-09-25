shader_type canvas_item;
// 模态背景：对屏幕做柔和模糊并叠加墨蓝色调（暂停菜单、设置、纪录等页面）。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform vec4 tint : source_color = vec4(0.106, 0.122, 0.231, 1.0);
uniform float tint_alpha = 0.38;
uniform float lod = 2.6;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * 6.0;
	vec3 c = vec3(0.0);
	float lv = lod * amount;
	c += textureLod(screen_tex, SCREEN_UV, lv).rgb * 0.2;
	c += textureLod(screen_tex, SCREEN_UV + vec2(px.x, 0.0), lv).rgb * 0.1;
	c += textureLod(screen_tex, SCREEN_UV - vec2(px.x, 0.0), lv).rgb * 0.1;
	c += textureLod(screen_tex, SCREEN_UV + vec2(0.0, px.y), lv).rgb * 0.1;
	c += textureLod(screen_tex, SCREEN_UV - vec2(0.0, px.y), lv).rgb * 0.1;
	c += textureLod(screen_tex, SCREEN_UV + px, lv).rgb * 0.1;
	c += textureLod(screen_tex, SCREEN_UV - px, lv).rgb * 0.1;
	c += textureLod(screen_tex, SCREEN_UV + vec2(px.x, -px.y), lv).rgb * 0.1;
	c += textureLod(screen_tex, SCREEN_UV + vec2(-px.x, px.y), lv).rgb * 0.1;
	c = mix(c, tint.rgb, tint_alpha * amount);
	COLOR = vec4(c, amount > 0.001 ? 1.0 : 0.0);
}
