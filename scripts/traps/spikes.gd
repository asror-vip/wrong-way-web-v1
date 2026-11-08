extends Area2D
class_name SpikesTrap

@export var spike_size: Vector2 = Vector2(32, 32)

@onready var col_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("traps")
	if col_shape:
		col_shape.shape = RectangleShape2D.new()
		col_shape.shape.size = Vector2(spike_size.x - 4.0, spike_size.y - 6.0)
		col_shape.position = Vector2(spike_size.x / 2.0, (spike_size.y + 6.0) / 2.0)
	body_entered.connect(_on_body_entered)
	queue_redraw()

func _draw() -> void:
	var is_winter := false
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("is_winter_theme"):
		is_winter = gm.is_winter_theme()

	var w := spike_size.x
	var h := spike_size.y

	if is_winter:
		# Muz tikanlar bazasi (qorli asos)
		draw_rect(Rect2(0, h - 4.0, w, 4.0), Color("#1e293b"), true)
		draw_rect(Rect2(0, h - 4.0, w, 2.0), Color("#f1f5f9"), true)
		
		# Crystalline ice spikes (o'tkir muz nayzalar)
		var count := 2
		var step := w / float(count)
		for i in range(count):
			var x0 := float(i) * step
			var x1 := x0 + step / 2.0
			var x2 := x0 + step
			
			var tri := PackedVector2Array([
				Vector2(x0 + 1.0, h - 4.0),
				Vector2(x1, 2.0),
				Vector2(x2 - 1.0, h - 4.0)
			])
			# Shaffofroq muz kristall tusi (borderlarsiz)
			draw_colored_polygon(tri, Color(0.22, 0.74, 0.97, 0.90))
	else:
		# Yashirilmaydigan oddiy tikanlar (borderlarsiz sof poligon)
		draw_rect(Rect2(0, h - 4.0, w, 4.0), Color("#1c1a22"), true)
		draw_rect(Rect2(0, h - 4.0, w, 2.0), Color("#342f3a"), true)
		
		var count := int(maxf(1.0, w / 16.0))
		var step := w / float(count)
		for i in range(count):
			var x0 := float(i) * step
			var x1 := x0 + step / 2.0
			var x2 := x0 + step
			
			var tri := PackedVector2Array([
				Vector2(x0 + 1.0, h - 4.0),
				Vector2(x1, 2.0),
				Vector2(x2 - 1.0, h - 4.0)
			])
			# To'q po'lat asos (barcha tikanlar bilan bir xil, borderlarsiz)
			draw_colored_polygon(tri, Color("#1e1b26"))
			# Ichki qirra (facet)
			var inner_facet := PackedVector2Array([
				Vector2(x0 + 2.5, h - 4.0),
				Vector2(x1, 3.5),
				Vector2(x1 + 1.0, h - 4.0)
			])
			draw_colored_polygon(inner_facet, Color("#2a2536"))

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
