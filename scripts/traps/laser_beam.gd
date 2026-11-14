extends Area2D
class_name LaserBeamTrap

@export var beam_length: float = 160.0
@export var active_time: float = 1.6
@export var inactive_time: float = 1.4
@export var is_vertical: bool = true

var timer: float = 0.0
var is_active: bool = true
var pulse_phase: float = 0.0

@onready var col_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("traps")
	_update_shape()
	body_entered.connect(_on_body_entered)

func _update_shape() -> void:
	if not col_shape:
		return
	var rect_shape := RectangleShape2D.new()
	if is_vertical:
		rect_shape.size = Vector2(8, beam_length)
		col_shape.position = Vector2(0, beam_length / 2.0)
	else:
		rect_shape.size = Vector2(beam_length, 8)
		col_shape.position = Vector2(beam_length / 2.0, 0)
	col_shape.shape = rect_shape

func _physics_process(delta: float) -> void:
	timer += delta
	pulse_phase += delta * 10.0
	
	var cycle := active_time + inactive_time
	var current_t := fmod(timer, cycle)
	var new_active := (current_t < active_time)
	
	if new_active != is_active:
		is_active = new_active
		if col_shape:
			col_shape.set_deferred("disabled", not is_active)
		if is_active:
			var sm = get_node_or_null("/root/SoundManager")
			if sm and sm.has_method("play"):
				sm.play("trap")
			
	queue_redraw()

func _draw() -> void:
	var ch: int = 1
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("get_current_chapter"):
		ch = gm.get_current_chapter()

	var base_col := Color("#1e1b29")
	var inner_col := Color("#3f3f46")

	if ch == 2:
		base_col = Color("#0d131f")
		inner_col = Color("#1e293b")
	elif ch == 3:
		base_col = Color("#062319")
		inner_col = Color("#064e3b")
	elif ch == 4:
		base_col = Color("#291c14")
		inner_col = Color("#451a03")
	elif ch == 5:
		base_col = Color("#1a0505")
		inner_col = Color("#450a0a")

	# Emitter asosi (kichik metall blok)
	draw_circle(Vector2.ZERO, 9.0, base_col)
	draw_circle(Vector2.ZERO, 6.0, inner_col)
	
	var end_pt := Vector2(0, beam_length) if is_vertical else Vector2(beam_length, 0)
	
	if is_active:
		# Yorqin nur (Lazer chizig'i va Glow)
		var glow_w := 10.0 + sin(pulse_phase) * 2.0
		var laser_glow := Color(1.0, 0.2, 0.3, 0.35)
		var laser_core := Color(1.0, 0.4, 0.5, 0.8)
		var emitter_light := Color("#ef4444")

		# Boblarga qarab lazer ranglari (Masalan O'rmonda zaharli yashil, Qishda muzdek ko'k)
		if ch == 2:
			laser_glow = Color(0.2, 0.8, 1.0, 0.35)
			laser_core = Color(0.4, 0.9, 1.0, 0.8)
			emitter_light = Color("#0ea5e9")
		elif ch == 3:
			laser_glow = Color(0.3, 1.0, 0.3, 0.35)
			laser_core = Color(0.5, 1.0, 0.5, 0.8)
			emitter_light = Color("#22c55e")
		elif ch == 4:
			laser_glow = Color(1.0, 0.8, 0.2, 0.35)
			laser_core = Color(1.0, 0.9, 0.4, 0.8)
			emitter_light = Color("#eab308")

		draw_line(Vector2.ZERO, end_pt, laser_glow, glow_w)
		draw_line(Vector2.ZERO, end_pt, laser_core, 4.0)
		draw_line(Vector2.ZERO, end_pt, Color(1.0, 1.0, 1.0, 0.95), 1.5)
		# Emitter nuri
		draw_circle(Vector2.ZERO, 4.0, emitter_light)
	else:
		# Ogohlantiruvchi xira nuqtali / nozik nur
		var idle_beam := Color(1.0, 0.2, 0.2, 0.15)
		var idle_dot := Color(0.6, 0.2, 0.2, 0.4)
		if ch == 2:
			idle_beam = Color(0.2, 0.8, 1.0, 0.15)
			idle_dot = Color(0.2, 0.6, 0.8, 0.4)
		elif ch == 3:
			idle_beam = Color(0.3, 1.0, 0.3, 0.15)
			idle_dot = Color(0.2, 0.6, 0.2, 0.4)
		elif ch == 4:
			idle_beam = Color(1.0, 0.8, 0.2, 0.15)
			idle_dot = Color(0.8, 0.6, 0.2, 0.4)

		draw_line(Vector2.ZERO, end_pt, idle_beam, 2.0)
		draw_circle(Vector2.ZERO, 3.0, idle_dot)

func _on_body_entered(body: Node2D) -> void:
	if is_active and (body is PlayerController or body.is_in_group("player")):
		if "is_dead" in body and body.is_dead:
			return
		if "is_invulnerable" in body and body.is_invulnerable:
			return
		if body.has_method("kill"):
			body.kill()

func reset_trap() -> void:
	timer = 0.0
	is_active = true
	if col_shape:
		col_shape.disabled = false

