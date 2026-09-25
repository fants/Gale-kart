class_name CameraRig
extends RefCounted
## 相机：追尾弹簧跟随（漂移时航向滞后露出车身角度）、开赛航拍、完赛环绕、震动与速度 FOV。
## 移植自参考版 cameraRig.js，加入插值与更强的速度感。

var cam: Camera3D
var pos := Vector3.ZERO
var look := Vector3.ZERO
var yaw := 0.0
var fov := 68.0
var shake_amp := 0.0
var shake_t := 0.0
var far := true
var initialized := false
## 相机相对车的偏移（平滑的是偏移量而不是世界坐标，高速时不会越拖越远）
var _off := Vector3.ZERO
var _cam_y := 0.0
## 视角远 / 近的距离与高度
const FAR_D := 4.8
const FAR_H := 2.15
const NEAR_D := 3.8
const NEAR_H := 1.8
const LOOK_AHEAD := 3.4


func _init(p_cam: Camera3D) -> void:
	cam = p_cam


func shake(amount: float) -> void:
	shake_amp = minf(1.2, maxf(shake_amp, amount))


func _kpos(k: KartSim, alpha: float) -> Vector3:
	return Vector3(lerpf(k.prev_x, k.x, alpha), lerpf(k.prev_y, k.y, alpha), lerpf(k.prev_z, k.z, alpha))


func snap_behind(k: KartSim) -> void:
	yaw = k.heading
	var d := FAR_D if far else NEAR_D
	var h := FAR_H if far else NEAR_H
	_off = Vector3(-sin(yaw) * d, 0.0, -cos(yaw) * d)
	_cam_y = k.y + h
	pos = Vector3(k.x, 0.0, k.z) + _off
	pos.y = _cam_y
	look = Vector3(k.x, k.y + 1.1, k.z)
	initialized = true


func chase(k: KartSim, dt: float, alpha: float) -> void:
	if not initialized:
		snap_behind(k)
	var kp := _kpos(k, alpha)
	var heading := MathX.lerp_angle_short(k.prev_heading, k.heading, alpha)
	var spd := k.speed
	var target_yaw := heading
	if spd > 4.0:
		var vel_yaw := atan2(k.vx, k.vz)
		# 前进时以运动方向为主，漂移时车身角度得以显现
		if cos(vel_yaw - heading) > 0.0:
			target_yaw = heading + MathX.wrap_angle(vel_yaw - heading) * 0.65
	if k.spin > 0.0 or k.flip > 0.0:
		target_yaw = yaw
	yaw = MathX.damp_angle(yaw, target_yaw, 4.5 if k.drifting else 7.0, dt)

	var boost := 1.0 if k.is_boosting() else 0.0
	var d := (FAR_D if far else NEAR_D) + boost * 0.6 + clampf(spd / 40.0, 0.0, 1.0) * 0.5
	var h := FAR_H if far else NEAR_H
	var fx := sin(yaw)
	var fz := cos(yaw)
	_off = MathX.damp_v3(_off, Vector3(-fx * d, 0.0, -fz * d), 10.0, dt)
	_cam_y = MathX.damp(_cam_y, kp.y + h + (1.2 if k.bubble > 0.0 else 0.0), 8.0 if k.on_ground else 3.5, dt)
	pos = Vector3(kp.x + _off.x, _cam_y, kp.z + _off.z)
	look = Vector3(kp.x + fx * LOOK_AHEAD, kp.y + 1.0, kp.z + fz * LOOK_AHEAD)
	var fov_t := 68.0 + clampf(spd / 36.0, 0.0, 1.25) * 7.0 + boost * (11.0 if k.boost_kind == "nitro" else 7.0)
	fov = MathX.damp(fov, fov_t, 4.0, dt)
	_apply(dt)


## 开赛航拍：u 0..1，从高空环绕起点落到玩家身后
func intro(track: TrackData, k: KartSim, u: float, dt: float) -> void:
	var e := MathX.smooth(0.0, 1.0, u)
	var p0 := track.point_at(0.0, 0.0)
	var ang := k.heading + PI * (1.0 - e) * 1.2 + 0.6
	var radius := lerpf(60.0, FAR_D if far else NEAR_D, e)
	var height := lerpf(38.0, FAR_H if far else NEAR_H, e)
	var cx := lerpf(p0.x, k.x, e)
	var cz := lerpf(p0.z, k.z, e)
	var cy := lerpf(p0.y, k.y, e)
	pos = Vector3(cx - sin(ang) * radius, cy + height, cz - cos(ang) * radius)
	look = Vector3(lerpf(p0.x, k.x + sin(k.heading) * 3.2, e), cy + 1.2, lerpf(p0.z, k.z + cos(k.heading) * 3.2, e))
	yaw = ang
	fov = 60.0 + e * 8.0
	if u >= 1.0:
		yaw = k.heading
	initialized = true
	_off = Vector3(pos.x - k.x, 0.0, pos.z - k.z)
	_cam_y = pos.y
	_apply(dt)


## 完赛后环绕
func orbit(k: KartSim, time: float, dt: float) -> void:
	var a := time * 0.35
	var tx := k.x + sin(a) * 8.0
	var tz := k.z + cos(a) * 8.0
	pos.x = MathX.damp(pos.x, tx, 2.0, dt)
	pos.z = MathX.damp(pos.z, tz, 2.0, dt)
	pos.y = MathX.damp(pos.y, k.y + 3.2, 2.0, dt)
	look = Vector3(k.x, k.y + 0.9, k.z)
	fov = MathX.damp(fov, 55.0, 2.0, dt)
	_off = Vector3(pos.x - k.x, 0.0, pos.z - k.z)
	_cam_y = pos.y
	_apply(dt)


## 直接指定机位（回放 / 颁奖台用）
func set_view(p: Vector3, target: Vector3, p_fov: float, dt: float) -> void:
	pos = p
	look = target
	fov = p_fov
	initialized = true
	_apply(dt)


func _apply(dt: float) -> void:
	var p := pos
	if shake_amp > 0.001:
		shake_t += dt * 38.0
		var a := shake_amp * 0.25
		p += Vector3(sin(shake_t * 1.3) * a, sin(shake_t * 1.7 + 1.0) * a, sin(shake_t * 1.1 + 2.0) * a)
		shake_amp *= exp(-dt * 6.0)
	if p.distance_squared_to(look) < 0.0001:
		return
	cam.global_transform = Transform3D(Basis.looking_at(look - p, Vector3.UP), p)
	cam.fov = fov
