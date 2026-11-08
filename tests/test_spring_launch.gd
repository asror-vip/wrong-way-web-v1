extends Node

func _ready() -> void:
	var gp = preload("res://scenes/game/gameplay.tscn").instantiate()
	add_child(gp)
	await get_tree().process_frame
	await get_tree().process_frame
	gp.reload_to_level(26)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout

	var player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	Input.action_press("move_right")

	for step in range(80):
		await get_tree().physics_frame
		for node in get_tree().get_nodes_in_group("traps"):
			if node is SpringTrap and node.is_springing:
				print("step=", step, " player_y=", player.global_position.y, " ext=", node.extension)
				if node.extension > 15.0:
					await get_tree().process_frame
					var tex = get_viewport().get_texture()
					if tex:
						var img = tex.get_image()
						if img:
							img.save_png("C:/Users/asror/.gemini/antigravity/brain/e8e16c92-b1ce-4557-9005-b70c46ad996a/test_level_26_spring_extended.png")
							print("CAPTURED_EXTENDED!")

	Input.action_release("move_right")
	get_tree().quit(0)
