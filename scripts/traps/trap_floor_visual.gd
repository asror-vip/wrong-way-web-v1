extends Node2D

# Wrong Way - Trap Floor Visual Renderer
# Ensures falling trap floors render with 100% fidelity to the current chapter biome.

func _draw() -> void:
	var target = get_parent()
	var w: float = 140.0
	var h: float = 160.0
	if target and "platform_size" in target:
		w = target.platform_size.x
		h = target.platform_size.y

	var ch: int = 1
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("get_current_chapter"):
		ch = gm.get_current_chapter()

	# Asosiy tosh rangi biomlarga (chapter) qarab belgilanadi
	var base_col := Color("#1c1a22") # Chapter 1 (Limbo)
	if ch == 2:
		base_col = Color("#0d131f") # Chapter 2 (Frost Peak)
	elif ch == 3:
		base_col = Color("#062319") # Chapter 3 (Emerald Woods)
	elif ch == 4:
		base_col = Color("#291c14") # Chapter 4 (Golden Canyon)
	elif ch == 5:
		base_col = Color("#1a0505") # Chapter 5 (Inferno Abyss)

	var rect := Rect2(0.0, 0.0, w, h)
	draw_rect(rect, base_col, true)

	# Boblarga mos pol qoplamalari (Top layers) - SolidPlatform bilan 100% bir xil
	if ch == 2: # Winter / Frost Peak
		var snow_h := 5.5
		if w > 36.0:
			draw_rect(Rect2(0.0, 0.0, w, snow_h), Color("#f1f5f9"), true)
			draw_rect(Rect2(0.0, 0.0, w, 2.0), Color("#ffffff"), true)
			draw_rect(Rect2(0.0, snow_h - 1.5, w, 1.5), Color("#94a3b8"), true)
			var icicle_step := 32.0
			var num_icicles := int((w - 20.0) / icicle_step)
			for i in range(num_icicles):
				var ix := 14.0 + float(i) * icicle_step
				var ilen := 4.0 if (i % 2 == 0) else 6.0
				var pts := PackedVector2Array([
					Vector2(ix - 2.0, snow_h),
					Vector2(ix + 2.0, snow_h),
					Vector2(ix, snow_h + ilen)
				])
				draw_colored_polygon(pts, Color("#bae6fd"))
		else:
			var frost_rect := Rect2(0.0, 0.0, minf(w, 2.5), h)
			draw_rect(frost_rect, Color(0.49, 0.86, 0.99, 0.6), true)
	elif ch == 3: # Emerald Woods (To'q yashil mox / Moss)
		draw_rect(Rect2(0.0, 0.0, w, 4.0), Color("#14532d"), true)
		draw_rect(Rect2(0.0, 4.0, w, 2.0), Color("#064e3b"), true)
	elif ch == 4: # Golden Canyon (Sahro / Qum)
		var sand_h := 6.0
		draw_rect(Rect2(0.0, 0.0, w, sand_h), Color("#fcd34d"), true)
		draw_rect(Rect2(0.0, sand_h - 2.0, w, 2.0), Color("#d97706"), true)
	elif ch == 5: # Inferno Abyss (Lava / Obsidian)
		draw_rect(Rect2(0.0, 0.0, w, 3.0), Color("#450a0a"), true)
		draw_rect(Rect2(0.0, 0.0, w, 1.0), Color("#f97316"), true)
	else: # Chapter 1 (Default / Limbo)
		draw_rect(Rect2(0.0, 0.0, w, 3.0), Color("#342f3a"), true)
