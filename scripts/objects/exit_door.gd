extends Area2D
class_name ExitDoor

signal door_sunk_completely

@export var door_size: Vector2 = Vector2(44, 58)
@export var runaway_enabled: bool = false
@export var runaway_distance: float = 110.0
@export var runaway_offset_x: float = -180.0

var initial_x: float
var initial_y: float
var is_sinking: bool = false
var has_run_away: bool = false
var is_running_away: bool = false
var runaway_tween_x: Tween
var runaway_tween_y: Tween
var reset_cooldown: float = 0.0
var pulse_time: float = 0.0
var sink_amount: float = 0.0
var show_triangle: bool = true

func _ready() -> void:
	initial_x = global_position.x
	initial_y = global_position.y
	reset_cooldown = 0.40
	body_entered.connect(_on_body_entered)

func _physics_process(_delta: float) -> void:
	if runaway_enabled and not has_run_away and not is_sinking and not is_running_away:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null and is_instance_valid(player):
			if "is_dead" in player and player.is_dead:
				return
			if "is_invulnerable" in player and player.is_invulnerable:
				return
			var dist := global_position.distance_to(player.global_position)
			if dist < runaway_distance:
				_run_away()

func _run_away() -> void:
	if has_run_away or is_running_away:
		return
	has_run_away = true
	is_running_away = true
	var sm = get_node_or_null("/root/SoundManager")
	if sm and sm.has_method("play"):
		sm.play("trap")
	
	if runaway_tween_x and runaway_tween_x.is_valid():
		runaway_tween_x.kill()
	if runaway_tween_y and runaway_tween_y.is_valid():
		runaway_tween_y.kill()
		
	var target_x := initial_x + runaway_offset_x
	var orig_y := initial_y
	var peak_y := orig_y - 130.0 # O'yinchi ustidan baland sakrab narigi tomonga o'tadi
	
	runaway_tween_x = create_tween()
	runaway_tween_x.tween_property(self, "global_position:x", target_x, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	runaway_tween_y = create_tween()
	runaway_tween_y.tween_property(self, "global_position:y", peak_y, 0.19).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	runaway_tween_y.chain().tween_property(self, "global_position:y", orig_y, 0.19).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	runaway_tween_x.finished.connect(func():
		is_running_away = false
		reset_cooldown = 0.25
	)

func _process(delta: float) -> void:
	if reset_cooldown > 0.0:
		reset_cooldown -= delta
		if reset_cooldown <= 0.0 and not is_sinking:
			for body in get_overlapping_bodies():
				_on_body_entered(body)
				if is_sinking:
					break
	if not is_sinking:
		pulse_time += delta
		queue_redraw()

func _draw() -> void:
	var is_winter := false
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("is_winter_theme"):
		is_winter = gm.is_winter_theme()

	var w := door_size.x
	var h := door_size.y
	var half_w := w / 2.0
	var post_w := 5.0
	var lintel_h := 5.5
	var frame_col := Color(0.85, 0.95, 1.0, 1.0) if is_winter else Color(1.0, 1.0, 1.0, 1.0)
	
	# Pol sathidan (y = 0) yuqorida qolgan eshik qismi
	# sink_amount 0.0 dan h gacha oshadi va eshik to'g'ridan-to'g'ri pol ichiga kirib boradi.
	# y = 0 dan pastga HECH NARSA chizilmaydi, natijada eshik yer/pol tagiga to'liq kiradi!
	var top_y := -h + sink_amount
	
	if top_y < 0.0:
		var lintel_bottom := minf(0.0, top_y + lintel_h)
		var post_h := -lintel_bottom
		
		# 1. Ichki qora bo'shliq va Ustunlar (faqat pol sathidan tepada qolgan qismi)
		if post_h > 0.0:
			var inner_rect := Rect2(-half_w + post_w, lintel_bottom, w - post_w * 2.0, post_h)
			draw_rect(inner_rect, Color("#000000"), true)
			
			# Chap va o'ng ustunlar
			draw_rect(Rect2(-half_w, lintel_bottom, post_w, post_h), frame_col, true)
			draw_rect(Rect2(half_w - post_w, lintel_bottom, post_w, post_h), frame_col, true)
			
			# Ichki burchak faskalari (┌ ┐)
			if post_h >= 4.0:
				var chamfer_pts_left := PackedVector2Array([
					Vector2(-half_w + post_w, lintel_bottom),
					Vector2(-half_w + post_w + 4.0, lintel_bottom),
					Vector2(-half_w + post_w, lintel_bottom + 4.0)
				])
				draw_colored_polygon(chamfer_pts_left, frame_col)
				var chamfer_pts_right := PackedVector2Array([
					Vector2(half_w - post_w, lintel_bottom),
					Vector2(half_w - post_w - 4.0, lintel_bottom),
					Vector2(half_w - post_w, lintel_bottom + 4.0)
				])
				draw_colored_polygon(chamfer_pts_right, frame_col)
		
		# 2. Yuqori to'sin (Lintel)
		var lintel_visible_h := lintel_bottom - top_y
		if lintel_visible_h > 0.0:
			draw_rect(Rect2(-half_w, top_y, w, lintel_visible_h), frame_col, true)
		
		# 3. Yuqori qopqoq hoshiyasi (Cornice)
		var cornice_visible_h := minf(2.5, -top_y)
		if cornice_visible_h > 0.0:
			draw_rect(Rect2(-half_w - 2.0, top_y, w + 4.0, cornice_visible_h), frame_col, true)
	
	# 4. Pol sathidagi chegara chiziq
	if sink_amount < h:
		draw_line(Vector2(-half_w - 2.0, 0.0), Vector2(half_w + 2.0, 0.0), frame_col, 2.0)
	
	# 5. Tepada suzib turuvchi oq uchburchak indikator (▼)
	if show_triangle and sink_amount <= 0.01:
		var tri_y := -(h + 8.0) + sin(pulse_time * 3.5) * 2.5
		var tri_w := 12.0
		var tri_h := 8.0
		var tri_pts := PackedVector2Array([
			Vector2(-tri_w / 2.0, tri_y),
			Vector2(tri_w / 2.0, tri_y),
			Vector2(0.0, tri_y + tri_h)
		])
		draw_colored_polygon(tri_pts, frame_col)

func _on_body_entered(body: Node2D) -> void:
	if reset_cooldown > 0.0 or is_running_away:
		return
	if runaway_enabled and not has_run_away:
		_run_away()
		return
	if body is PlayerController and not is_sinking:
		is_sinking = true
		monitoring = false
		var sm = get_node_or_null("/root/SoundManager")
		if sm and sm.has_method("play"):
			sm.play("win")
		body.enter_door(global_position + Vector2(0.0, -20.0))
		show_triangle = false
		var gm = get_node_or_null("/root/GameManager")
		if gm:
			gm.is_level_running = false # Level shu ondayoq yutildi
		queue_redraw()

		# Qisqa pauzasiz to'g'ridan-to'g'ri tushishni boshlash (xavfsizroq)
		_sink_door()

func _sink_door() -> void:
	var tween := create_tween()
	tween.tween_method(func(val: float):
		sink_amount = val
		queue_redraw()
	, 0.0, door_size.y + 2.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	await tween.finished
	if not is_instance_valid(self) or not is_inside_tree():
		return
	visible = false
	door_sunk_completely.emit()
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("complete_level"):
		gm.complete_level()

func reset_door() -> void:
	if runaway_tween_x and runaway_tween_x.is_valid():
		runaway_tween_x.kill()
	if runaway_tween_y and runaway_tween_y.is_valid():
		runaway_tween_y.kill()
	is_running_away = false
	is_sinking = false
	sink_amount = 0.0
	show_triangle = true
	global_position = Vector2(initial_x, initial_y)
	has_run_away = false
	modulate.a = 1.0
	visible = true
	reset_cooldown = 0.40
	monitoring = true
	queue_redraw()
