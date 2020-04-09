tool
extends EditorPlugin


func _enter_tree():
	add_custom_type("PlayerSpawn", "Spatial", load("res://common/game/mode/player_spawn/PlayerSpawn.gd"), load("res://common/game/mode/player_spawn/player_spawn_icon.png"))


func _exit_tree():
	remove_custom_type("PlayerSpawn")
