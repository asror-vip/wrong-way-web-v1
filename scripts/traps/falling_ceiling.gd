extends AnimatableBody2D
class_name FallingCeiling

# Level Devil Trap: Falling Ceiling (Kutilmagan Shift Qulashi)
# Suspended overhead. When player walks beneath, it slams down rapidly!

@export var ceiling_size: Vector2 = Vector2(160, 40)
var platform_size: Vector2:
	get: return ceiling_size
	set(v): ceiling_size = v
@export var slam_distance_y: float = 240.0
@export var trigger_distance_x: float = 90.0
@export var slam_duration: float = 0.18

var original_pos: Vector2
var is_triggered: bool = false
var tween: Tween

@onready var col_shape: CollisionShape2D = $CollisionShape2D
@onready var kill_area: Area2D = $KillArea

func _ready() -> void:
	add_to_group("traps")
	original_pos = position
	
	if col_shape:
		var rect := RectangleShape2D.new()
		rect.size = ceiling_size
		col_shape.shape = rect
		col_shape.position = ceiling_size / 2.0
		
	if kill_area:
		var k_shape = kill_area.get_node_or_null("CollisionShape2D")
		if k_shape:
			var k_rect := RectangleShape2D.new()
			k_rect.size = Vector2(ceiling_size.x - 4.0, 12.0)
			k_shape.shape = k_rect
			k_shape.position = Vector2(ceiling_size.x / 2.0, ceiling_size.y - 6.0)
		kill_area.body_entered.connect(_on_kill_entered)

func _physics_process(_delta: float) -> void:
	if not is_triggered:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null and is_instance_valid(player):
			if "is_dead" in player and player.is_dead:
				return
			if "is_invulnerable" in player and player.is_invulnerable:
				return
			var center_x: float = global_position.x + ceiling_size.x / 2.0
			var dist_x: float = abs(player.global_position.x - center_x)
			var dist_y: float = player.global_position.y - global_position.y
			if dist_x < trigger_distance_x and dist_y > 0.0 and dist_y < slam_distance_y + 80.0:
				trigger_slam()

func trigger_slam() -> void:
	if is_triggered:
		return
	is_triggered = true
	SoundManager.play("trap")
	GameManager.request_screen_shake.emit(10.0)
	
	tween = create_tween()
	var target_y := original_pos.y + slam_distance_y
	tween.tween_property(self, "position:y", target_y, slam_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _on_kill_entered(body: Node2D) -> void:
	if is_triggered and (body is PlayerController or body.is_in_group("player")):
		if "is_dead" in body and body.is_dead:
			return
		if "is_invulnerable" in body and body.is_invulnerable:
			return
		if body.has_method("kill"):
			body.kill()
		elif body.has_method("die"):
			body.die()

func reset_trap() -> void:
	if tween and tween.is_valid():
		tween.kill()
	is_triggered = false
	position = original_pos
	queue_redraw()

func _draw() -> void:
	var ch: int = 1
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("get_current_chapter"):
		ch = gm.get_current_chapter()

	var base_col := Color("#1c1a22")
	var edge_col := Color("#342f3a")

	if ch == 2:
		base_col = Color("#0d131f")
		edge_col = Color(0.49, 0.86, 0.99, 0.6)
	elif ch == 3:
		base_col = Color("#062319")
		edge_col = Color("#4ade80")
	elif ch == 4:
		base_col = Color("#291c14")
		edge_col = Color("#fcd34d")
	elif ch == 5:
		base_col = Color("#1a0505")
		edge_col = Color("#f97316")

	var rect := Rect2(0, 0, ceiling_size.x, ceiling_size.y)
	draw_rect(rect, base_col, true)
	
	draw_line(Vector2(0, ceiling_size.y), Vector2(ceiling_size.x, ceiling_size.y), edge_col, 3.0)
