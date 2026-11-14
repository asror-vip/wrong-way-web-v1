extends Area2D
class_name SpikesTrap

@export var spike_size: Vector2 = Vector2(32, 32)

@onready var col_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("traps")
	if col_shape:
		col_shape.shape = RectangleShape2D.new()
		col_shape.shape.size = Vector2(spike_size.x - 4.0, spike_size.y - 4.0)
		col_shape.position = Vector2(spike_size.x / 2.0, (spike_size.y + 4.0) / 2.0)
	body_entered.connect(_on_body_entered)
	queue_redraw()

func _draw() -> void:
	var ch: int = 1
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("get_current_chapter"):
		ch = gm.get_current_chapter()

	var w := spike_size.x
	var h := spike_size.y

	var teeth_col := Color("#1c1a22")
	var stroke_col := Color("#1c1a22", 0.0)
	if ch == 2:
		teeth_col = Color(0.22, 0.74, 0.97, 0.90)
		stroke_col = Color("#ffffff")
	elif ch == 3:
		teeth_col = Color("#14532d")
		stroke_col = Color("#4ade80") # Ochiq neon yashil chiziq
	elif ch == 4:
		teeth_col = Color("#78350f")
		stroke_col = Color("#fcd34d") # Qum/tillarang chiziq
	elif ch == 5:
		teeth_col = Color("#450a0a")
		stroke_col = Color("#f97316") # Yonuvchi to'q sariq chiziq

	var count := int(maxf(1.0, roundf(w / 16.0)))
	var step := w / float(count)
	for i in range(count):
		var x0 := float(i) * step
		var x1 := x0 + step / 2.0
		var x2 := x0 + step

		var tri := PackedVector2Array([
			Vector2(x0, h),
			Vector2(x1, 0.0),
			Vector2(x2, h)
		])
		draw_colored_polygon(tri, teeth_col)
		if stroke_col.a > 0.0:
			draw_polyline(tri, stroke_col, 1.2)

func _on_body_entered(body: Node2D) -> void:
	if body is PlayerController or body.is_in_group("player"):
		if "is_dead" in body and body.is_dead:
			return
		if "is_invulnerable" in body and body.is_invulnerable:
			return
		if body.has_method("kill"):
			body.kill()

func reset_trap() -> void:
	queue_redraw()
