extends Node
## 入口节点：把自己交给 Game 单例，由它负责菜单与比赛之间的切换。


func _ready() -> void:
	Game.boot(self)
