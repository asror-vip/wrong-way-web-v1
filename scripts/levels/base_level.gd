extends Node2D
class_name BaseLevel

@export var level_number: int = 1

@onready var player: Node2D = get_node_or_null("Player")
@onready var exit_door: Node2D = get_node_or_null("ExitDoor")
@onready var traps_container: Node2D = get_node_or_null("Traps")

func _ready() -> void:
	if player == null:
		player = get_node_or_null("Player")
	if exit_door == null:
		exit_door = get_node_or_null("ExitDoor")
	if traps_container == null:
		traps_container = get_node_or_null("Traps")
	
	if traps_container:
		for trap in traps_container.get_children():
			if "player_ref" in trap:
				trap.player_ref = player
				
	if player and player.has_signal("died") and not player.died.is_connected(_on_player_died):
		player.died.connect(_on_player_died)
	if player and player.has_signal("respawned") and not player.respawned.is_connected(_on_player_respawned):
		player.respawned.connect(_on_player_respawned)
	
	# Mark level attempted for ad logic
	var sm = get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("record_level_attempt"):
		sm.record_level_attempt(level_number)

func _on_player_died() -> void:
	if traps_container:
		traps_container.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)

func _on_player_respawned() -> void:
	reset_level_traps()
	if traps_container:
		traps_container.set_deferred("process_mode", Node.PROCESS_MODE_INHERIT)

func reset_level_traps() -> void:
	if exit_door and exit_door.has_method("reset_door"):
		exit_door.reset_door()
	# Dublikat reset chaqiruvlarining oldini olish uchun yagona to'plamdan foydalanamiz
	var unique_traps: Dictionary = {}
	if traps_container:
		for trap in traps_container.get_children():
			if trap.has_method("reset_trap"):
				unique_traps[trap] = true
	for trap in get_tree().get_nodes_in_group("traps"):
		if trap.has_method("reset_trap"):
			unique_traps[trap] = true
	for trap in unique_traps.keys():
		trap.reset_trap()

func restart_attempt() -> void:
	reset_level_traps()
	if player:
		player.respawn()

func reset_attempt() -> void:
	restart_attempt()
