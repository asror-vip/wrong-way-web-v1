extends AnimatableBody2D
class_name CrashingPillar

# Wrong Way - Unexpected Event: Crashing Ceiling Pillar (Shift qoyasining qulashi)
# Suspended invisibly/silently at the ceiling.
# As the player approaches, it suddenly breaks off and SLAMS into the ground!

@export var pillar_size: Vector2 = Vector2(50, 200)
@export var trigger_distance: float = 160.0
@export var crash_speed: float = 1200.0

var is_triggered: bool = false
var is_grounded: bool = false
var original_pos: Vector2
var crash_velocity: float = 0.0

@onready var col_shape: CollisionShape2D = $CollisionShape2D
@onready var kill_area: Area2D = $KillArea

func _ready() -> void:
	add_to_group("traps")
	original_pos = position
	_update_shapes()
	
	if kill_area:
		kill_area.body_entered.connect(_on_kill_entered)

func _update_shapes() -> void:
	if col_shape:
		var rect := RectangleShape2D.new()
		rect.size = pillar_size
		col_shape.shape = rect
		col_shape.position = pillar_size / 2.0
		
	if kill_area:
		var k_shape = kill_area.get_node_or_null("CollisionShape2D")
		if k_shape:
			var k_rect := RectangleShape2D.new()
			# Ustun pastki zarba qismi
			k_rect.size = Vector2(pillar_size.x - 4.0, 16.0)
			k_shape.shape = k_rect
			k_shape.position = Vector2(pillar_size.x / 2.0, pillar_size.y - 8.0)

func _physics_process(delta: float) -> void:
	if not is_triggered:
		_check_trigger()
		return
		
	if not is_grounded:
		crash_velocity += 2400.0 * delta
		position.y += crash_velocity * delta
		
		if kill_area:
			for b in kill_area.get_overlapping_bodies():
				_on_kill_entered(b)
		
		# Polga urilish (yerni topsin)
		# Qattiq 190.0 o'rniga parametr orqali
		var drop_dist = 190.0
		if "drop_distance" in self:
			drop_dist = float(self.get("drop_distance"))
		elif "platform_size" in self:
			drop_dist = float(self.get("platform_size").y)
		else:
			drop_dist = maxf(190.0, 500.0 - original_pos.y)

		if position.y >= original_pos.y + drop_dist:
			position.y = original_pos.y + drop_dist
			is_grounded = true
			crash_velocity = 0.0
			SoundManager.play("trap")
			GameManager.request_screen_shake.emit(14.0)
			if kill_area:
				kill_area.set_deferred("monitoring", false)
			queue_redraw()

func _check_trigger() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	var px = player.global_position.x
	var my_x = global_position.x + pillar_size.x / 2.0
	
	if absf(px - my_x) <= trigger_distance:
		trigger_crash()

func trigger_crash() -> void:
	if is_triggered:
		return
	is_triggered = true
	SoundManager.play("click")
	GameManager.request_screen_shake.emit(4.0)
	
	# Qisqa tebranish (ogohlantiruvchi yorilish)
	var tw := create_tween()
	tw.tween_property(self, "position:x", original_pos.x - 3.0, 0.05)
	tw.tween_property(self, "position:x", original_pos.x + 3.0, 0.05)
	tw.tween_property(self, "position:x", original_pos.x, 0.04)

func _on_kill_entered(body: Node2D) -> void:
	if not is_grounded and (body is PlayerController or body.is_in_group("player")):
		if body.has_method("kill"):
			body.kill()
		elif body.has_method("die"):
			body.die()

func reset_trap() -> void:
	is_triggered = false
	is_grounded = false
	crash_velocity = 0.0
	position = original_pos
	if kill_area:
		kill_area.set_deferred("monitoring", true)
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(0, 0, pillar_size.x, pillar_size.y)
	# Asosiy quyuq tosh ustun
	draw_rect(rect, Color(0.07, 0.09, 0.14, 1.0))
	# Yon hoshiyalar
	draw_line(Vector2(0, 0), Vector2(0, pillar_size.y), Color(0.24, 0.32, 0.44, 0.8), 1.5)
	draw_line(Vector2(pillar_size.x, 0), Vector2(pillar_size.x, pillar_size.y), Color(0.24, 0.32, 0.44, 0.8), 1.5)
	
	# Tosh g'ishtlar relyefi
	for y in range(25, int(pillar_size.y), 35):
		draw_line(Vector2(0, y), Vector2(pillar_size.x, y), Color(0.04, 0.05, 0.08, 0.9), 1.2)
	
	# Pastki o'tkir tishli qoya qirrasi
	var pts := PackedVector2Array([
		Vector2(0, pillar_size.y),
		Vector2(12, pillar_size.y + 8),
		Vector2(25, pillar_size.y + 4),
		Vector2(38, pillar_size.y + 9),
		Vector2(pillar_size.x, pillar_size.y)
	])
	draw_colored_polygon(pts, Color(0.07, 0.09, 0.14, 1.0))
	draw_polyline(pts, Color(0.35, 0.45, 0.60, 0.85), 1.5)

