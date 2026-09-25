extends Node
## 全局流程（桩）：Task 5 / 10 / 11 会逐步补全。

var main: Node


func _ready() -> void:
	InputSetup.setup()


func boot(main_node: Node) -> void:
	main = main_node
