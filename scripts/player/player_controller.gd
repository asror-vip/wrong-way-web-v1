extends CharacterBody2D
class_name PlayerController

signal died
signal respawned
signal entered_exit

const SPEED: float = 280.0
const DASH_SPEED: float = 660.0
const DASH_DURATION: float = 0.16
const DASH_COOLDOWN: float = 0.40
const JUMP_VELOCITY: float = -560.0
const GRAVITY: float = 1450.0
const MAX_SHORT_JUMP_FALL: float = -280.0

var coyote_timer: float = 0.0
var jump_buffer: float = 0.0
var facing: int = 1
var is_dead: bool = false
var is_entering_door: bool = false
var spawn_position: Vector2
var controls_inverted: bool = false
var active_inverters: Dictionary = {}
var is_invulnerable: bool = false
var invulnerable_timer: float = 0.0

# Genshin Impact uslubidagi bir martalik Dash (Shift) holati
var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_dir: float = 1.0
var ghost_trail_timer: float = 0.0

@onready var visual: Node2D = $Visual
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("player")
	spawn_position = global_position
	if not InputMap.has_action("dash"):
		InputMap.add_action("dash")
	# Shift va J tugmalarining ikkalasi ham Dash uchun to'liq ishlashini kafolatlaymiz
	var has_shift := false
	var has_j := false
	for ev in InputMap.action_get_events("dash"):
		if ev is InputEventKey:
			if ev.keycode == KEY_SHIFT or ev.physical_keycode == KEY_SHIFT:
				has_shift = true
			if ev.keycode == KEY_J or ev.physical_keycode == KEY_J:
				has_j = true
	if not has_shift:
		var ev_shift := InputEventKey.new()
		ev_shift.physical_keycode = KEY_SHIFT
		InputMap.action_add_event("dash", ev_shift)
	if not has_j:
		var ev_j := InputEventKey.new()
		ev_j.physical_keycode = KEY_J
		InputMap.action_add_event("dash", ev_j)

func _physics_process(delta: float) -> void:
	if is_dead or is_entering_door or GameManager.is_countdown_active:
		velocity = Vector2.ZERO
		return

	if invulnerable_timer > 0.0:
		invulnerable_timer -= delta
		if invulnerable_timer <= 0.0:
			is_invulnerable = false

	# Dash taymerlari va sharpali qoldiq (ghost afterimage)
	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer -= delta

	if is_dashing:
		dash_timer -= delta
		ghost_trail_timer -= delta
		if ghost_trail_timer <= 0.0:
			ghost_trail_timer = 0.038
			_spawn_dash_ghost()
		if dash_timer <= 0.0:
			is_dashing = false

	# Coyote Time & Jump Buffer
	if is_on_floor():
		coyote_timer = 0.16
	else:
		coyote_timer -= delta

	if jump_buffer > 0.0:
		jump_buffer -= delta

	# Gorizontal harakat
	var move_dir := Input.get_axis("move_left", "move_right")
	if controls_inverted:
		move_dir = -move_dir

	# Dash faollashtirish (Faqat bir marta bosilganda - Genshin Impact uslubida)
	# QAT'IY QOIDA: is_action_just_pressed ishlatiladi,
	# shuning uchun Shift bosib turilsa tez yururmaydi!
	if Input.is_action_just_pressed("dash") and not is_dashing and dash_cooldown_timer <= 0.0:
		var target_dir := move_dir
		if target_dir == 0.0:
			target_dir = float(facing)
		dash_dir = target_dir
		is_dashing = true
		dash_timer = DASH_DURATION
		dash_cooldown_timer = DASH_COOLDOWN
		ghost_trail_timer = 0.0
		_spawn_dash_ghost()
		if visual:
			visual.scale = Vector2(1.38, 0.72)
		if is_inside_tree():
			var sm = get_node_or_null("/root/SoundManager")
			if sm and sm.has_method("play"):
				sm.play("dash")

	if is_dashing:
		velocity.x = dash_dir * DASH_SPEED
	elif move_dir != 0:
		facing = signi(int(move_dir))
		velocity.x = move_dir * SPEED
	else:
		velocity.x = 0.0

	if Input.is_action_just_pressed("jump"):
		jump_buffer = 0.16

	# Sakrash
	if jump_buffer > 0.0 and coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		coyote_timer = 0.0
		jump_buffer = 0.0
		if visual:
			visual.scale = Vector2(0.75, 1.35)
		if is_inside_tree():
			var sm = get_node_or_null("/root/SoundManager")
			if sm and sm.has_method("play"):
				sm.play("jump")

	# Sakrash tugmasi erta qo'yib yuborilganda pastga tortish
	if Input.is_action_just_released("jump") and velocity.y < MAX_SHORT_JUMP_FALL:
		velocity.y = MAX_SHORT_JUMP_FALL

	# Gravitatsiya va shaklni asl holatiga qaytarish (lerp)
	velocity.y += GRAVITY * delta
	# Terminal velocity (yorib o'tishni oldini olish)
	velocity.y = minf(velocity.y, 1200.0)

	if visual:
		visual.scale = visual.scale.lerp(Vector2.ONE, delta * 10.0)

	move_and_slide()
	if visual:
		visual.queue_redraw()

	# O'lim tekisligi config'dan o'qiladi yoki dinamik hisoblanadi
	var death_y: float = 750.0
	var trap_cfg = get_node_or_null("/root/TrapConfig")
	if trap_cfg and "death_plane_y" in trap_cfg:
		death_y = float(trap_cfg.death_plane_y)
	else:
		death_y = maxf(get_viewport_rect().size.y, 540.0) + 210.0

	if global_position.y > death_y:
		kill()

func kill() -> void:
	if is_dead or is_entering_door or is_invulnerable:
		return
	is_dead = true
	clear_inverter_zones()
	is_dashing = false
	dash_timer = 0.0
	dash_cooldown_timer = 0.0
	velocity = Vector2.ZERO
	if is_inside_tree():
		var sm = get_node_or_null("/root/SoundManager")
		if sm and sm.has_method("play"):
			sm.play("die")
		var gm = get_node_or_null("/root/GameManager")
		if gm and gm.has_method("record_death"):
			gm.record_death()
	died.emit()
	
	visible = false
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	_spawn_particles()
	
	# O'lik gavdani xaritadagi tuzoqlar zonasidan chetga olamiz
	global_position = Vector2(-9999, -9999)
	
	# Original: setTimeout(() => resetPlayer(), 340)
	await get_tree().create_timer(0.34).timeout
	if is_instance_valid(self):
		respawn()

func die() -> void:
	kill()

func respawn(at_position: Vector2 = spawn_position) -> void:
	global_position = at_position
	velocity = Vector2.ZERO
	is_dead = false
	is_dashing = false
	dash_timer = 0.0
	dash_cooldown_timer = 0.0
	is_entering_door = false
	clear_inverter_zones()
	is_invulnerable = true
	invulnerable_timer = 0.22 # 220ms spawn protection (takroriy o'limni oldini oladi)
	coyote_timer = 0.0
	jump_buffer = 0.0
	visible = true
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
	if visual:
		visual.scale = Vector2.ONE
	respawned.emit()
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_signal("player_respawned"):
		gm.player_respawned.emit()

func add_inverter_zone(zone: Node) -> void:
	active_inverters[zone] = true
	controls_inverted = true

func remove_inverter_zone(zone: Node) -> void:
	active_inverters.erase(zone)
	controls_inverted = not active_inverters.is_empty()

func clear_inverter_zones() -> void:
	active_inverters.clear()
	controls_inverted = false

func enter_door(target_pos: Vector2) -> void:
	if is_entering_door or is_dead:
		return
	is_entering_door = true
	velocity = Vector2.ZERO
	entered_exit.emit()
	
	# Original animatsiya: o'lcham 0 ga qarab kichrayib markazga tortiladi
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "global_position", target_pos, 0.18)
	if visual:
		tween.tween_property(visual, "scale", Vector2.ZERO, 0.18)
	await tween.finished
	visible = false

func enter_finish(target_pos: Vector2) -> void:
	enter_door(target_pos)

func _spawn_particles() -> void:
	var p_scene: PackedScene = load("res://scenes/player/death_particles.tscn")
	if p_scene:
		var p: CPUParticles2D = p_scene.instantiate()
		p.global_position = global_position - Vector2(0, 16)
		get_parent().add_child(p)

func _spawn_dash_ghost() -> void:
	if not is_inside_tree() or not get_parent():
		return
	var ghost := Node2D.new()
	ghost.global_position = global_position
	if visual:
		ghost.scale = visual.scale
	ghost.set_script(load("res://scripts/player/dash_ghost.gd"))
	get_parent().add_child(ghost)
