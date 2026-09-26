// 特效粒子的处理着色器：所有粒子都由 Effects 用 emit_particle() 逐个发射（emitting = false）。
// 每个粒子的参数随发射一起传入（需要 EMIT_FLAG_POSITION | ROTATION_SCALE | VELOCITY | COLOR | CUSTOM）：
//   TRANSFORM[0].xyz = (寿命 s, 起始尺寸, 结束尺寸)
//   TRANSFORM[1].xyz = (重力, 阻尼, 自转角速度)
//   TRANSFORM[2].xyz = (形状 + 模式 × 16, 拉伸系数, 地面高度偏移；< -50 表示不碰地面)
//   COLOR  = 起始颜色（分量可 > 1，配合辉光）
//   CUSTOM = (结束颜色 rgb, 透明度曲线：>= 0 为淡入比例；< 0 为保持到 1 + x 再淡出)
// 输出给绘制着色器：TRANSFORM 基向量（尺寸 / 朝向）、COLOR（当前颜色与透明度）、
//   CUSTOM = (形状码, 生命进度 0..1, 平面内旋转角, 随机数)
// 模式：0 公告板  1 沿速度拉伸  2 三维翻滚  3 水平贴地  4 竖直光柱
shader_type particles;
render_mode disable_force;

// 清除代数：Effects.clear() 递增它，旧一代的粒子在下一帧自行失效（不用 restart()）
uniform float generation = 0.0;

float hash(uint x) {
	x = ((x >> 16u) ^ x) * 0x45d9f3bu;
	x = ((x >> 16u) ^ x) * 0x45d9f3bu;
	x = (x >> 16u) ^ x;
	return float(x) / 4294967295.0;
}

mat3 axis_rot(vec3 a, float t) {
	float c = cos(t);
	float s = sin(t);
	float ic = 1.0 - c;
	return mat3(
		vec3(c + a.x * a.x * ic, a.y * a.x * ic + a.z * s, a.z * a.x * ic - a.y * s),
		vec3(a.x * a.y * ic - a.z * s, c + a.y * a.y * ic, a.z * a.y * ic + a.x * s),
		vec3(a.x * a.z * ic + a.y * s, a.y * a.z * ic - a.x * s, c + a.z * a.z * ic));
}

void start() {
	// 只接受 emit_particle() 发射的粒子（重启等途径产生的粒子立即作废）
	if (RESTART_CUSTOM) {
		ACTIVE = false;
	}
	vec3 p0 = TRANSFORM[0].xyz;
	vec3 p1 = TRANSFORM[1].xyz;
	vec3 p2 = TRANSFORM[2].xyz;
	uint seed = NUMBER * 747796405u + RANDOM_SEED * 2891336453u + INDEX;
	float rnd = hash(seed);
	vec3 axis = normalize(vec3(hash(seed + 11u), hash(seed + 23u), hash(seed + 37u)) - 0.5 + vec3(0.0, 0.001, 0.0));
	// 寿命、起始尺寸、结束尺寸、重力
	USERDATA1 = vec4(max(p0.x, 0.01), p0.y, p0.z, p1.x);
	// 阻尼、自转、拉伸、地面偏移
	USERDATA2 = vec4(p1.y, p1.z, p2.y, p2.z);
	USERDATA3 = COLOR;
	USERDATA4 = CUSTOM;
	// 发射高度、年龄、随机数、形状码
	USERDATA5 = vec4(TRANSFORM[3].y, 0.0, rnd, p2.x);
	USERDATA6 = vec4(axis, generation);
	CUSTOM = vec4(p2.x, 0.0, rnd * 6.2831853, rnd);
	float s = p0.y;
	TRANSFORM[0] = vec4(s, 0.0, 0.0, 0.0);
	TRANSFORM[1] = vec4(0.0, s, 0.0, 0.0);
	TRANSFORM[2] = vec4(0.0, 0.0, s, 0.0);
}

void process() {
	// 防御：异常的帧间隔会让阻尼的指数爆掉
	float dt = clamp(DELTA, 0.0, 0.1);
	float life = USERDATA1.x;
	float age = USERDATA5.y + dt;
	USERDATA5.y = age;
	float u = clamp(age / life, 0.0, 1.0);
	if (age >= life || abs(USERDATA6.w - generation) > 0.5) {
		ACTIVE = false;
	}

	// 阻尼与重力（位置由引擎按 VELOCITY 积分）
	VELOCITY *= exp(-USERDATA2.x * dt);
	VELOCITY.y -= USERDATA1.w * dt;
	float vl = length(VELOCITY);
	if (vl > 80.0) {
		VELOCITY *= 80.0 / vl;
	}
	float floor_off = USERDATA2.w;
	if (floor_off > -50.0) {
		float fy = USERDATA5.x + floor_off;
		if (TRANSFORM[3].y < fy) {
			TRANSFORM[3].y = fy;
			if (VELOCITY.y < 0.0) {
				VELOCITY.y *= -0.3;
				VELOCITY.xz *= 0.45;
			}
		}
	}

	// 尺寸：先快后慢
	float k = u * (2.0 - u);
	float size = mix(USERDATA1.y, USERDATA1.z, k);

	// 透明度曲线
	float f = USERDATA4.a;
	float a;
	if (f >= 0.0) {
		a = u < f ? u / max(f, 0.0001) : 1.0 - (u - f) / max(1.0 - f, 0.0001);
	} else {
		float h = 1.0 + f;
		a = u < h ? 1.0 : 1.0 - (u - h) / max(-f, 0.0001);
	}
	COLOR = vec4(mix(USERDATA3.rgb, USERDATA4.rgb, u), USERDATA3.a * clamp(a, 0.0, 1.0));
	CUSTOM.y = u;
	CUSTOM.z += USERDATA2.y * dt;

	int code = int(USERDATA5.w + 0.5);
	int mode = code / 16;
	if (mode == 1) {
		// 沿速度拉伸：X 为宽度，Y 为（带方向的）长度。拉伸系数为负时反向：从粒子位置沿速度方向伸出（尾焰）
		float sp = length(VELOCITY);
		vec3 dir = sp > 0.001 ? VELOCITY / sp : vec3(0.0, 1.0, 0.0);
		float st = USERDATA2.z;
		float len = size * 2.0 + sp * abs(st);
		TRANSFORM[0] = vec4(size, 0.0, 0.0, 0.0);
		TRANSFORM[1] = vec4(dir * (st < 0.0 ? -len : len), 0.0);
		TRANSFORM[2] = vec4(0.0, 0.0, size, 0.0);
	} else if (mode == 2) {
		mat3 r = axis_rot(USERDATA6.xyz, CUSTOM.z) * size;
		TRANSFORM[0] = vec4(r[0], 0.0);
		TRANSFORM[1] = vec4(r[1], 0.0);
		TRANSFORM[2] = vec4(r[2], 0.0);
	} else if (mode == 3) {
		float c = cos(CUSTOM.z) * size;
		float s = sin(CUSTOM.z) * size;
		TRANSFORM[0] = vec4(c, 0.0, s, 0.0);
		TRANSFORM[1] = vec4(-s, 0.0, c, 0.0);
		TRANSFORM[2] = vec4(0.0, size, 0.0, 0.0);
	} else if (mode == 4) {
		TRANSFORM[0] = vec4(size, 0.0, 0.0, 0.0);
		TRANSFORM[1] = vec4(0.0, size * USERDATA2.z, 0.0, 0.0);
		TRANSFORM[2] = vec4(0.0, 0.0, size, 0.0);
	} else {
		TRANSFORM[0] = vec4(size, 0.0, 0.0, 0.0);
		TRANSFORM[1] = vec4(0.0, size, 0.0, 0.0);
		TRANSFORM[2] = vec4(0.0, 0.0, size, 0.0);
	}
}
