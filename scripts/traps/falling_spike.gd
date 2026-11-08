extends Area2D
class_name FallingSpikeTrap

@export var trigger_distance: float = 340.0
@export var trigger_distance_x: float = 54.0
@export var fall_speed: float = 750.0
@export var shake_duration: float = 0.04

var is_triggered: bool = false
var is_falling: bool = false
var is_grounded: bool = false
var velocity_y: float = 0.0
var shake_timer: float = 0.0
var original_pos: Vector2

@onready var col_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("traps")
	original_pos = global_position
	# Kutilmagan, ammo adolatli qochish imkoniyatini beruvchi ogohlantirish (0.18s)
	shake_duration = clampf(shake_duration, 0.16, 0.22)
	visible = true
	is_grounded = false
	if col_shape:
		col_shape.set_deferred("disabled", false)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	if not is_inside_tree() or is_grounded:
		return
	if not is_triggered:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null and is_instance_valid(player):
			var dead: bool = "is_dead" in player and player.is_dead
			var inv: bool = "is_invulnerable" in player and player.is_invulnerable
			if not dead and not inv:
				var dx: float = abs(player.global_position.x - global_position.x)
				var dy: float = player.global_position.y - global_position.y
				var effective_dx := maxf(trigger_distance_x, 50.0)
				var effective_dy := maxf(trigger_distance, 350.0)
				if dx < effective_dx and dy > 0.0 and dy < effective_dy:
					_trigger()
	elif not is_falling:
		shake_timer -= delta
		global_position.x = original_pos.x + randf_range(-2.0, 2.0)
		if shake_timer <= 0.0:
			global_position.x = original_pos.x
			is_falling = true
			velocity_y = 350.0 # Boshlang'ich kutilmagan zarba tezligi
	else:
		velocity_y += 2400.0 * delta
		global_position.y += velocity_y * delta
		
		# Harakat paytida to'qnashuvlarni tekshirish
		for b in get_overlapping_bodies():
			_handle_overlap(b)
		var p := get_tree().get_first_node_in_group("player") as Node2D
		if p != null and is_instance_valid(p):
			var p_dead: bool = "is_dead" in p and p.is_dead
			var p_inv: bool = "is_invulnerable" in p and p.is_invulnerable
			if not p_dead and not p_inv:
				var px: float = p.global_position.x
				var py: float = p.global_position.y
				if absf(px - global_position.x) < 18.0:
					if py >= (global_position.y - 12.0) and py <= (global_position.y + 36.0):
						_kill_player(p)
		
		# Pastga tushib ekrandan chiqsa
		if global_position.y > 600.0:
			is_falling = false
			velocity_y = 0.0
			if col_shape:
				col_shape.set_deferred("disabled", true)

func _trigger() -> void:
	is_triggered = true
	shake_timer = clampf(shake_duration, 0.16, 0.22)
	visible = true
	if col_shape:
		col_shape.set_deferred("disabled", false)
	var sm = get_node_or_null("/root/SoundManager")
	if sm and sm.has_method("play"):
		sm.play("trap")

func _draw() -> void:
	var is_winter := false
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("is_winter_theme"):
		is_winter = gm.is_winter_theme()

	var pts := PackedVector2Array([
		Vector2(-16, 0),
		Vector2(16, 0),
		Vector2(0, 32)
	])

	# Borderlarsiz, sof rangli monolit tushuvchi tikan
	if is_winter:
		draw_colored_polygon(pts, Color(0.22, 0.74, 0.97, 0.92))
	else:
		draw_colored_polygon(pts, Color("#1c1a22"))

func _handle_overlap(body: Node2D) -> void:
	if not is_falling:
		return
	if body is PlayerController or body.is_in_group("player"):
		_kill_player(body)
	elif body is StaticBody2D and _is_ground_body(body):
		_ground_impact(body)

func _on_body_entered(body: Node2D) -> void:
	if not is_falling:
		return
	if body is PlayerController or body.is_in_group("player"):
		_kill_player(body)
	elif body is StaticBody2D and _is_ground_body(body):
		_ground_impact(body)

func _is_ground_body(body: StaticBody2D) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if body.name.to_lower().contains("ceiling"):
		return false
	# Shift platformasi va devorlarning yuqori qismini inkor qilish
	if body.global_position.y <= original_pos.y + 40.0:
		return false
	# Tikan uchi polning yuqori yuzasiga yetgandagina sanchilish
	if (global_position.y + 24.0) < body.global_position.y:
		return false
	return true

func _ground_impact(body: StaticBody2D) -> void:
	is_falling = false
	is_grounded = true
	velocity_y = 0.0
	visible = true
	# Yerga sanchilib qolish (uchi 6px yerga botadi)
	if body != null and is_instance_valid(body):
		global_position.y = body.global_position.y - 26.0
	if col_shape:
		col_shape.set_deferred("disabled", true)
	var sm = get_node_or_null("/root/SoundManager")
	if sm and sm.has_method("play"):
		sm.play("trap")

func _kill_player(body: Node2D) -> void:
	if body is PlayerController or body.is_in_group("player"):
		if "is_dead" in body and body.is_dead:
			return
		if "is_invulnerable" in body and body.is_invulnerable:
			return
		if body.has_method("kill"):
			body.kill()
		elif body.has_method("die"):
			body.die()

func reset_trap() -> void:
	global_position = original_pos
	is_triggered = false
	is_falling = false
	is_grounded = false
	velocity_y = 0.0
	shake_timer = 0.0
	visible = true
	if col_shape:
		col_shape.set_deferred("disabled", false)
	queue_redraw()
