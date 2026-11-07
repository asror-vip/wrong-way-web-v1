extends Area2D
class_name MovingSawTrap

@export var radius: float = 16.0 # 32px diametr
@export var patrol_distance: float = 64.0 # 2x katak
@export var patrol_speed: float = 120.0
@export var patrol_axis: Vector2 = Vector2.RIGHT
@export var trigger_distance: float = 0.0 # Agar > 0 bo'lsa, o'yinchi yaqinlashganda otilib chiqadi

var start_pos: Vector2
var patrol_t: float = 0.0
var rotation_angle: float = 0.0
var moving_forward: bool = true
var is_triggered: bool = false

@onready var col_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("traps")
	start_pos = global_position
	if col_shape:
		var circle := CircleShape2D.new()
		circle.radius = radius - 1.0
		col_shape.shape = circle
		col_shape.position = Vector2.ZERO
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	if trigger_distance > 0.0 and not is_triggered:
		if col_shape and not col_shape.disabled:
			col_shape.disabled = true
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null and is_instance_valid(player):
			if "is_dead" in player and player.is_dead:
				return
			var dx: float = player.global_position.x - global_position.x
			var should_trigger: bool = false
			# Agar arra o'ngga (orqadan quvuvchi) bo'lsa (patrol_axis.x > 0):
			# O'yinchi yetarlicha oldinga (dx >= trigger_distance) o'tganda orqadan chiqadi
			if patrol_axis.x > 0.1:
				if dx >= trigger_distance:
					should_trigger = true
			# Agar arra chapga (oldindan keluvchi) bo'lsa (patrol_axis.x < -0.1):
			# O'yinchi unga yetarlicha yaqinlashganda oldindan chiqadi
			elif patrol_axis.x < -0.1:
				if dx <= 0.0 and absf(dx) <= trigger_distance:
					should_trigger = true
			else:
				var dist: float = absf(dx)
				if dist < trigger_distance:
					should_trigger = true

			if should_trigger:
				is_triggered = true
				if col_shape:
					col_shape.disabled = false
				var sm = get_node_or_null("/root/SoundManager")
				if sm and sm.has_method("play"):
					sm.play("trap")
		return

	if col_shape and col_shape.disabled:
		col_shape.disabled = false

	rotation_angle += delta * 14.0
	
	if patrol_distance > 0.0:
		if moving_forward:
			patrol_t += (patrol_speed * delta) / patrol_distance
			if patrol_t >= 1.0:
				patrol_t = 1.0
				moving_forward = false
		else:
			patrol_t -= (patrol_speed * delta) / patrol_distance
			if patrol_t <= 0.0:
				patrol_t = 0.0
				moving_forward = true
		global_position = start_pos + patrol_axis.normalized() * (patrol_distance * patrol_t)
		
	queue_redraw()

func reset_trap() -> void:
	is_triggered = false
	patrol_t = 0.0
	moving_forward = true
	global_position = start_pos
	if trigger_distance > 0.0 and col_shape:
		col_shape.disabled = true
	queue_redraw()

func _draw() -> void:
	if trigger_distance > 0.0 and not is_triggered:
		return

	var is_winter := false
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("is_winter_theme"):
		is_winter = gm.is_winter_theme()

	var teeth_count := 8
	var outer_r := radius
	var inner_r := radius * 0.70
	
	var pts := PackedVector2Array()
	var step := (PI * 2.0) / float(teeth_count)
	
	for i in range(teeth_count):
		var a0 := rotation_angle + float(i) * step
		var a1 := a0 + step * 0.45
		var a2 := a0 + step * 0.80
		
		pts.append(Vector2(cos(a0), sin(a0)) * inner_r)
		pts.append(Vector2(cos(a1), sin(a1)) * outer_r)
		pts.append(Vector2(cos(a2), sin(a2)) * inner_r)
		
	if is_winter:
		draw_colored_polygon(pts, Color(0.22, 0.74, 0.97, 0.95))
		draw_polyline(pts, Color("#ffffff"), 1.2)
		draw_circle(Vector2.ZERO, inner_r * 0.85, Color("#0f172a"))
		draw_circle(Vector2.ZERO, inner_r * 0.65, Color("#0284c7"))
		draw_circle(Vector2.ZERO, 3.5, Color("#1e293b"))
		draw_circle(Vector2.ZERO, 1.5, Color("#e0f2fe"))
	else:
		draw_colored_polygon(pts, Color("#94a3b8"))
		draw_polyline(pts, Color("#f1f5f9"), 1.0)
		draw_circle(Vector2.ZERO, inner_r * 0.85, Color("#475569"))
		draw_circle(Vector2.ZERO, inner_r * 0.65, Color("#dc2626"))
		draw_circle(Vector2.ZERO, 3.5, Color("#0f172a"))
		draw_circle(Vector2.ZERO, 1.5, Color("#cbd5e1"))

func _on_body_entered(body: Node2D) -> void:
	if body is PlayerController or body.is_in_group("player"):
		if "is_dead" in body and body.is_dead:
			return
		if "is_invulnerable" in body and body.is_invulnerable:
			return
		if body.has_method("kill"):
			body.kill()
