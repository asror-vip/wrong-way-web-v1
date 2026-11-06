extends Area2D
class_name PopUpSpikesTrap

@export var spike_width: float = 32.0
@export var max_spike_height: float = 32.0
@export var trigger_distance: float = 85.0
@export var warning_time: float = 0.0
@export var is_timer_mode: bool = false
@export var cycle_time: float = 2.4

var current_height: float = 0.0
var is_triggered: bool = false
var is_active: bool = false
var timer: float = 0.0
var warning_timer: float = 0.0

@onready var col_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("traps")
	# Level sahnalaridagi eski kechikishlarni (0.3s-0.7s) tozalaymiz, kutilmaganda darhol otilishi shart
	warning_time = minf(warning_time, 0.02)
	if col_shape:
		var rect := RectangleShape2D.new()
		rect.size = Vector2(spike_width, max_spike_height)
		col_shape.shape = rect
		col_shape.position = Vector2(spike_width / 2.0, -max_spike_height / 2.0)
		col_shape.disabled = true
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	if is_timer_mode:
		timer += delta
		var phase := fmod(timer, cycle_time)
		if phase < cycle_time * 0.5:
			current_height = move_toward(current_height, max_spike_height, delta * 500.0)
			is_active = current_height > (max_spike_height * 0.3)
		else:
			current_height = move_toward(current_height, 0.0, delta * 300.0)
			is_active = current_height > (max_spike_height * 0.3)
	else:
		if not is_triggered:
			var player := get_tree().get_first_node_in_group("player") as Node2D
			if player != null and is_instance_valid(player):
				if not ("is_dead" in player and player.is_dead) and not ("is_invulnerable" in player and player.is_invulnerable):
					var center_x := global_position.x + spike_width / 2.0
					var dx: float = abs(player.global_position.x - center_x)
					var dy: float = abs(player.global_position.y - global_position.y)
					var effective_trigger := maxf(trigger_distance, spike_width / 2.0 + 20.0)
					if dx < effective_trigger and dy < 85.0:
						var is_direct_step := dx <= (spike_width / 2.0 + 16.0)
						_trigger(is_direct_step)
		elif warning_timer > 0.0:
			warning_timer -= delta
		else:
			# Kutilmaganda yashindek tez otilib chiqish (1200 px/s - atigi 0.025 soniyada to'liq ko'tariladi)
			current_height = move_toward(current_height, max_spike_height, delta * 1200.0)
			is_active = current_height > 4.0
			
	if col_shape:
		col_shape.disabled = not is_active
		if is_active:
			var rect := col_shape.shape as RectangleShape2D
			if rect:
				var hit_h := maxf(current_height - 2.0, 4.0)
				rect.size = Vector2(spike_width, hit_h)
				col_shape.position = Vector2(spike_width / 2.0, -hit_h / 2.0)
				
	# Faol holatda o'yinchi tekshiruvi (area ichidagi yoki bevosita ustiga tushgan qahramon)
	if is_active:
		for b in get_overlapping_bodies():
			_kill_player(b)
		var p := get_tree().get_first_node_in_group("player") as Node2D
		if p != null and is_instance_valid(p):
			if not ("is_dead" in p and p.is_dead) and not ("is_invulnerable" in p and p.is_invulnerable):
				var px: float = p.global_position.x
				var py: float = p.global_position.y
				if px + 10.0 >= global_position.x and px - 10.0 <= global_position.x + spike_width:
					if py >= (global_position.y - current_height - 4.0) and py <= (global_position.y + 16.0):
						_kill_player(p)

	queue_redraw()

func _trigger(instant: bool = false) -> void:
	is_triggered = true
	warning_timer = 0.0 if instant else minf(warning_time, 0.02)
	var sm = get_node_or_null("/root/SoundManager")
	if sm and sm.has_method("play"):
		sm.play("trap")

func _draw() -> void:
	if current_height <= 1.0:
		return

	var is_winter := false
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("is_winter_theme"):
		is_winter = gm.is_winter_theme()
		
	var w := spike_width
	var count := int(maxf(1.0, w / 16.0))
	var step := w / float(count)
	
	for i in range(count):
		var sx0 := float(i) * step
		var sx1 := sx0 + step / 2.0
		var sx2 := sx0 + step
		
		var tri := PackedVector2Array([
			Vector2(sx0 + 2.0, 0.0),
			Vector2(sx1, -current_height),
			Vector2(sx2 - 2.0, 0.0)
		])
		if is_winter:
			draw_colored_polygon(tri, Color(0.22, 0.74, 0.97, 0.90))
			draw_line(Vector2(sx0 + 2.0, 0.0), Vector2(sx1, -current_height), Color("#ffffff"), 1.2)
			draw_line(Vector2(sx1, -current_height), Vector2(sx2 - 2.0, 0.0), Color("#7dd3fc"), 1.2)
		else:
			draw_colored_polygon(tri, Color("#1e1b26"))
			var inner_facet := PackedVector2Array([
				Vector2(sx0 + 2.5, 0.0),
				Vector2(sx1, -current_height + 2.0),
				Vector2(sx1 + 1.0, 0.0)
			])
			draw_colored_polygon(inner_facet, Color("#2a2536"))
			draw_line(Vector2(sx0 + 2.0, 0.0), Vector2(sx1, -current_height), Color("#ffffff"), 1.4)
			draw_line(Vector2(sx1, -current_height), Vector2(sx2 - 2.0, 0.0), Color("#5c566a"), 1.2)
			draw_circle(Vector2(sx1, -current_height), 1.4, Color.WHITE)

func _on_body_entered(body: Node2D) -> void:
	if is_active:
		_kill_player(body)

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
	current_height = 0.0
	is_triggered = false
	is_active = false
	timer = 0.0
	warning_timer = 0.0
	if col_shape:
		col_shape.disabled = true
