extends Control

# MenuCharacter - Interactive Animated Wrong Way Character for Main Menu
# - Stands proudly under the "WRONG WAY" title
# - Natural breathing squash & stretch animation
# - Expressive eyes with blinking
# - Interactive PC mouse cursor tracking (pupils follow the cursor dynamically!)
# - Interactive click / tap reaction (cute hop & happy eyes)
# - Interactive Exit hover reaction (quivering sad, tearful pleading eyes)

var body_w: float = 34.0
var body_h: float = 40.0

var _time: float = 0.0
var is_blinking: bool = false
var blink_timer: float = 3.2
var blink_duration: float = 0.13

# Cursor tracking
var current_pupil_offset: Vector2 = Vector2.ZERO
var target_pupil_offset: Vector2 = Vector2.ZERO

# Reaction: Happy
var is_happy: bool = false
var happy_timer: float = 0.0
var hop_offset_y: float = 0.0

# Reaction: Sad (Exit Hover)
var is_sad: bool = false
var sad_factor: float = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(body_w + 16, body_h + 16)
	mouse_filter = Control.MOUSE_FILTER_STOP
	blink_timer = randf_range(2.5, 4.5)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_trigger_hop()

func _trigger_hop() -> void:
	if is_sad:
		return
	is_happy = true
	happy_timer = 0.8
	var tw := create_tween()
	tw.tween_property(self, "hop_offset_y", -14.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "hop_offset_y", 0.0, 0.18).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	var sm = get_node_or_null("/root/SoundManager")
	if sm and sm.has_method("play"):
		sm.play("click")

func trigger_happy_reaction() -> void:
	if is_sad:
		return
	_trigger_hop()

func set_happy_emotion(happy: bool) -> void:
	if is_sad:
		return
	if happy:
		_trigger_hop()
	else:
		if happy_timer > 0.2:
			happy_timer = 0.2

func set_sad_emotion(sad: bool) -> void:
	is_sad = sad
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	
	# Smooth emotional transition for sad/pleading state
	if is_sad:
		sad_factor = move_toward(sad_factor, 1.0, delta * 6.5)
	else:
		sad_factor = move_toward(sad_factor, 0.0, delta * 5.0)
	
	# Blinking (disabled during sad or happy states)
	if not is_happy and sad_factor < 0.1:
		blink_timer -= delta
		if blink_timer <= 0.0:
			is_blinking = true
			blink_duration -= delta
			if blink_duration <= 0.0:
				is_blinking = false
				blink_timer = randf_range(3.0, 5.5)
				blink_duration = 0.13
	elif is_happy:
		is_blinking = false
		happy_timer -= delta
		if happy_timer <= 0.0:
			is_happy = false
	else:
		is_blinking = false
			
	# Mouse cursor tracking (PC & Desktop)
	var mouse_pos := get_global_mouse_position()
	var eye_center_global := global_position + Vector2(custom_minimum_size.x * 0.5, custom_minimum_size.y * 0.5 - 2.0)
	var diff := mouse_pos - eye_center_global
	var dist := diff.length()
	
	if dist > 4.0:
		var dir := diff.normalized()
		var strength := clampf(dist / 140.0, 0.15, 1.0)
		target_pupil_offset = Vector2(dir.x * 2.8 * strength, dir.y * 2.8 * strength)
	else:
		target_pupil_offset = Vector2.ZERO
		
	# When sad, gaze looks pleadingly up-left towards Quit button
	if sad_factor > 0.001:
		var sad_look := Vector2(-2.5, -2.4)
		target_pupil_offset = target_pupil_offset.lerp(sad_look, sad_factor * 0.85)
		
	current_pupil_offset = current_pupil_offset.lerp(target_pupil_offset, delta * 12.0)
	
	queue_redraw()

func _draw() -> void:
	var center := Vector2(custom_minimum_size.x * 0.5, custom_minimum_size.y - 4.0 + hop_offset_y)
	
	# Breathing squash & stretch
	var breath := sin(_time * 2.6) * 0.03
	var h := body_h * (1.0 + breath)
	var w := body_w * (1.0 - breath * 0.5)
	
	if is_happy:
		# Happy stretch
		w *= 1.08
		h *= 0.94
	elif sad_factor > 0.001:
		# Trembling body (whimpering / shivering with sadness)
		var tremble := sin(_time * 28.0) * (0.85 * sad_factor)
		center.x += tremble
		center.y += 1.2 * sad_factor
		h *= (1.0 - 0.05 * sad_factor)
		w *= (1.0 + 0.04 * sad_factor)
		
	var body_rect := Rect2(center.x - w * 0.5, center.y - h, w, h)
	
	# Shadow under character
	var shadow_rect := Rect2(center.x - body_w * 0.45, center.y - 2.0, body_w * 0.9, 4.0)
	draw_colored_polygon([
		Vector2(shadow_rect.position.x, shadow_rect.position.y + 2.0),
		Vector2(shadow_rect.position.x + shadow_rect.size.x * 0.5, shadow_rect.position.y),
		Vector2(shadow_rect.end.x, shadow_rect.position.y + 2.0),
		Vector2(shadow_rect.position.x + shadow_rect.size.x * 0.5, shadow_rect.end.y)
	], Color(0.0, 0.0, 0.0, 0.35))
	
	# Chassis (tana)
	draw_rect(body_rect, Color("#18171f"), true)
	draw_rect(body_rect, Color("#2d2838"), false, 1.5)
	
	# Top subtle bevel highlight
	draw_line(
		Vector2(body_rect.position.x + 2, body_rect.position.y + 1),
		Vector2(body_rect.end.x - 2, body_rect.position.y + 1),
		Color(1, 1, 1, 0.12),
		1.0
	)
	
	# Eyes
	var eye_y := center.y - h * 0.52
	var eye_radius := Vector2(4.8, 6.0)
	var left_eye := Vector2(center.x - 7.5, eye_y)
	var right_eye := Vector2(center.x + 7.5, eye_y)
	
	if is_happy:
		# Happy squint arcs: ^^
		_draw_happy_eye(left_eye)
		_draw_happy_eye(right_eye)
	elif is_blinking and sad_factor < 0.2:
		# Blink slits
		draw_line(left_eye - Vector2(4.5, 0), left_eye + Vector2(4.5, 0), Color.WHITE, 2.0)
		draw_line(right_eye - Vector2(4.5, 0), right_eye + Vector2(4.5, 0), Color.WHITE, 2.0)
	else:
		# Sclera (White eye)
		_draw_ellipse(left_eye, eye_radius, Color.WHITE)
		_draw_ellipse(right_eye, eye_radius, Color.WHITE)
		
		# Pupils (following mouse or looking pleadingly at Exit)
		var p_radius := lerpf(2.2, 2.7, sad_factor)
		var p_left := left_eye + current_pupil_offset
		var p_right := right_eye + current_pupil_offset
		
		draw_circle(p_left, p_radius, Color("#100f14"))
		draw_circle(p_right, p_radius, Color("#100f14"))
		
		# White glints in pupils (extra glassy shimmer when sad)
		draw_circle(p_left + Vector2(-0.8, -0.8), 0.75, Color.WHITE)
		draw_circle(p_right + Vector2(-0.8, -0.8), 0.75, Color.WHITE)
		if sad_factor > 0.15:
			draw_circle(p_left + Vector2(0.9, 0.7), 0.55 * sad_factor, Color(1, 1, 1, 0.8 * sad_factor))
			draw_circle(p_right + Vector2(0.9, 0.7), 0.55 * sad_factor, Color(1, 1, 1, 0.8 * sad_factor))
			
		# Sad pleading eyebrows (slanting upward inwards: \  / )
		if sad_factor > 0.05:
			var brow_alpha := clampf(sad_factor * 1.2, 0.0, 1.0)
			var brow_col := Color(0.95, 0.96, 1.0, 0.9 * brow_alpha)
			draw_line(
				Vector2(left_eye.x - 5.5, eye_y - 7.5 + 1.0 * sad_factor),
				Vector2(left_eye.x + 4.5, eye_y - 9.8 - 0.8 * sad_factor),
				brow_col, 1.8, true
			)
			draw_line(
				Vector2(right_eye.x - 4.5, eye_y - 9.8 - 0.8 * sad_factor),
				Vector2(right_eye.x + 5.5, eye_y - 7.5 + 1.0 * sad_factor),
				brow_col, 1.8, true
			)
			
			# Cute glistening tear droplets under eyes
			var tear_col := Color(0.38, 0.74, 0.97, 0.85 * brow_alpha)
			var left_tear := left_eye + Vector2(-3.4, 7.2)
			var right_tear := right_eye + Vector2(3.4, 7.2)
			draw_circle(left_tear, 1.6 * sad_factor, tear_col)
			draw_circle(left_tear + Vector2(-0.4, -0.4), 0.5 * sad_factor, Color(1, 1, 1, 0.9 * brow_alpha))
			draw_circle(right_tear, 1.4 * sad_factor, tear_col)
			draw_circle(right_tear + Vector2(-0.3, -0.3), 0.45 * sad_factor, Color(1, 1, 1, 0.9 * brow_alpha))
			
			# Sad little downturned mouth (quivering lip)
			_draw_sad_mouth(Vector2(center.x, eye_y + 9.5), sad_factor)

func _draw_ellipse(c: Vector2, r: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	var segs := 18
	for i in range(segs):
		var th := float(i) * 2.0 * PI / float(segs)
		pts.append(c + Vector2(cos(th) * r.x, sin(th) * r.y))
	draw_colored_polygon(pts, color)

func _draw_happy_eye(c: Vector2) -> void:
	# Curved upward arc
	var pts := PackedVector2Array()
	var segs := 8
	var r := 4.5
	for i in range(segs + 1):
		var th := PI + float(i) * PI / float(segs)
		pts.append(c + Vector2(cos(th) * r, sin(th) * 3.0))
	draw_polyline(pts, Color.WHITE, 2.2, true)

func _draw_sad_mouth(c: Vector2, factor: float) -> void:
	var pts := PackedVector2Array()
	var segs := 6
	var r := 3.2 * factor
	for i in range(segs + 1):
		var th := float(i) * PI / float(segs)
		pts.append(c + Vector2(-r * cos(th), -1.8 * sin(th) * factor))
	draw_polyline(pts, Color(0.85, 0.9, 1.0, 0.75 * factor), 1.5, true)
