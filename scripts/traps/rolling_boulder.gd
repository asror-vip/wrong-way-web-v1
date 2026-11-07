extends CharacterBody2D
class_name RollingBoulder

# Wrong Way - Unexpected Event: Rolling Giant Boulder (Qoya Toshi)
# Iconic Limbo-style surprise: Triggers when the player walks past,
# rumbles with screen shake and rolls rapidly to chase or crush the player!

@export var boulder_radius: float = 28.0
@export var roll_speed: float = 380.0
@export var roll_direction: float = 1.0 # 1.0 = o'ngga, -1.0 = chapga
@export var trigger_distance: float = 260.0 # O'yinchi yaqinlashganda
@export var delay_before_roll: float = 0.7
@export var gravity: float = 1200.0

var is_triggered: bool = false
var is_rolling: bool = false
var has_fallen: bool = false
var roll_delay_timer: float = 0.0
var original_pos: Vector2
var roll_rotation: float = 0.0

@onready var col_shape: CollisionShape2D = $CollisionShape2D
@onready var kill_area: Area2D = $KillArea

func _ready() -> void:
	add_to_group("traps")
	original_pos = global_position
	
	if col_shape and col_shape.shape is CircleShape2D:
		col_shape.shape.radius = boulder_radius
		
	if kill_area:
		kill_area.body_entered.connect(_on_kill_entered)

func _physics_process(delta: float) -> void:
	if has_fallen:
		return

	# Qoyaga tushib ketsa
	if global_position.y > 650.0:
		has_fallen = true
		is_rolling = false
		velocity = Vector2.ZERO
		return

	if not is_triggered:
		_check_player_trigger()
		return

	if not is_rolling:
		roll_delay_timer -= delta
		global_position.x = original_pos.x + randf_range(-1.5, 1.5)
		if roll_delay_timer <= 0.0:
			global_position.x = original_pos.x
			is_rolling = true
		return
		
	# Gravitatsiya va aylanish
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0
		# Harakatlanish paytida vaqti-vaqti bilan yengil silkinish
		if randf() < 0.1:
			var gm = get_node_or_null("/root/GameManager")
			if gm and gm.has_signal("request_screen_shake"):
				gm.request_screen_shake.emit(3.0)
			
	velocity.x = roll_direction * roll_speed
	roll_rotation += roll_direction * (roll_speed / boulder_radius) * delta
	
	move_and_slide()
	queue_redraw()
	
	# Qoyaga tushib ketsa
	if global_position.y > 650.0:
		has_fallen = true
		is_rolling = false
		velocity = Vector2.ZERO
		return

func _check_player_trigger() -> void:
	var player = get_tree().get_first_node_in_group("player") as Node2D
	if not player or not is_instance_valid(player):
		return
	if "is_dead" in player and player.is_dead:
		return
		
	var dx: float = player.global_position.x - global_position.x
	var dy: float = absf(player.global_position.y - global_position.y)
	if dy > 120.0:
		return
		
	if roll_direction > 0:
		# Orqadan quvuvchi tosh: o'yinchi yetarlicha oldinga o'tganda
		if dx >= trigger_distance:
			trigger_boulder()
	else:
		# Oldindan keluvchi tosh: o'yinchi yaqinlashganda
		if dx <= 0.0 and absf(dx) <= trigger_distance:
			trigger_boulder()
		elif absf(dx) <= 60.0:
			trigger_boulder()

func trigger_boulder() -> void:
	if is_triggered:
		return
	is_triggered = true
	is_rolling = false
	roll_delay_timer = delay_before_roll
	var sm = get_node_or_null("/root/SoundManager")
	if sm and sm.has_method("play"):
		sm.play("trap")
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_signal("request_screen_shake"):
		gm.request_screen_shake.emit(10.0)

func _on_kill_entered(body: Node2D) -> void:
	if is_triggered and (body is PlayerController or body.is_in_group("player")):
		if body.has_method("kill"):
			body.kill()
		elif body.has_method("die"):
			body.die()

func reset_trap() -> void:
	has_fallen = false
	is_triggered = false
	is_rolling = false
	roll_delay_timer = 0.0
	global_position = original_pos
	velocity = Vector2.ZERO
	roll_rotation = 0.0
	queue_redraw()

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, roll_rotation, Vector2.ONE)
	
	# 1. Shar atrofidagi o'tkir metall-qizil tikanlar (Spikes around boulder)
	var num_spikes := 8
	for i in range(num_spikes):
		var ang := float(i) * (TAU / float(num_spikes))
		var dir := Vector2(cos(ang), sin(ang))
		var norm := Vector2(-dir.y, dir.x)
		var base1 := dir * (boulder_radius - 2.0) - norm * 6.0
		var base2 := dir * (boulder_radius - 2.0) + norm * 6.0
		var tip := dir * (boulder_radius + 12.0)
		draw_colored_polygon(PackedVector2Array([base1, tip, base2]), Color("#1e1b26"))
		draw_colored_polygon(PackedVector2Array([base1 + norm * 2.0, tip, base2]), Color("#2a2536"))
		draw_line(base1, tip, Color("#ffffff"), 1.4)
		draw_line(tip, base2, Color("#5c566a"), 1.2)
		draw_circle(tip, 1.5, Color.WHITE)

	# 2. Asosiy obsidian qoya toshi tanasi
	draw_circle(Vector2.ZERO, boulder_radius, Color(0.08, 0.10, 0.15, 1.0))
	# Qoya xoshiyasi
	draw_arc(Vector2.ZERO, boulder_radius, -PI, PI, 32, Color(0.35, 0.45, 0.60, 0.9), 2.0)
	
	# 3. Ichki tosh qatlamlari va yoriqlari (Limbo silhouette rock cracks)
	draw_line(Vector2(-16, -10), Vector2(4, -4), Color(0.03, 0.04, 0.07, 0.95), 2.5)
	draw_line(Vector2(4, -4), Vector2(16, -14), Color(0.03, 0.04, 0.07, 0.95), 2.0)
	draw_line(Vector2(4, -4), Vector2(0, 15), Color(0.03, 0.04, 0.07, 0.95), 2.2)
	draw_line(Vector2(0, 15), Vector2(-12, 18), Color(0.03, 0.04, 0.07, 0.95), 1.8)
	
	# Markaziy temir yadrosi
	draw_circle(Vector2.ZERO, 6.0, Color("#36435c"))
	draw_circle(Vector2.ZERO, 3.0, Color.WHITE)
	
	# Nozik tosh yorug'lik aksi
	var arc_col := Color(0.40, 0.50, 0.65, 0.40)
	draw_arc(Vector2.ZERO, boulder_radius - 4.0, -PI * 0.7, -PI * 0.2, 16, arc_col, 1.5)

