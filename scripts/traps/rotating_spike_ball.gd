extends Area2D
class_name RotatingSpikeBallTrap

@export var chain_length: float = 64.0
@export var rotation_speed: float = 2.2
@export var ball_radius: float = 16.0
@export var is_pendulum: bool = false
@export var pendulum_arc_deg: float = 75.0
@export var start_angle_deg: float = 0.0

var current_angle: float = 0.0
var pendulum_time: float = 0.0
var ball_offset: Vector2 = Vector2.ZERO

@onready var col_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("traps")
	current_angle = deg_to_rad(start_angle_deg)
	_update_ball_position()
	if col_shape:
		var circle := CircleShape2D.new()
		circle.radius = ball_radius + 4.0 # Tikanlar uchini ham hisobga oladi
		col_shape.shape = circle
		col_shape.position = ball_offset
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	if is_pendulum:
		pendulum_time += delta * rotation_speed
		var base_rad := deg_to_rad(start_angle_deg)
		var max_arc := deg_to_rad(pendulum_arc_deg)
		current_angle = base_rad + sin(pendulum_time) * max_arc
	else:
		current_angle += rotation_speed * delta
		
	_update_ball_position()
	if col_shape:
		col_shape.position = ball_offset
	queue_redraw()

func _update_ball_position() -> void:
	ball_offset = Vector2(cos(current_angle), sin(current_angle)) * chain_length

func _draw() -> void:
	# 1. Markaziy karkas (Anchor bracket)
	draw_circle(Vector2.ZERO, 8.0, Color("#1e1b29"))
	draw_circle(Vector2.ZERO, 5.0, Color("#475569"))
	draw_circle(Vector2.ZERO, 2.5, Color("#94a3b8"))
	
	# 2. Temir zanjir (Chain links)
	var links_count := maxi(2, int(chain_length / 14.0))
	for i in range(1, links_count):
		var t := float(i) / float(links_count)
		var lpos := ball_offset * t
		draw_circle(lpos, 4.0, Color("#334155"))
		draw_circle(lpos, 2.0, Color("#64748b"))
	draw_line(Vector2.ZERO, ball_offset, Color("#1e293b"), 2.5)
	
	# 3. Tikanli shar (Spiked Ball)
	_draw_spiked_ball(ball_offset)

func _draw_spiked_ball(pos: Vector2) -> void:
	var is_winter := false
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("is_winter_theme"):
		is_winter = gm.is_winter_theme()

	var spikes_count := 8
	var core_radius := 11.0
	var spike_len := 5.0 # core + spike = 16.0px radius (32px diameter)
	var step := (PI * 2.0) / float(spikes_count)
	
	# Konus tikanlar: qishda muz kristallari
	for i in range(spikes_count):
		var ang := current_angle + float(i) * step
		var tip := pos + Vector2(cos(ang), sin(ang)) * (core_radius + spike_len)
		var left_pt := pos + Vector2(cos(ang - 0.25), sin(ang - 0.25)) * core_radius
		var right_pt := pos + Vector2(cos(ang + 0.25), sin(ang + 0.25)) * core_radius
		
		var spike_poly := PackedVector2Array([left_pt, tip, right_pt])
		if is_winter:
			draw_colored_polygon(spike_poly, Color(0.22, 0.74, 0.97, 0.92))
		else:
			draw_colored_polygon(spike_poly, Color("#1e1b26"))
		
	# Asosiy shar
	var base_col := Color("#0f172a") if is_winter else Color("#18181b")
	draw_circle(pos, core_radius, base_col)
	draw_circle(pos, core_radius * 0.85, Color("#1e293b") if is_winter else Color("#27272a"))
	
	# Yaltirash (Highlight)
	draw_circle(pos + Vector2(-3.0, -3.0), core_radius * 0.35, Color("#38bdf8") if is_winter else Color("#52525b"))
	draw_circle(pos + Vector2(-4.0, -4.0), 2.0, Color("#ffffff") if is_winter else Color("#a1a1aa"))
	
	# Zanjir qulfi / o'rnatgich
	draw_circle(pos, 3.5, Color("#38bdf8") if is_winter else Color("#3f3f46"))

func _on_body_entered(body: Node2D) -> void:
	if body is PlayerController or body.is_in_group("player"):
		if body.has_method("kill"):
			body.kill()

func reset_trap() -> void:
	current_angle = deg_to_rad(start_angle_deg)
	pendulum_time = 0.0
	_update_ball_position()
	if col_shape:
		col_shape.position = ball_offset

