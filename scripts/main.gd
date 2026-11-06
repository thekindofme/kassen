extends Node
## Boot scene. Hands over to the Game flow autoload (title → select → briefing → battle → results).
## Without the autoload (or with --shot/--demo/--map/--battle/--skip_menu, see Game.boot) it goes
## straight into the battle as before.

func _ready() -> void:
	var game := get_node_or_null("/root/Game")
	if game != null and game.has_method("boot"):
		game.boot.call_deferred()
	else:
		get_tree().change_scene_to_file.call_deferred("res://scenes/battle.tscn")
