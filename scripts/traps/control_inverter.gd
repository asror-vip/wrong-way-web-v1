extends Area2D
class_name ControlInverter

# Level Devil Trap: Control Inverter (Teskari Boshqaruv Xiylasi)
# When the player touches this zone, left and right controls instantly flip!

@export var zone_size: Vector2 = Vector2(48, 64)

var pulse_time: float = 0.0
var is_triggered: bool = false

@onready var col_shape: CollisionShape2D = get_node_or_null("CollisionShape2D")

func _ready() -> void:
	add_to_group("traps")
	
	if col_shape:
		var rect := RectangleShape2D.new()
		rect.size = zone_size
		col_shape.shape = rect
		col_shape.position = zone_size / 2.0
		
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(delta: float) -> void:
	pulse_time += delta * 4.0
	queue_redraw()

func _on_body_entered(body: Node2D) -> void:
	if body is PlayerController or body.is_in_group("player"):
		if body.has_method("add_inverter_zone"):
			body.add_inverter_zone(self)
		elif "controls_inverted" in body:
			body.controls_inverted = true
		if not is_triggered:
			is_triggered = true
			SoundManager.play("trap")
			GameManager.request_screen_shake.emit(5.0)

func _on_body_exited(body: Node2D) -> void:
	if body is PlayerController or body.is_in_group("player"):
		if body.has_method("remove_inverter_zone"):
			body.remove_inverter_zone(self)
		elif "controls_inverted" in body:
			body.controls_inverted = false

func reset_trap() -> void:
	is_triggered = false
	var tree := get_tree()
	var player: Node2D = null
	if tree:
		player = tree.get_first_node_in_group("player") as Node2D
	if player:
		if player.has_method("remove_inverter_zone"):
			player.remove_inverter_zone(self)
		elif "controls_inverted" in player:
			player.controls_inverted = false
	if is_inside_tree():
		queue_redraw()

func _draw() -> void:
	var w := zone_size.x
	var h := zone_size.y
	var alpha := 0.35 + 0.15 * sin(pulse_time)
	
	# Binafsha teskari boshqaruv portali
	draw_rect(Rect2(0, 0, w, h), Color(0.65, 0.2, 0.9, alpha * 0.4), true)
	draw_rect(Rect2(0, 0, w, h), Color(0.75, 0.3, 1.0, alpha), false, 1.5)
	
	# Teskari strelka belgisi (<->)
	var mid_y := h * 0.5
	var arrow_col := Color(1.0, 1.0, 1.0, 0.8 + 0.2 * sin(pulse_time))
	draw_line(Vector2(w * 0.2, mid_y), Vector2(w * 0.8, mid_y), arrow_col, 2.0)
	# Chap strelka uchi
	draw_line(Vector2(w * 0.2, mid_y), Vector2(w * 0.35, mid_y - 6), arrow_col, 2.0)
	draw_line(Vector2(w * 0.2, mid_y), Vector2(w * 0.35, mid_y + 6), arrow_col, 2.0)
	# O'ng strelka uchi
	draw_line(Vector2(w * 0.8, mid_y), Vector2(w * 0.65, mid_y - 6), arrow_col, 2.0)
	draw_line(Vector2(w * 0.8, mid_y), Vector2(w * 0.65, mid_y + 6), arrow_col, 2.0)

