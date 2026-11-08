extends Area2D
class_name Crusher

@export var crusher_size: Vector2 = Vector2(64, 64)
@export var target_y: float = 325.0
@export var trigger_distance: float = 64.0
@export var returns_up: bool = true
@export var wait_at_bottom: float = 0.7
@export var rise_speed: float = 140.0
@export var retrigger_delay: float = 0.8

enum State { IDLE, FALLING, WAITING_BOTTOM, RISING, COOLDOWN }
var state: State = State.IDLE

var initial_position: Vector2
var speed: float = 0.0
var timer: float = 0.0
var player_ref: Node2D = null
var has_crushed: bool = false

var is_triggered: bool:
	get: return state != State.IDLE
var is_falling: bool:
	get: return state == State.FALLING

@onready var col_shape: CollisionShape2D = get_node_or_null("CollisionShape2D")

func _ready() -> void:
	add_to_group("traps")
	initial_position = global_position
	if col_shape:
		col_shape.shape = RectangleShape2D.new()
		col_shape.shape.size = crusher_size + Vector2(0, 8)
		col_shape.position = (crusher_size + Vector2(0, 8)) / 2.0
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	match state:
		State.IDLE:
			if has_crushed:
				return
			if player_ref == null:
				player_ref = get_tree().get_first_node_in_group("player") as Node2D
			if player_ref != null and is_instance_valid(player_ref):
				if "is_dead" in player_ref and player_ref.is_dead:
					return
				var crusher_center_x := global_position.x + crusher_size.x / 2.0
				var player_center_x: float = player_ref.global_position.x
				if absf(player_center_x - crusher_center_x) < trigger_distance:
					state = State.FALLING
					speed = 0.0
					queue_redraw()
					var sm = get_node_or_null("/root/SoundManager")
					if sm and sm.has_method("play"):
						sm.play("trap")
		
		State.FALLING:
			speed += 3600.0 * delta
			global_position.y += speed * delta
			for b in get_overlapping_bodies():
				_on_body_entered(b)
			var p := get_tree().get_first_node_in_group("player") as Node2D
			if p != null and is_instance_valid(p):
				var p_dead: bool = "is_dead" in p and p.is_dead
				var p_invuln: bool = "is_invulnerable" in p and p.is_invulnerable
				if not p_dead and not p_invuln:
					var px: float = p.global_position.x
					var py: float = p.global_position.y
					if px + 8.0 >= global_position.x and px - 8.0 <= (global_position.x + crusher_size.x):
						if py >= global_position.y and py <= (global_position.y + crusher_size.y + 12.0):
							_on_body_entered(p)
			if global_position.y >= target_y:
				global_position.y = target_y
				var sm = get_node_or_null("/root/SaveManager")
				if sm == null or sm.shake_enabled:
					var gm = get_node_or_null("/root/GameManager")
					if gm and gm.has_signal("request_screen_shake"):
						gm.request_screen_shake.emit(8.0)
				if returns_up:
					state = State.WAITING_BOTTOM
					timer = wait_at_bottom
				else:
					has_crushed = true
					state = State.IDLE
					queue_redraw()
		
		State.WAITING_BOTTOM:
			timer -= delta
			if timer <= 0.0:
				state = State.RISING
		
		State.RISING:
			global_position.y -= rise_speed * delta
			if global_position.y <= initial_position.y:
				global_position.y = initial_position.y
				if retrigger_delay > 0.0:
					state = State.COOLDOWN
					timer = retrigger_delay
				else:
					state = State.IDLE
		
		State.COOLDOWN:
			timer -= delta
			if timer <= 0.0:
				state = State.IDLE

func _on_body_entered(body: Node2D) -> void:
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
	state = State.IDLE
	speed = 0.0
	timer = 0.0
	has_crushed = false
	global_position = initial_position
	queue_redraw()

func _draw() -> void:
	var is_winter := false
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("is_winter_theme"):
		is_winter = gm.is_winter_theme()

	var w := crusher_size.x
	var h := crusher_size.y

	# Zanjir (shiftgacha ko'tariluvchi asl temir zanjir)
	var chain_x := w / 2.0
	var link_spacing := 12.0
	var current_y := 0.0
	while current_y > -600.0:
		draw_rect(
			Rect2(chain_x - 3.0, current_y - 10.0, 6.0, 10.0),
			Color("#1a2230"),
			false,
			1.8
		)
		draw_line(
			Vector2(chain_x, current_y - 10.0),
			Vector2(chain_x, current_y - 12.0),
			Color("#2a3548"),
			1.5
		)
		current_y -= link_spacing

	# Zanjir qotirgich halqasi (crusher tepasida)
	draw_circle(Vector2(chain_x, 0), 5.0, Color("#262e3e"))
	draw_circle(Vector2(chain_x, 0), 2.5, Color("#0c0e14"))

	# Asosiy ezuvchi blok korpusi (borderlarsiz sof monolit to'rtburchak)
	var body_col := Color("#0d131f") if is_winter else Color("#1c1a22")
	draw_rect(Rect2(0, 0, w, h), body_col, true)

	if is_winter:
		# Crusher tepasidagi qor qatlami (borderlarsiz)
		draw_rect(Rect2(0, 0, w, 5.0), Color("#ffffff"), true)
		draw_rect(Rect2(0, 4.0, w, 1.5), Color("#94a3b8"), true)

	# Tishlar: shift tikanlari bilan bir xil sof rangli tishlar (borderlarsiz!)
	var teeth := int(round(w / 16.0))
	if teeth < 1:
		teeth = 4
	var tw := w / float(teeth)
	var tooth_len := 13.0
	for i in range(teeth):
		var p1 := Vector2(float(i) * tw, h)
		var p2 := Vector2((float(i) + 0.5) * tw, h + tooth_len)
		var p3 := Vector2(float(i + 1) * tw, h)
		if is_winter:
			draw_colored_polygon(
				PackedVector2Array([p1, p2, p3]),
				Color(0.22, 0.74, 0.97, 0.92)
			)
		else:
			draw_colored_polygon(
				PackedVector2Array([p1, p2, p3]),
				Color("#1c1a22")
			)
