extends Node
## Boot scene. For now it goes straight into the battle (menu/briefing come later).

func _ready() -> void:
	get_tree().change_scene_to_file.call_deferred("res://scenes/battle.tscn")
