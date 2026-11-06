extends Area2D
class_name JumpingSpikes

# Level Devil Trap: Jumping Spikes (Sakrovchi Tikanlar)
# Floor spikes that look innocent, but as soon as the player jumps over them,
# they spring into the air to catch the player mid-air!

@export var spike_width: float = 64.0
@export var spike_height: float = 28.0
@export var trigger_distance: float = 80.0
@export var jump_speed: float = -620.0
@export var fall_gravity: float = 1800.0

var original_pos: Vector2
var is_triggered: bool = false
var velocity_y: float = 0.0
var current_y: float = 0.0

@onready var col_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("traps")
	original_pos = position
	current_y = position.y
	
	if col_shape:
		var rect := RectangleShape2D.new()
		rect.size = Vector2(spike_width, spike_height)
		col_shape.shape = rect
		col_shape.position = Vector2(spike_width / 2.0, -spike_height / 2.0)
		
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	if not is_triggered:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null and is_instance_valid(player):
			if "is_dead" in player and player.is_dead:
				return
			if "is_invulnerable" in player and player.is_invulnerable:
				return
			var center_x: float = global_position.x + spike_width / 2.0
			var dist_x: float = abs(player.global_position.x - center_x)
			var dist_y: float = global_position.y - player.global_position.y
			
			# O'yinchi yaqinlashib havoga sakraganda tikanlar yuqoriga otiladi!
			if dist_x < trigger_distance and dist_y > 10.0 and dist_y < 160.0:
				trigger_jump()
	else:
		velocity_y += fall_gravity * delta
		current_y += velocity_y * delta
		if current_y >= original_pos.y:
			current_y = original_pos.y
			velocity_y = 0.0
		position.y = current_y
		for b in get_overlapping_bodies():
			_on_body_entered(b)
		
	queue_redraw()

func trigger_jump() -> void:
	if is_triggered:
		return
	is_triggered = true
	velocity_y = jump_speed
	SoundManager.play("trap")
	GameManager.request_screen_shake.emit(6.0)

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
	is_triggered = false
	velocity_y = 0.0
	current_y = original_pos.y
	position = original_pos
	queue_redraw()

func _draw() -> void:
	var w := spike_width
	var h := spike_height
	var count := int(max(1.0, w / 16.0))
	var step := w / float(count)
	
	# Poydevor (oddiy qorong'i polga mos)
	draw_rect(Rect2(0, -3.0, w, 3.0), Color("#0a0b10"), true)
	draw_rect(Rect2(0, -3.0, w, 1.5), Color("#262e3e"), true)
	
	# Oddiy qora Limbo tikanlari (o'yinchi oddiy tikan deb o'ylab sakraydi)
	for i in range(count):
		var x0 := i * step
		var x1 := x0 + step * 0.5
		var x2 := (i + 1) * step
		var pts := PackedVector2Array([
			Vector2(x0, -3.0),
			Vector2(x1, -h),
			Vector2(x2, -3.0)
		])
		draw_colored_polygon(pts, Color("#0a0b10"))
		draw_line(Vector2(x0, -3.0), Vector2(x1, -h), Color("#e4e4e7"), 1.2)
		draw_line(Vector2(x1, -h), Vector2(x2, -3.0), Color("#334155"), 1.2)
