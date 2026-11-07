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
	start_pos = position
	if col_shape:
		col_shape.shape = RectangleShape2D.new()
		col_shape.shape.size = door_size
		col_shape.position = Vector2(0, -door_size.y / 2.0)
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

func _run_away(_player: Node2D) -> void:
	is_triggered = true
	var sm = get_node_or_null("/root/SoundManager")
	if sm and sm.has_method("play"):
		sm.play("trap")
	
	# Eshik pastga pol ichiga tushib yo'qoladi (Falls down and vanishes)
	runaway_tween = create_tween()
	runaway_tween.tween_property(self, "position:y", start_pos.y - 3.0, 0.05)
	runaway_tween.tween_property(self, "position:y", start_pos.y + 120.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	runaway_tween.tween_callback(func():
		visible = false
		if col_shape:
			col_shape.disabled = true
	)

func _draw() -> void:
	# Haqiqiy ExitDoor bilan 100% bir xil vizual ko'rinish
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

