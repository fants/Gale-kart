// 特效粒子绘制：普通混合（烟、尘、碎片、彩带、水滴、星星），按视深排序。
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
#include "res://assets/shaders/fx_sprite.gdshaderinc"
