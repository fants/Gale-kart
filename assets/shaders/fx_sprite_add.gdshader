// 特效粒子绘制：叠加混合（火花、尾焰、光点、冲击环、风线、光柱），不受雾影响。
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
#include "res://assets/shaders/fx_sprite.gdshaderinc"
