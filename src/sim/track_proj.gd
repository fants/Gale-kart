class_name TrackProj
extends RefCounted
## 赛道投影查询的结果（复用同一个对象，避免每帧分配）。

var idx := 0
var t := 0.0
var dist2 := 0.0
## 弧长位置（采样单位，可为小数）
var s := 0.0
## 横向偏移，右侧为正
var lateral := 0.0
## 右法线
var nx := 1.0
var nz := 0.0
## 切线
var tx := 0.0
var tz := 1.0
var road_y := 0.0
## 路面高度（含跳台）
var y := 0.0
