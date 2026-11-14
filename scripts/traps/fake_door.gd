extends Area2D
class_name FakeDoorTrap

@export var door_size: Vector2 = Vector2(44, 58)
@export var run_away_distance: float = 90.0

var start_pos: Vector2
var is_triggered: bool = false
var pulse_time: float = 0.0
var runaway_tween: Tween = null

@onready var col_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("traps")
	door_size = Vector2(44, 58)
	start_pos = position
	if col_shape:
		var rect := RectangleShape2D.new()
		rect.size = Vector2(32, 64)
		col_shape.shape = rect
		col_shape.position = Vector2(0, -32)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	pulse_time += delta
	queue_redraw()
	
	if not is_triggered:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null and is_instance_valid(player):
			if "is_dead" in player and player.is_dead:
				return
			var dist := global_position.distance_to(player.global_position)
			if dist < run_away_distance:
				_run_away(player)

func _run_away(player: Node2D) -> void:
	is_triggered = true

	# Ehtiyot qismi: Faqat player haqiqiy PlayerController bo'lsagina ishlaydi
	if not is_instance_valid(player) or not player.has_method("enter_door"):
		return

	var sm = get_node_or_null("/root/SoundManager")
	if sm and sm.has_method("play"):
		sm.play("win") # O'yinchini ishontirish uchun "Win" (Yutuq) musiqasi!

	# 1. Pleyerni soxta eshik ichiga kirgandek yutadi
	player.enter_door(global_position)
	
	# 2. Qisqa vaqt o'tgach troll (o'lim va spawn ga qaytarish) bo'ladi
	var tw := create_tween()
	tw.tween_interval(1.1)
	tw.tween_callback(func():
		if sm and sm.has_method("play"):
			sm.play("die") # Va ustidan kulgandek o'lim ovozi

		var gm = get_node_or_null("/root/GameManager")
		if gm and gm.has_signal("request_screen_shake"):
			gm.request_screen_shake.emit(8.0)

		if is_instance_valid(player) and player.has_method("respawn"):
			player.respawn(player.spawn_position)
	)

func _draw() -> void:
	# Haqiqiy ExitDoor bilan 100% bir xil vizual ko'rinish
	var ch: int = 1
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("get_current_chapter"):
		ch = gm.get_current_chapter()

	var w := door_size.x
	var h := door_size.y
	var half_w := w / 2.0
	var post_w := 5.0
	var lintel_h := 5.5
	var frame_col := Color(1.0, 1.0, 1.0, 1.0)
	if ch == 2: frame_col = Color(0.85, 0.95, 1.0, 1.0)
	elif ch == 3: frame_col = Color(0.75, 1.0, 0.85, 1.0)
	elif ch == 4: frame_col = Color(1.0, 0.9, 0.7, 1.0)
	elif ch == 5: frame_col = Color(1.0, 0.7, 0.7, 1.0)
	
	var top_y := -h
	var lintel_bottom := top_y + lintel_h
	var post_h := -lintel_bottom
	
	# 1. Ichki qora portal va ustunlar
	if post_h > 0.0:
		var inner_rect := Rect2(-half_w + post_w, lintel_bottom, w - post_w * 2.0, post_h)
		draw_rect(inner_rect, Color("#000000"), true)
		
		# Chap va o'ng ustunlar
		draw_rect(Rect2(-half_w, lintel_bottom, post_w, post_h), frame_col, true)
		draw_rect(Rect2(half_w - post_w, lintel_bottom, post_w, post_h), frame_col, true)
		
		# Ichki burchak faskalari
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
	draw_rect(Rect2(-half_w - 2.0, top_y, w + 4.0, 2.5), frame_col, true)
	
	# 4. Pol sathidagi chegara chiziq
	draw_line(Vector2(-half_w - 2.0, 0.0), Vector2(half_w + 2.0, 0.0), frame_col, 2.0)
	
	# 5. Tepada suzib turuvchi oq uchburchak indikator (▼)
	var t: float = Time.get_ticks_msec() / 1000.0
	var tri_y := -(h + 8.0) + sin(t * 3.5) * 2.5
	var tri_w := 12.0
	var tri_h := 8.0
	var tri_pts := PackedVector2Array([
		Vector2(-tri_w / 2.0, tri_y),
		Vector2(tri_w / 2.0, tri_y),
		Vector2(0.0, tri_y + tri_h)
	])
	draw_colored_polygon(tri_pts, frame_col)

func _on_body_entered(body: Node2D) -> void:
	if body is PlayerController or body.is_in_group("player"):
		if body.has_method("kill"):
			body.kill()

func reset_trap() -> void:
	if runaway_tween and runaway_tween.is_valid():
		runaway_tween.kill()
	position = start_pos
	rotation = 0.0
	is_triggered = false
	visible = true
	if col_shape:
		col_shape.disabled = false

