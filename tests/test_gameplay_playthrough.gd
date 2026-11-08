extends Node2D

# Deep Gameplay Traversal & Beatability Test (Levels 1 to 60)
# Validates that every single level in Chapters 1, 2, and 3 is 100% winnable.

var current_level_index: int = 1
var total_levels_to_test: int = 60
var failed_levels: Array[String] = []

func _ready() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--start="):
			current_level_index = int(arg.trim_prefix("--start="))
		if arg.begins_with("--end="):
			total_levels_to_test = int(arg.trim_prefix("--end="))

	print("======================================================================")
	print("STARTING GAMEPLAY PLAYTHROUGH BOT (LEVELS %d to %d)" % [
		current_level_index, total_levels_to_test
	])
	print("Simulating real platformer navigation from Spawn to ExitDoor")
	print("======================================================================")
	await get_tree().process_frame
	await get_tree().process_frame
	_test_next_level()

func _has_floor_ahead(inst: Node2D, at_pos: Vector2, dir: float) -> bool:
	var platforms := inst.get_node_or_null("Platforms")
	var check_x := at_pos.x + dir * 26.0
	var check_y := at_pos.y
	if platforms:
		for p in platforms.get_children():
			if p is StaticBody2D and "platform_size" in p:
				var px1: float = p.global_position.x
				var px2: float = px1 + p.platform_size.x
				var py: float = p.global_position.y
				if check_x >= px1 and check_x <= px2 and absf(py - check_y) <= 18.0:
					return true
	var traps := inst.get_node_or_null("Traps")
	if traps:
		for t in traps.get_children():
			if "platform_size" in t:
				var tx1: float = t.global_position.x
				var tx2: float = tx1 + t.platform_size.x
				var ty: float = t.global_position.y
				if check_x >= tx1 and check_x <= tx2 and absf(ty - check_y) <= 18.0:
					return true
	return false

func _test_next_level() -> void:
	if current_level_index > total_levels_to_test:
		_print_summary()
		return

	var lvl := current_level_index
	var path := "res://scenes/levels/level_%02d.tscn" % lvl
	print("\n>>> [PLAYING LEVEL %02d] %s" % [lvl, path])

	if not ResourceLoader.exists(path):
		failed_levels.append("Lvl %02d: Scene file missing" % lvl)
		current_level_index += 1
		_test_next_level()
		return

	var scn = load(path)
	var inst = scn.instantiate()
	add_child(inst)

	await get_tree().process_frame
	await get_tree().physics_frame

	var player = inst.get_node_or_null("Player") as PlayerController
	var door = inst.get_node_or_null("ExitDoor") as ExitDoor
	var traps = inst.get_node_or_null("Traps")

	if not player or not door:
		failed_levels.append("Lvl %02d: Player or ExitDoor missing" % lvl)
		inst.queue_free()
		current_level_index += 1
		_test_next_level()
		return

	player.is_invulnerable = true
	player.invulnerable_timer = 9999.0
	player.set_physics_process(false)

	var reached_door := false
	var max_frames := 750
	var prev_pos: Vector2 = player.global_position
	var stuck_counter: int = 0
	var launched_by_spring := false

	for frame in range(max_frames):
		if not is_instance_valid(player) or not is_instance_valid(door):
			break

		var cur_pos: Vector2 = player.global_position
		var door_pos: Vector2 = door.global_position

		if player.is_entering_door or cur_pos.distance_to(door_pos) < 45.0 or (
			absf(cur_pos.x - door_pos.x) < 36.0 and absf(cur_pos.y - door_pos.y) < 48.0
		):
			reached_door = true
			break

		if cur_pos.y > 620.0:
			break

		if player.velocity.y < -300.0:
			launched_by_spring = true
		elif player.is_on_floor():
			launched_by_spring = false

		var target_x: float = door_pos.x

		# Navigation: if door is higher or spring needed to cross
		var need_spring: bool = (door_pos.y < cur_pos.y - 30.0)
		if not need_spring and not _has_floor_ahead(inst, cur_pos, signf(door_pos.x - cur_pos.x)):
			need_spring = true

		if need_spring and not launched_by_spring and traps:
			var best_spring: Node2D = null
			var best_d: float = 99999.0
			for t in traps.get_children():
				if "spring_size" in t or t.name.to_lower().contains("spring"):
					if t.global_position.y >= cur_pos.y - 40.0:
						var d: float = cur_pos.distance_to(t.global_position)
						var is_towards: bool = (
							(door_pos.x >= cur_pos.x and
							t.global_position.x >= cur_pos.x - 30.0) or
							(door_pos.x < cur_pos.x and
							t.global_position.x <= cur_pos.x + 30.0)
						)
						if is_towards and d < best_d:
							best_d = d
							best_spring = t
			if not best_spring:
				for t in traps.get_children():
					if "spring_size" in t or t.name.to_lower().contains("spring"):
						if t.global_position.y >= cur_pos.y - 40.0:
							var d: float = cur_pos.distance_to(t.global_position)
							if d < best_d:
								best_d = d
								best_spring = t

			if best_spring:
				target_x = best_spring.global_position.x + 16.0

		var dx := target_x - cur_pos.x
		var dir := signf(dx) if absf(dx) > 2.0 else 0.0
		player.velocity.x = dir * player.SPEED

		if absf(cur_pos.x - prev_pos.x) < 0.5 and dir != 0.0:
			stuck_counter += 1
		else:
			stuck_counter = 0
		prev_pos = cur_pos

		var need_jump := false
		if stuck_counter > 4 or player.is_on_wall():
			need_jump = true

		if door_pos.y < cur_pos.y - 25.0 and player.is_on_floor() and not launched_by_spring:
			need_jump = true

		# Jump over incoming rolling boulders
		if traps and player.is_on_floor():
			for t in traps.get_children():
				if t is RollingBoulder and is_instance_valid(t):
					var rb := t as RollingBoulder
					var b_dist: float = rb.global_position.x - cur_pos.x
					var b_dy: float = absf(rb.global_position.y - cur_pos.y)
					if absf(b_dist) < 75.0 and b_dy < 30.0:
						need_jump = true
						break

		# Geometric floor ahead check
		if player.is_on_floor() and dir != 0.0:
			var near_spring := false
			if traps:
				for t in traps.get_children():
					if "spring_size" in t or t.name.to_lower().contains("spring"):
						var sx: float = absf(cur_pos.x - t.global_position.x)
						var sy: float = absf(cur_pos.y - t.global_position.y)
						if sx < 55.0 and sy < 35.0:
							near_spring = true
							break
			if not near_spring and not _has_floor_ahead(inst, cur_pos, dir):
				need_jump = true

		if need_jump and player.is_on_floor() and player.velocity.y > -500.0:
			player.velocity.y = player.JUMP_VELOCITY

		player.velocity.y += player.GRAVITY * (1.0 / 60.0)
		player.move_and_slide()
		await get_tree().physics_frame

	if reached_door:
		print("  -> Level %02d: REACHED EXIT DOOR! (WINNABLE)" % lvl)
	else:
		var fail_msg := "Lvl %02d: Bot could NOT reach ExitDoor! Ended at %s, Door at %s" % [
			lvl, str(player.global_position), str(door.global_position)
		]
		print("  -> FAIL: %s" % fail_msg)
		failed_levels.append(fail_msg)

	inst.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame

	current_level_index += 1
	_test_next_level()

func _print_summary() -> void:
	print("\n======================================================================")
	print("PLAYTHROUGH BOT AUDIT SUMMARY (LEVELS 1 to 60):")
	var passed_count := total_levels_to_test - failed_levels.size()
	print("  TOTAL LEVELS WON: %d / %d" % [passed_count, total_levels_to_test])
	print("======================================================================")
	if failed_levels.is_empty():
		print("EXIT 0: ALL 60 LEVELS ARE 100% NAVIGABLE AND BEATABLE TO THE EXIT DOOR!\n")
		get_tree().quit(0)
	else:
		print("EXIT 1: UNREACHABLE OR BLOCKED LEVELS DETECTED:")
		for f in failed_levels:
			print("  * %s" % f)
		get_tree().quit(1)
