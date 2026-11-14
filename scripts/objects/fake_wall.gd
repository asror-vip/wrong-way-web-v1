extends Node2D
class_name FakeWall

# Level Devil / Wrong Way Trick: Fake Wall (Aldovchi Devor)
# Looks completely solid, but the player can walk straight through it
# to find a secret path or escape an impossible forward trap!

@export var wall_size: Vector2 = Vector2(32, 540)

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	var ch: int = 1
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("get_current_chapter"):
		ch = gm.get_current_chapter()

	var base_col := Color("#1c1a22")
	if ch == 2: base_col = Color("#0d131f")
	elif ch == 3: base_col = Color("#062319")
	elif ch == 4: base_col = Color("#291c14")
	elif ch == 5: base_col = Color("#1a0505")

	draw_rect(Rect2(0, 0, wall_size.x, wall_size.y), base_col, true)

