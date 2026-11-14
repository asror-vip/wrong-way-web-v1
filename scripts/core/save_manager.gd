extends Node

signal touch_layout_changed
signal music_setting_changed(enabled: bool)

const SAVE_PATH := "user://save_data.cfg"

var unlocked_levels: Array[int] = [1]
var level_stars: Dictionary = {}
var level_best_times: Dictionary = {}
var level_best_deaths: Dictionary = {}
var overall_best_text: String = ""
var overall_best_ms: float = 999999999.0
var sfx_enabled: bool = true
var music_enabled: bool = true
var music_volume: float = 0.8
var sfx_volume: float = 1.0
var shake_enabled: bool = true
var current_language: String = "en"
var custom_touch_layout: Dictionary = {}

# Debug / All levels unlocked mode: barcha 60 ta daraja ochiq
var debug_unlock_all: bool = true

# Ad-unlock & Navigation Context
var ad_unlocked_levels: Array[int] = []
var attempted_levels: Array[int] = []
var last_ad_unlocked_level: int = 0
var navigation_source: String = "home_menu"
var return_level_num: int = 1
var should_restore_result_modal: bool = false
var pending_result_data: Dictionary = {}

func _ready() -> void:
	load_data()

func load_data() -> void:
	var config := ConfigFile.new()
	var err := config.load(SAVE_PATH)
	if err != OK:
		err = config.load(SAVE_PATH + ".bak")
	if err == OK:
		unlocked_levels = Array(config.get_value("progress", "unlocked_levels", [1]), TYPE_INT, "", null)
		level_stars = config.get_value("progress", "level_stars", {})
		level_best_times = config.get_value("progress", "level_best_times", {})
		level_best_deaths = config.get_value("progress", "level_best_deaths", {})
		overall_best_text = config.get_value("progress", "overall_best_text", "")
		overall_best_ms = config.get_value("progress", "overall_best_ms", 999999999.0)
		ad_unlocked_levels = Array(config.get_value("progress", "ad_unlocked_levels", []), TYPE_INT, "", null)
		attempted_levels = Array(config.get_value("progress", "attempted_levels", []), TYPE_INT, "", null)
		last_ad_unlocked_level = config.get_value("progress", "last_ad_unlocked_level", 0)
		sfx_enabled = config.get_value("settings", "sfx_enabled", true)
		music_enabled = config.get_value("settings", "music_enabled", true)
		music_volume = config.get_value("settings", "music_volume", 0.8)
		sfx_volume = config.get_value("settings", "sfx_volume", 1.0)
		shake_enabled = config.get_value("settings", "shake_enabled", true)
		current_language = config.get_value("settings", "current_language", "en")
		custom_touch_layout = config.get_value("settings", "custom_touch_layout", {})
		debug_unlock_all = config.get_value("settings", "debug_unlock_all", true)

	debug_unlock_all = true

	# Barcha 60 ta darajani o'yinchi uchun ochiq holatga keltirish:
	for l in range(1, 61):
		if not unlocked_levels.has(l):
			unlocked_levels.append(l)

func save_data() -> void:
	var config := ConfigFile.new()
	config.set_value("progress", "unlocked_levels", unlocked_levels)
	config.set_value("progress", "level_stars", level_stars)
	config.set_value("progress", "level_best_times", level_best_times)
	config.set_value("progress", "level_best_deaths", level_best_deaths)
	config.set_value("progress", "overall_best_text", overall_best_text)
	config.set_value("progress", "overall_best_ms", overall_best_ms)
	config.set_value("progress", "ad_unlocked_levels", ad_unlocked_levels)
	config.set_value("progress", "attempted_levels", attempted_levels)
	config.set_value("progress", "last_ad_unlocked_level", last_ad_unlocked_level)
	config.set_value("settings", "sfx_enabled", sfx_enabled)
	config.set_value("settings", "music_enabled", music_enabled)
	config.set_value("settings", "music_volume", music_volume)
	config.set_value("settings", "sfx_volume", sfx_volume)
	config.set_value("settings", "shake_enabled", shake_enabled)
	config.set_value("settings", "current_language", current_language)
	config.set_value("settings", "custom_touch_layout", custom_touch_layout)
	config.set_value("settings", "debug_unlock_all", debug_unlock_all)
	_write_config_atomic(config)

func _write_config_atomic(config: ConfigFile) -> void:
	# Atomik saqlash: avval .tmp faylga yoziladi, so'ng eski fayl .bak'ga ko'chiriladi
	# va .tmp asosiy fayl ustiga rename qilinadi. Crash/disk to'lishida progress yo'qolmaydi.
	var tmp_path := SAVE_PATH + ".tmp"
	var bak_path := SAVE_PATH + ".bak"
	var err := config.save(tmp_path)
	if err != OK:
		push_error("SaveManager: saqlashda xatolik (kod %d): %s" % [err, tmp_path])
		return
	var abs_save := ProjectSettings.globalize_path(SAVE_PATH)
	var abs_tmp := ProjectSettings.globalize_path(tmp_path)
	var abs_bak := ProjectSettings.globalize_path(bak_path)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(abs_save, abs_bak)
	var ren_err := DirAccess.rename_absolute(abs_tmp, abs_save)
	if ren_err != OK:
		push_error("SaveManager: atomik o'zgartirishda xatolik (kod %d)" % ren_err)

func get_touch_pos(btn_name: String, default_val: Vector2) -> Vector2:
	if custom_touch_layout.has(btn_name):
		var val = custom_touch_layout[btn_name]
		if val is Array and val.size() >= 2:
			return Vector2(float(val[0]), float(val[1]))
		elif val is Vector2:
			return val
	return default_val

func set_touch_pos(btn_name: String, pos: Vector2) -> void:
	custom_touch_layout[btn_name] = [pos.x, pos.y]
	save_data()
	touch_layout_changed.emit()

func reset_touch_layout() -> void:
	custom_touch_layout.clear()
	save_data()
	touch_layout_changed.emit()

func is_level_unlocked(lvl: int) -> bool:
	if debug_unlock_all:
		return lvl >= 1 and lvl <= 60
	if lvl == 1:
		return true
	return unlocked_levels.has(lvl) or ad_unlocked_levels.has(lvl)

func get_highest_unlocked_level() -> int:
	var highest := 1
	for lvl in unlocked_levels:
		if lvl > highest:
			highest = lvl
	for lvl in ad_unlocked_levels:
		if lvl > highest:
			highest = lvl
	return highest

func record_result(lvl: int, time_ms: float, deaths: int) -> int:
	var stars: int = 1
	if deaths == 0:
		stars = 3
	elif deaths <= 2:
		stars = 2
	else:
		stars = 1

	var str_lvl := str(lvl)
	var prev_stars: int = int(level_stars.get(str_lvl, 0))
	if stars > prev_stars:
		level_stars[str_lvl] = stars

	var prev_time: float = float(level_best_times.get(str_lvl, 999999999.0))
	if time_ms < prev_time:
		level_best_times[str_lvl] = time_ms

	var prev_deaths: int = int(level_best_deaths.get(str_lvl, 999999))
	if deaths < prev_deaths:
		level_best_deaths[str_lvl] = deaths

	if time_ms < overall_best_ms:
		overall_best_ms = time_ms
		var lvl_str := LocaleManager.t("level_header", [lvl])
		overall_best_text = "%.2fs (%s)" % [time_ms / 1000.0, lvl_str]

	if stars >= 2:
		var next_lvl := lvl + 1
		if next_lvl <= 60 and not unlocked_levels.has(next_lvl):
			unlocked_levels.append(next_lvl)

	save_data()
		
	return stars

func get_save_payload() -> Dictionary:
	return {
		"unlocked_levels": unlocked_levels,
		"level_stars": level_stars,
		"level_best_times": level_best_times,
		"level_best_deaths": level_best_deaths,
		"overall_best_ms": overall_best_ms,
		"overall_best_text": overall_best_text,
		"ad_unlocked_levels": ad_unlocked_levels,
		"total_stars": get_total_stars(),
		"highest_level": get_highest_unlocked_level()
	}

func merge_cloud_save(cloud_data: Dictionary) -> void:
	if not cloud_data is Dictionary or cloud_data.is_empty():
		return
		
	var changed := false
	
	# 1. Unlocked levels
	if cloud_data.has("unlocked_levels"):
		var c_unlocked = cloud_data["unlocked_levels"]
		if c_unlocked is Array:
			for lvl in c_unlocked:
				var ilvl := int(lvl)
				if ilvl >= 1 and not unlocked_levels.has(ilvl):
					unlocked_levels.append(ilvl)
					changed = true
					
	# 2. Level stars
	if cloud_data.has("level_stars"):
		var c_stars = cloud_data["level_stars"]
		if c_stars is Dictionary:
			for k in c_stars.keys():
				var str_k := str(k)
				var c_s := int(c_stars[k])
				var l_s := int(level_stars.get(str_k, 0))
				if c_s > l_s:
					level_stars[str_k] = c_s
					changed = true
					
	# 3. Best times
	if cloud_data.has("level_best_times"):
		var c_times = cloud_data["level_best_times"]
		if c_times is Dictionary:
			for k in c_times.keys():
				var str_k := str(k)
				var c_t := float(c_times[k])
				var l_t := float(level_best_times.get(str_k, 999999999.0))
				if c_t < l_t:
					level_best_times[str_k] = c_t
					changed = true
					
	# 4. Overall best
	if cloud_data.has("overall_best_ms"):
		var c_ob := float(cloud_data["overall_best_ms"])
		if c_ob < overall_best_ms:
			overall_best_ms = c_ob
			if cloud_data.has("overall_best_text"):
				overall_best_text = str(cloud_data["overall_best_text"])
			changed = true
			
	if not unlocked_levels.has(1):
		unlocked_levels.push_front(1)
		
	if changed:
		save_data()
		print("SaveManager: Bulutli saqlangan o'yin muvaffaqiyatli sinxronlandi!")

func record_level_result(lvl: int, time_ms: float, deaths: int) -> int:
	return record_result(lvl, time_ms, deaths)

func get_level_stars(lvl: int) -> int:
	return int(level_stars.get(str(lvl), 0))

func get_overall_best_text() -> String:
	if overall_best_ms >= 999999000.0 or overall_best_text == "Mavjud emas" \
			or overall_best_text.is_empty():
		return LocaleManager.t("not_available")
	return overall_best_text

func record_level_attempt(lvl: int) -> void:
	if not attempted_levels.has(lvl):
		attempted_levels.append(lvl)
		save_data()

# -------------------------------------------------------------
# Yangilangan Reklama orqali Daraja Ochish Tizimi:
# 1. Faqat birinchi qulflangan darajagagina ruxsat (sakrab ketish taqiqlanadi).
# 2. Ochmoqchi bo'lgan darajadan oldingisini kamida bir marta o'ynagan bo'lishi shart (1-ni o'ynamay 2-ni ocholmaydi).
# 3. Bitta daraja oralab (cheriz) reklama ruxsat beriladi (masalan 2 dan o'tolmasa 3 ni reklama bilan ochadi, 4 da bu yo'q, 5 da bor va h.k.).
# -------------------------------------------------------------
func is_level_ad_unlockable(lvl: int) -> bool:
	if lvl <= 1 or lvl > 60:
		return false
	if is_level_unlocked(lvl):
		return false
		
	# 1. Faqat eng birinchi qulflangan daraja bo'lishi kerak
	var first_locked := -1
	for l in range(1, 61):
		if not is_level_unlocked(l):
			first_locked = l
			break
	if lvl != first_locked:
		return false
		
	# 2. Ochmoqchi bo'lgan darajadan oldingisini kamida bir marta o'ynagan bo'lishi shart
	if not attempted_levels.has(lvl - 1):
		return false
		
	# 3. Bitta daraja oralab (cheriz) reklama ruxsat beriladi
	if last_ad_unlocked_level > 0:
		if (lvl - last_ad_unlocked_level) < 2:
			return false
			
	return true

func get_lock_reason_dialog(lvl: int) -> Dictionary:
	var first_locked := -1
	for l in range(1, 61):
		if not is_level_unlocked(l):
			first_locked = l
			break
			
	if lvl != first_locked:
		return {
			"title": LocaleManager.t("lock_title"),
			"text": LocaleManager.t("lock_must_open_earlier")
		}
		
	if not attempted_levels.has(lvl - 1):
		return {
			"title": LocaleManager.t("lock_title"),
			"text": LocaleManager.t("lock_need_attempt", [lvl - 1])
		}
		
	if last_ad_unlocked_level > 0 and (lvl - last_ad_unlocked_level) < 2:
		var next_allowed := last_ad_unlocked_level + 2
		return {
			"title": LocaleManager.t("lock_title"),
			"text": LocaleManager.t("lock_cooldown", [last_ad_unlocked_level, next_allowed])
		}
		
	return {
		"title": LocaleManager.t("lock_title"),
		"text": LocaleManager.t("lock_need_stars", [lvl - 1])
	}

func unlock_level_via_ad(lvl: int) -> void:
	last_ad_unlocked_level = lvl
	if not ad_unlocked_levels.has(lvl):
		ad_unlocked_levels.append(lvl)
	if not unlocked_levels.has(lvl):
		unlocked_levels.append(lvl)
	save_data()

func is_level_completed(lvl: int) -> bool:
	return level_stars.has(str(lvl)) and int(level_stars[str(lvl)]) > 0

func get_highest_completed_level() -> int:
	var highest := 0
	for k in level_stars:
		var lvl := int(k)
		if int(level_stars[k]) > 0 and lvl > highest:
			if lvl <= 60 or ResourceLoader.exists("res://scenes/levels/level_%02d.tscn" % lvl) or ResourceLoader.exists("res://scenes/levels/level_%d.tscn" % lvl):
				highest = lvl
	return highest

func get_completed_level_count() -> int:
	var count := 0
	for k in level_stars:
		var lvl := int(k)
		if int(level_stars[k]) > 0:
			if lvl <= 60 or ResourceLoader.exists("res://scenes/levels/level_%02d.tscn" % lvl) or ResourceLoader.exists("res://scenes/levels/level_%d.tscn" % lvl):
				count += 1
	return count

func get_unlocked_count() -> int:
	var count := 0
	for lvl in unlocked_levels:
		if lvl <= 60 or ResourceLoader.exists("res://scenes/levels/level_%02d.tscn" % lvl) or ResourceLoader.exists("res://scenes/levels/level_%d.tscn" % lvl):
			count += 1
	return count

func get_level_best_deaths(lvl: int) -> int:
	var str_lvl := str(lvl)
	if level_best_deaths.has(str_lvl):
		return int(level_best_deaths[str_lvl])
	return 0

func get_total_beaten_deaths() -> int:
	var total: int = 0
	for lvl in range(1, 61):
		var str_lvl := str(lvl)
		if is_level_completed(lvl) and level_best_deaths.has(str_lvl):
			total += int(level_best_deaths[str_lvl])
	return total

func get_total_stars() -> int:
	var total: int = 0
	for k in level_stars:
		total += int(level_stars[k])
	return total

func get_level_best_time_sec(lvl: int) -> int:
	var str_lvl := str(lvl)
	if level_best_times.has(str_lvl):
		var t_ms: float = float(level_best_times[str_lvl])
		if t_ms < 999999000.0:
			# Faqat butun sekundlar (millisekundsiz)
			return maxi(1, int(round(t_ms / 1000.0)))
	return -1

func get_total_beaten_time_sec() -> int:
	var total_sec: int = 0
	for lvl in range(1, 61):
		var sec := get_level_best_time_sec(lvl)
		if sec > 0:
			total_sec += sec
	return total_sec

func get_chapter_stars(chapter: int) -> int:
	var total: int = 0
	var start_lvl := 1
	var end_lvl := 20
	if chapter == 2:
		start_lvl = 21
		end_lvl = 40
	elif chapter == 3:
		start_lvl = 41
		end_lvl = 60
	for l in range(start_lvl, end_lvl + 1):
		total += int(level_stars.get(str(l), 0))
	return total

func get_chapter_total_time_sec(chapter: int) -> int:
	var total_sec: int = 0
	var start_lvl := 1
	var end_lvl := 20
	if chapter == 2:
		start_lvl = 21
		end_lvl = 40
	elif chapter == 3:
		start_lvl = 41
		end_lvl = 60
	for l in range(start_lvl, end_lvl + 1):
		var sec := get_level_best_time_sec(l)
		if sec > 0:
			total_sec += sec
	return total_sec

func is_chapter_unlocked(chapter: int) -> bool:
	if debug_unlock_all:
		return chapter >= 1 and chapter <= 3
	if chapter == 1:
		return true
	elif chapter == 2:
		return is_level_completed(20) or unlocked_levels.has(21) or ad_unlocked_levels.has(21)
	elif chapter == 3:
		return is_level_completed(40) or unlocked_levels.has(41) or ad_unlocked_levels.has(41)
	return false

func get_level_time_text(lvl: int) -> String:
	var sec := get_level_best_time_sec(lvl)
	if sec >= 0:
		return "%ds" % sec
	return "--"

func reset_progress() -> void:
	unlocked_levels = []
	for l in range(1, 61):
		unlocked_levels.append(l)
	ad_unlocked_levels.clear()
	attempted_levels.clear()
	last_ad_unlocked_level = 0
	level_stars.clear()
	level_best_times.clear()
	level_best_deaths.clear()
	overall_best_text = ""
	overall_best_ms = 999999999.0
	save_data()

func reset_all_data() -> void:
	reset_progress()
