extends RefCounted
class_name UIResponsive

## UIResponsive: Universal Adaptive & Responsive UI Engine for Godot 4
## Handles fluid screen scaling, notch/camera cutout safe areas, and dynamic layout positioning
## across all mobile (16:9, 18:9, 19.5:9, 20:9, 21:9), tablet (4:3, 16:10), foldable, and desktop screens.

## Returns safe area insets (left, right, top, bottom) in canvas coordinates.
static func get_safe_insets(caller: Control = null) -> Dictionary:
	var safe := DisplayServer.get_display_safe_area()
	var win_size := DisplayServer.window_get_size()
	
	if win_size.x <= 0 or win_size.y <= 0:
		return {"left": 0.0, "right": 0.0, "top": 0.0, "bottom": 0.0}
	
	var vp_size := Vector2(960.0, 540.0)
	if caller and caller.is_inside_tree():
		vp_size = caller.get_viewport_rect().size
	elif Engine.get_main_loop() and Engine.get_main_loop().root and Engine.get_main_loop().root.is_inside_tree():
		vp_size = Vector2(Engine.get_main_loop().root.get_visible_rect().size)
		
	var scale_x := vp_size.x / float(win_size.x)
	var scale_y := vp_size.y / float(win_size.y)
	
	var inset_l := float(safe.position.x) * scale_x
	var inset_t := float(safe.position.y) * scale_y
	var inset_r := float(win_size.x - (safe.position.x + safe.size.x)) * scale_x
	var inset_b := float(win_size.y - (safe.position.y + safe.size.y)) * scale_y
	
	return {
		"left": maxf(0.0, inset_l),
		"right": maxf(0.0, inset_r),
		"top": maxf(0.0, inset_t),
		"bottom": maxf(0.0, inset_b)
	}

## Returns the true visible viewport size in canvas units.
static func get_viewport_size(caller: Control = null) -> Vector2:
	if caller and caller.is_inside_tree():
		return caller.get_viewport_rect().size
	elif Engine.get_main_loop() and Engine.get_main_loop().root and Engine.get_main_loop().root.is_inside_tree():
		return Vector2(Engine.get_main_loop().root.get_visible_rect().size)
	return Vector2(960.0, 540.0)

## Computes responsive, ergonomic touch button layout across any aspect ratio and resolution.
static func get_default_touch_positions(caller: Control = null) -> Dictionary:
	var vp := get_viewport_size(caller)
	var insets := get_safe_insets(caller)
	
	var margin_l: float = 24.0 + insets["left"]
	var margin_r: float = 24.0 + insets["right"]
	var margin_b: float = 20.0 + insets["bottom"]
	
	var btn_w: float = 64.0
	var btn_h: float = 64.0
	var jump_w: float = 68.0
	var jump_h: float = 68.0
	var gap: float = 16.0
	
	var base_y := vp.y - margin_b - btn_h
	var jump_y := vp.y - margin_b - jump_h
	
	var pos_left := Vector2(margin_l, base_y)
	var pos_right := Vector2(margin_l + btn_w + gap, base_y)
	var pos_jump := Vector2(vp.x - margin_r - jump_w, jump_y)
	var pos_dash := Vector2(pos_jump.x - gap - btn_w, base_y)
	
	return {
		"left": pos_left,
		"right": pos_right,
		"dash": pos_dash,
		"jump": pos_jump
	}

