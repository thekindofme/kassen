extends Node
## Offscreen rendering for dev screenshots (autoload "Offscreen", first in the autoload order).
## Active only with the user arg `--offscreen=WxH` (tools/render_run.sh adds it). The OS window is
## shrunk to a borderless 1x1 pixel so nothing flashes on the user's screen, while the root viewport
## keeps rendering at WxH using the "viewport" stretch mode (fixed internal resolution). Game code,
## UI layout and `get_viewport().get_texture().get_image()` all see the full WxH frame.

var active := false
var size := Vector2i(1920, 1080)


func _enter_tree() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--offscreen"):
			active = true
			var v := a.get_slice("=", 1)
			if "x" in v:
				size = Vector2i(int(v.get_slice("x", 0)), int(v.get_slice("x", 1)))
	if not active:
		return
	var w := get_window()
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	w.content_scale_size = size
	w.borderless = true
	w.min_size = Vector2i(1, 1)
	w.size = Vector2i(1, 1)


func _process(_d: float) -> void:
	if active and get_window().size != Vector2i(1, 1):
		get_window().size = Vector2i(1, 1)
