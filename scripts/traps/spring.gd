extends Area2D
class_name SpringTrap

@export var spring_size: Vector2 = Vector2(32, 32)
@export var launch_velocity: float = -950.0
@export var bounce_force: float = 0.0

@onready var col_shape: CollisionShape2D = $CollisionShape2D

var is_springing: bool = false
var tw: Tween
var extension: float = 0.0

func _ready() -> void:
	add_to_group("traps")
	if col_shape:
		var rect := RectangleShape2D.new()
		rect.size = Vector2(spring_size.x + 8.0, 24.0)
		col_shape.shape = rect
		# Pol yuzasidan tepaga joylashtiramiz (y in [-24, 0])
		col_shape.position = Vector2(spring_size.x / 2.0, -12.0)
	body_entered.connect(_on_body_entered)
	queue_redraw()

func _physics_process(_delta: float) -> void:
	if is_springing:
		queue_redraw()
		return

	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null and is_instance_valid(player):
		var p_dead: bool = "is_dead" in player and player.is_dead
		if not p_dead:
			var px: float = player.global_position.x
			var py: float = player.global_position.y
			var min_x: float = global_position.x - 4.0
			var max_x: float = global_position.x + spring_size.x + 4.0
			if px >= min_x and px <= max_x:
				var dy: float = py - global_position.y
				# O'yinchi pol sirtida turganda yoki qo'nganda (-18px..+10px oralig'ida)
				if dy >= -18.0 and dy <= 10.0:
					_trigger_launch(player)

func _draw() -> void:
	# Tinch holatda (idle) pol ichida hech qanday purjina ko'rinmasligi shart
	if not is_springing or extension <= 1.0:
		return

	var ch: int = 1
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("get_current_chapter"):
		ch = gm.get_current_chapter()

	var w := spring_size.x
	var h := extension
	var y_top := -h

	var base_col := Color("#1c1a22")
	var spring_col1 := Color("#475569")
	var spring_col2 := Color("#1e293b")

	if ch == 2:
		base_col = Color("#0d131f")
		spring_col1 = Color("#94a3b8")
		spring_col2 = Color("#64748b")
	elif ch == 3:
		base_col = Color("#062319")
		spring_col1 = Color("#166534")
		spring_col2 = Color("#064e3b")
	elif ch == 4:
		base_col = Color("#291c14")
		spring_col1 = Color("#b45309")
		spring_col2 = Color("#78350f")
	elif ch == 5:
		base_col = Color("#1a0505")
		spring_col1 = Color("#ea580c")
		spring_col2 = Color("#991b1b")

	# Poydevor (pol sirtiga jips birlashgan)
	draw_rect(Rect2(0, -3.0, w, 4.0), base_col, true)

	# Yuqoriga otiluvchi spiral halqalar
	var coils := 4
	var coil_h := (h - 6.0) / float(coils)
	for i in range(coils):
		var cy0 := -3.0 - float(i) * coil_h
		var cy1 := cy0 - coil_h * 0.5
		var cy2 := cy0 - coil_h
		draw_line(Vector2(4, cy0), Vector2(w - 4, cy1), spring_col1, 2.2)
		draw_line(Vector2(w - 4, cy1), Vector2(4, cy2), spring_col2, 2.2)

	# Sakrash yostig'i (Top pad)
	var pad_col := Color("#f59e0b")
	var hl_col := Color("#fef08a")

	if ch == 2:
		pad_col = Color("#38bdf8")
		hl_col = Color("#ffffff")
	elif ch == 3:
		pad_col = Color("#22c55e")
		hl_col = Color("#86efac")
	elif ch == 4:
		pad_col = Color("#fcd34d")
		hl_col = Color("#fffbeb")
	elif ch == 5:
		pad_col = Color("#ef4444")
		hl_col = Color("#fef08a")

	draw_rect(Rect2(2, y_top - 5, w - 4, 6), pad_col, true)
	draw_rect(Rect2(4, y_top - 5, w - 8, 2), hl_col, true)

func _on_body_entered(body: Node2D) -> void:
	if body is PlayerController or body.is_in_group("player"):
		_trigger_launch(body)

func _trigger_launch(body: Node2D) -> void:
	if is_springing:
		return
	is_springing = true
	extension = 0.0

	var sm = get_node_or_null("/root/SoundManager")
	if sm and sm.has_method("play"):
		sm.play("jump")

	var target_vel: float = launch_velocity
	if bounce_force > 0.0 and (launch_velocity == -950.0 or launch_velocity == 0.0):
		target_vel = -absf(bounce_force) * 1.35
	elif launch_velocity == 0.0:
		target_vel = -850.0

	if "velocity" in body:
		body.velocity.y = target_vel
	if body.has_method("apply_impulse"):
		body.apply_impulse(Vector2(0, target_vel))
	if "coyote_timer" in body:
		body.coyote_timer = 0.0
	if "visual" in body and body.visual:
		body.visual.scale = Vector2(0.65, 1.45)

	if tw and tw.is_valid():
		tw.kill()
	tw = create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	var max_ext := maxf(spring_size.y, 34.0)
	tw.tween_property(self, "extension", max_ext, 0.08)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "extension", max_ext * 1.15, 0.06)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "extension", 0.0, 0.18)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	tw.finished.connect(func():
		is_springing = false
		extension = 0.0
		queue_redraw()
	)
	queue_redraw()

func reset_trap() -> void:
	if tw and tw.is_valid():
		tw.kill()
	is_springing = false
	extension = 0.0
	queue_redraw()
