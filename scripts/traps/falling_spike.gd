extends Area2D
class_name FallingSpikeTrap

@export var trigger_distance: float = 340.0
@export var trigger_distance_x: float = 54.0
@export var fall_speed: float = 750.0
@export var shake_duration: float = 0.04

var is_triggered: bool = false
var is_falling: bool = false
var velocity_y: float = 0.0
var shake_timer: float = 0.0
var original_pos: Vector2

@onready var col_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("traps")
	original_pos = global_position
	# Kutilmagan, ammo adolatli qochish imkoniyatini beruvchi ogohlantirish (0.18s)
	shake_duration = clampf(shake_duration, 0.16, 0.22)
	visible = false
	if col_shape:
		col_shape.set_deferred("disabled", true)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	if not is_triggered:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null and is_instance_valid(player):
			if not ("is_dead" in player and player.is_dead) and not ("is_invulnerable" in player and player.is_invulnerable):
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
		
		# Harakat paytida to'g'ridan-to'g'ri o'yinchi bilan to'qnashuvni tekshirish
		for b in get_overlapping_bodies():
			_kill_player(b)
		var p := get_tree().get_first_node_in_group("player") as Node2D
		if p != null and is_instance_valid(p):
			if not ("is_dead" in p and p.is_dead) and not ("is_invulnerable" in p and p.is_invulnerable):
				var px: float = p.global_position.x
				var py: float = p.global_position.y
				if absf(px - global_position.x) < 18.0:
					if py >= (global_position.y - 12.0) and py <= (global_position.y + 36.0):
						_kill_player(p)
		
		# Pastga tushib ekrandan chiqsa yoki qattiq polga ursa
		if global_position.y > 600.0:
			is_falling = false
			visible = false
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

	if is_winter:
		draw_colored_polygon(pts, Color(0.22, 0.74, 0.97, 0.92))
		draw_line(Vector2(-16, 1), Vector2(16, 1), Color("#ffffff"), 3.0)
		var inner_pts := PackedVector2Array([
			Vector2(-7, 3),
			Vector2(7, 3),
			Vector2(0, 26)
		])
		draw_colored_polygon(inner_pts, Color("#e0f2fe"))
		draw_line(Vector2(-16, 0), Vector2(0, 32), Color("#ffffff"), 1.5)
		draw_line(Vector2(16, 0), Vector2(0, 32), Color("#0284c7"), 1.2)
	else:
		draw_colored_polygon(pts, Color("#1e1b26"))
		var inner_pts := PackedVector2Array([
			Vector2(-7, 2),
			Vector2(7, 2),
			Vector2(0, 24)
		])
		draw_colored_polygon(inner_pts, Color("#2a2536"))
		draw_line(Vector2(-16, 0), Vector2(0, 32), Color("#ffffff"), 1.4)
		draw_line(Vector2(16, 0), Vector2(0, 32), Color("#5c566a"), 1.2)
		draw_circle(Vector2(0, 32), 1.4, Color.WHITE)

func _on_body_entered(body: Node2D) -> void:
	_kill_player(body)
	if is_falling and body is StaticBody2D:
		var sm = get_node_or_null("/root/SoundManager")
		if sm and sm.has_method("play"):
			sm.play("trap")
		is_falling = false
		visible = false
		if col_shape:
			col_shape.set_deferred("disabled", true)

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
	velocity_y = 0.0
	shake_timer = 0.0
	visible = false
	if col_shape:
		col_shape.set_deferred("disabled", true)
