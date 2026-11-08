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
	var is_winter := false
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("is_winter_theme"):
		is_winter = gm.is_winter_theme()

	var w := spike_size.x
	var h := spike_size.y

	if is_winter:
		# Muz tikanlar (pol bilan to'liq tekis, tagliksiz)
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
			draw_colored_polygon(tri, Color(0.22, 0.74, 0.97, 0.90))
	else:
		# Yashirilmaydigan oddiy tikanlar (pol bilan to'liq tekis, tagliksiz)
		var count := int(maxf(1.0, roundf(w / 16.0)))
		var step := w / float(count)
		for i in range(count):
			var x0 := float(i) * step
			var x1 := x0 + step / 2.0
			var x2 := x0 + step
			
			var tri := PackedVector2Array([
				Vector2(x0, h + 2.0),
				Vector2(x1, 0.0),
				Vector2(x2, h + 2.0)
			])
			# To'q po'lat asos (borderlarsiz, pol bilan to'liq tekis va bir xil rang)
			draw_colored_polygon(tri, Color("#1c1a22"))

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
