extends Node

# LocaleManager: Multi-language localization system for Wrong Way
# Supports: uz (O'zbek), ru (Русский), en (English), tr (Türkçe)

signal language_changed(lang_code: String)

var current_language: String = "en"

const LANGUAGES = {
	"uz": "O'zbekcha",
	"ru": "Русский",
	"en": "English",
	"tr": "Türkçe"
}

const STRINGS = {
	"uz": {
		# Title Screen
		"game_title": "WRONG WAY",
		"game_subtitle": "Tuzoqlar va sinovlar maydoni",
		"btn_start": "BOSHLASH",
		
		# Main Menu
		"btn_play": "O'YNASH",
		"btn_continue": "DAVOM ETISH",
		"btn_level_select": "DARAJALAR",
		"btn_levels": "DARAJALAR",
		"btn_multiplayer": "MULTIPLAYER",
		"btn_leaderboard": "REKORDLAR",
		"btn_settings": "SOZLAMALAR",
		"btn_quit": "CHIQISH",
		"best_chip": "Rekord: %s",
		"best_stars": "Yulduzlar: %d / 60",
		"level_header": "DARAJA %d",
		"level_complete": "DARAJA YAKUNLANDI",
		"great_job": "Ajoyib natija!",
		"last_record": "Oxirgi rekord: %s",
		"not_available": "Mavjud emas",
		"multiplayer_title": "MULTIPLAYER REJIMI",
		"multiplayer_desc": "Multiplayer va Online Race rejimi tez kunda taqdim etiladi!\n\nHozirda Campaign darajalari faol.",
		"leaderboard_title": "REKORDLAR JADVALI",
		"leaderboard_desc": "Hozirgi bosqichda faqat lokal rekordlar saqlanmoqda.\n\nSizning eng yaxshi rekordingiz:\n%s",
		"total_time": "Jami vaqt: %ds",
		"leaderboard_total_stars": "Yulduzlar: %d",
		"leaderboard_total_time": "Umumiy vaqt: %d soniya",
		"level_time_item": "%d-daraja: %s",
		"tab_global": "GLOBAL",
		"tab_friends": "DO'STLAR",
		"player_you": "Siz",
		
		# Settings Modal
		"settings_title": "SOZLAMALAR",
		"setting_language": "Til (Language):",
		"setting_music": "Fon musiqasi (BGM):",
		"setting_music_volume": "Musiqa balandligi:",
		"setting_sound": "Ovoz effektlari (SFX):",
		"setting_sound_volume": "Effektlar balandligi:",
		"setting_shake": "Ekran silkinishi:",
		"status_on": "YONIQ",
		"status_off": "O'CHIQ",
		"controls_title": "Boshqaruv va Klaviatura:",
		"controls_desc": "Yurish: A / D yoki ◄ / ► (Sensor)\nSakrash: W / Space / ▲\nDash (Tezlashuv): Shift / J\nQayta boshlash: R\nPauza / Menyu: Esc / P\nTo'liq ekran: F11",
				"btn_close": "Yopish",
		"btn_customize_controls": "Tugmalar joyini sozlash",
		"controls_customizer_title": "TUGMALAR JOYINI SOZLASH",
		"controls_customizer_hint": "Tugmalarni xohlagan joyga surib joylashtiring",
		"btn_reset_default": "Asliga qaytarish",
		
		# Level Select
		"map_title": "DARAJALAR",
		"chapter_1_title": "1-BOB: DARAJALAR",
		"chapter_2_title": "2-BOB: DARAJALAR",
		"chapter_3_title": "3-BOB: DARAJALAR",
		"chapter_4_title": "4-BOB: OLTIN KANYON",
		"chapter_5_title": "5-BOB: OLOVLI ABISS",
		"chapter_4_desc": "Sahro va Kanyon yangilanishi tez kunda taqdim etiladi!",
		"chapter_5_desc": "Lava va Vulqon yangilanishi tez kunda taqdim etiladi!",
		"chapter_nav_btn": "%d-BOB",
		"coming_soon_caps": "TEZ KUNDA",
		"more_levels_soon": "Yangi darajalar tez kunda taqdim etiladi!",
		"chapter_2_locked": "2-BOB QULFLANGAN",
		"chapter_2_unlock_req": "Ochish uchun 1-bobni (20-darajani) yakunlang",
		"chapter_3_locked": "3-BOB QULFLANGAN",
		"chapter_3_unlock_req": "Ochish uchun 2-bobni (40-darajani) yakunlang",
		"btn_chapter_1": "1-BOB",
		"btn_chapter_2": "2-BOB",
		"btn_chapter_3": "3-BOB",
		"btn_back": "Orqaga",
		"btn_menu": "Menyu",
		"lvl_label": "LVL %d",
		"lvl_ad_unlock": "Ochish",
		"lvl_locked": "Qulf",
		"total_stars": "%d / 180",
		"lock_title": "DARAJA QULFLANGAN",
		"lock_need_attempt": "Bu darajani reklama orqali ochish uchun avval %d-darajani o'ynab ko'ring!",
		"lock_cooldown": "Reklama orqali daraja ochish har 3 ta darajada 1 marta mumkin!\n(Oxirgi ochilgan: %d-lvl. Keyingi ruxsat: %d-darajada)",
		"lock_need_stars": "Bu darajani ochish uchun avvalgi %d-darajada kamida 2 ta yulduz oling!",
		"lock_must_open_earlier": "Avval oldingi darajalarni oching!",
		"zone2_title": "2-ZONA: TUMANLI QAL'A",
		"zone2_req": "Ochilish uchun 50 ta yulduz kerak",
		"zone2_status": "%d / 50",
		
		# Game HUD
		"hud_level": "LEVEL %d",
		"hud_time": "%.2fs",
		"hud_deaths": "%d ta o'lim",
		"btn_jump": "SAKRA",
		"btn_hud_menu": "Menyu",
		
		# Pause Modal
		"pause_title": "PAUZA",
		"btn_resume": "DAVOM ETISH",
		"btn_restart": "Qayta urinish",
		"btn_map": "Xarita",
		"btn_home": "Bosh menyu",
		
		# Win Overlay
		"win_title": "%d-DARAJA YAKUNLANDI!",
		"win_3_stars": "Mukammal natija! Keyingi daraja ochildi!",
		"win_2_stars": "Yaxshi natija! Keyingi daraja ochildi!",
		"win_1_star": "Keyingi darajani ochish uchun kamida 2 ta yulduz oling!",
		"win_time": "Vaqt: %.2fs",
		"win_deaths": "%d ta o'lim",
		"win_stats": "Vaqt: %ds   •   O'limlar: %d",
		"win_all_60_complete": "BARCHA 60 TA DARAJA YAKUNLANDI! 🎉\n4-BOB VA 5-BOB TEZ KUNDA",
		"btn_next_lvl": "KEYINGI DARAJA",

		# Splash Hints & Game Info
		"hint_0": "O'yin sozlamalari tekshirilmoqda...",
		"hint_1": "Tuzoqlarning barcha mexanizmlari yashirilmoqda...",
		"hint_2": "Hech qachon pol va eshiklarga ko'r-ko'rona ishonmang...",
		"hint_3": "Hamma narsa tayyor. Qorong'u olamga xush kelibsiz!",
		"game_desc_info": (
			"Wrong Way — 2D Tuzoq-Platformer.\n\nPoki Web Edition.\n"
			+ "Barcha 60 ta darajadan muvaffaqiyatli o'tib, yulduzlarni to'plang!"
		),
		
		# Level & Trap Editor
		"btn_editor": "ZONA YARATISH",
		"editor_title": "ZONA VA TUZOQ MUHARRIRI",
		"btn_test": "SINOV",
		"btn_stop_test": "TAHRIRGA QAYTISH",
		"btn_save": "SAQLASH",
		"btn_load": "YUKLASH",
		"btn_clear": "TOZALASH",
		"btn_erase": "O'CHIRGICH",
		"saved_notice": "Daraja muvaffaqiyatli saqlandi!",
		"cleared_notice": "Maydon tozalandi!",
		"slot_label": "Slot %d",
		"slot_saved": "Saqlangan",
		"slot_empty": "Bo'sh",
		"loaded_notice": "Slot %d yuklandi!",
		"reloaded_notice": "Slot %d qayta yuklandi!",
		"btn_reload_current": "Qayta yuklash (bekor qilish)",
		"test_won_notice": "Sinov muvaffaqiyatli yakunlandi! Darvoza ishlamoqda.",
		"tool_platform": "Pol",
		"tool_trap_floor": "Tuzoq pol",
		"tool_spikes": "Tikan",
		"tool_saw": "Arra",
		"tool_crusher": "Ezuvchi",
		"tool_spring": "Prujina",
		"tool_fake_door": "Soxta eshik",
		"tool_falling": "Stalaktit",
		"tool_laser": "Lazer",
		"tool_door": "Darvoza",
		"tool_player": "O'yinchi",
		"tool_circular_saw": "Aylanuvchi arra",
		"tool_spike_ball": "Tikanli shar",
		"tool_pop_up_spikes": "Otiluvchi tikan"
	},
	
	"ru": {
		# Title Screen
		"game_title": "WRONG WAY",
		"game_subtitle": "Арена ловушек и испытаний",
		"btn_start": "СТАРТ",
		
		# Main Menu
		"btn_play": "ИГРАТЬ",
		"btn_continue": "ПРОДОЛЖИТЬ",
		"btn_level_select": "ВЫБОР УРОВНЯ",
		"btn_levels": "ВЫБОР УРОВНЯ",
		"btn_multiplayer": "МУЛЬТИПЛЕЕР",
		"btn_leaderboard": "РЕКОРДЫ",
		"btn_settings": "НАСТРОЙКИ",
		"btn_quit": "ВЫХОД",
		"best_chip": "Рекорд: %s",
		"best_stars": "Звезды: %d / 60",
		"level_header": "УРОВЕНЬ %d",
		"level_complete": "УРОВЕНЬ ПРОЙДЕН",
		"great_job": "Отличная работа!",
		"last_record": "Лучший рекорд: %s",
		"not_available": "Нет данных",
		"multiplayer_title": "МУЛЬТИПЛЕЕР",
		"multiplayer_desc": "Режимы Мультиплеер и Онлайн Гонка скоро появятся!\n\nСейчас доступны уровни Кампании.",
		"leaderboard_title": "ТАБЛИЦА РЕКОРДОВ",
		"leaderboard_desc": "На данном этапе сохраняются локальные рекорды.\n\nВаш лучший рекорд:\n%s",
		"total_time": "Общее время: %dс",
		"leaderboard_total_stars": "Звёзды: %d",
		"leaderboard_total_time": "Общее время: %d секунд",
		"level_time_item": "%d-уровень: %s",
		"tab_global": "ГЛОБАЛ",
		"tab_friends": "ДРУЗЬЯ",
		"player_you": "Вы",
		
		# Settings Modal
		"settings_title": "НАСТРОЙКИ",
		"setting_language": "Язык (Language):",
		"setting_music": "Фоновая музыка (BGM):",
		"setting_music_volume": "Громкость музыки:",
		"setting_sound": "Звуковые эффекты (SFX):",
		"setting_sound_volume": "Громкость звуков:",
		"setting_shake": "Тряска экрана:",
		"status_on": "ВКЛ",
		"status_off": "ВЫКЛ",
		"controls_title": "Управление и Клавиатура:",
		"controls_desc": "Движение: A / D или ◄ / ► (Сенсор)\nПрыжок: W / Пробел / ▲\nРывок (Dash): Shift / J\nБыстрый рестарт: R\nПауза / Меню: Esc / P\nПолный экран: F11",
				"btn_close": "Закрыть",
		"btn_customize_controls": "Настроить кнопки",
		"controls_customizer_title": "НАСТРОЙКА КНОПОК",
		"controls_customizer_hint": "Перетащите кнопки в любое удобное место",
		"btn_reset_default": "По умолчанию",
		
		# Level Select
		"map_title": "УРОВНИ",
		"chapter_1_title": "ГЛАВА 1: УРОВНИ",
		"chapter_2_title": "ГЛАВА 2: УРОВНИ",
		"chapter_3_title": "ГЛАВА 3: УРОВНИ",
		"chapter_4_title": "ГЛАВА 4: ЗОЛОТОЙ КАНЬОН",
		"chapter_5_title": "ГЛАВА 5: АДСКАЯ БЕЗДНА",
		"chapter_4_desc": "Обновление с Пустыней и Каньоном скоро выйдет!",
		"chapter_5_desc": "Обновление с Лавой и Вулканом скоро выйдет!",
		"chapter_nav_btn": "ГЛАВА %d",
		"coming_soon_caps": "СКОРО",
		"more_levels_soon": "Новые уровни появятся в следующем обновлении!",
		"chapter_2_locked": "ГЛАВА 2 ЗАБЛОКИРОВАНА",
		"chapter_2_unlock_req": "Пройдите 1-ю главу (уровень 20), чтобы открыть",
		"chapter_3_locked": "ГЛАВА 3 ЗАБЛОКИРОВАНА",
		"chapter_3_unlock_req": "Пройдите 2-ю главу (уровень 40), чтобы открыть",
		"btn_chapter_1": "ГЛАВА 1",
		"btn_chapter_2": "ГЛАВА 2",
		"btn_chapter_3": "ГЛАВА 3",
		"btn_back": "Назад",
		"btn_menu": "Меню",
		"lvl_label": "LVL %d",
		"lvl_ad_unlock": "Открыть",
		"lvl_locked": "Блок",
		"total_stars": "%d / 180",
		"lock_title": "УРОВЕНЬ ЗАБЛОКИРОВАН",
		"lock_need_attempt": "Чтобы открыть этот уровень за рекламу, сначала сыграйте уровень %d!",
		"lock_cooldown": "Пропуск за рекламу доступен раз в 3 уровня!\n(Последний пропуск: %d-й lvl. Следующий доступен: %d-й уровень)",
		"lock_need_stars": "Чтобы открыть этот уровень, получите минимум 2 звезды на уровне %d!",
		"lock_must_open_earlier": "Сначала откройте предыдущие уровни!",
		"zone2_title": "ЗОНА 2: ТУМАННЫЙ ЗАМОК",
		"zone2_req": "Требуется 50 звезд для открытия",
		"zone2_status": "%d / 50",
		
		# Game HUD
		"hud_level": "LEVEL %d",
		"hud_time": "%.2fs",
		"hud_deaths": "%d смертей",
		"btn_jump": "ПРЫЖОК",
		"btn_hud_menu": "Меню",
		
		# Pause Modal
		"pause_title": "ПАУЗА",
		"btn_resume": "ПРОДОЛЖИТЬ",
		"btn_restart": "Начать заново",
		"btn_map": "Карта",
		"btn_home": "Главное меню",
		
		# Win Overlay
		"win_title": "%d-Й УРОВЕНЬ ПРОЙДЕН!",
		"win_3_stars": "Идеально! Следующий уровень открыт!",
		"win_2_stars": "Отличный результат! Следующий уровень открыт!",
		"win_1_star": "Получите минимум 2 звезды, чтобы открыть следующий уровень!",
		"win_time": "Время: %.2fs",
		"win_deaths": "%d смертей",
		"win_stats": "Время: %ds   •   Смертей: %d",
		"win_all_60_complete": "ВСЕ 60 УРОВНЕЙ ПРОЙДЕНЫ! 🎉\nГЛАВЫ 4 И 5 СКОРО",
		"btn_next_lvl": "СЛЕДУЮЩИЙ УРОВЕНЬ",

		# Splash Hints & Game Info
		"hint_0": "Проверка настроек игры...",
		"hint_1": "Скрытие механизмов ловушек...",
		"hint_2": "Никогда слепо не верьте полам и дверям...",
		"hint_3": "Все готово. Добро пожаловать во тьму!",
		"game_desc_info": (
			"Wrong Way — 2D платформер с ловушками.\n\nPoki Web Edition.\n"
			+ "Пройдите все 60 уровней и соберите звезды!"
		),
		
		# Level & Trap Editor
		"btn_editor": "РЕДАКТОР ЗОНЫ",
		"editor_title": "РЕДАКТОР ЗОН И ЛОВУШЕК",
		"btn_test": "ТЕСТ",
		"btn_stop_test": "В РЕДАКТОР",
		"btn_save": "СОХРАНИТЬ",
		"btn_load": "ЗАГРУЗИТЬ",
		"btn_clear": "ОЧИСТИТЬ",
		"btn_erase": "ЛАСТИК",
		"saved_notice": "Уровень успешно сохранен!",
		"cleared_notice": "Поле очищено!",
		"slot_label": "Слот %d",
		"slot_saved": "Сохранен",
		"slot_empty": "Пусто",
		"loaded_notice": "Слот %d загружен!",
		"reloaded_notice": "Слот %d перезагружен!",
		"btn_reload_current": "Перезагрузить (отменить)",
		"test_won_notice": "Тест пройден! Дверь работает отлично.",
		"tool_platform": "Пол",
		"tool_trap_floor": "Ловушка",
		"tool_spikes": "Шипы",
		"tool_saw": "Пила",
		"tool_crusher": "Пресс",
		"tool_spring": "Пружина",
		"tool_fake_door": "Обманка",
		"tool_falling": "Обвал",
		"tool_laser": "Лазер",
		"tool_door": "Выход",
		"tool_player": "Игрок",
		"tool_circular_saw": "Круглая пила",
		"tool_spike_ball": "Шар с шипами",
		"tool_pop_up_spikes": "Выдвижные шипы"
	},
	
	"en": {
		# Title Screen
		"game_title": "WRONG WAY",
		"game_subtitle": "Arena of traps and trials",
		"btn_start": "START",
		
		# Main Menu
		"btn_play": "PLAY",
		"btn_continue": "CONTINUE",
		"btn_level_select": "LEVEL SELECT",
		"btn_levels": "LEVEL SELECT",
		"btn_multiplayer": "MULTIPLAYER",
		"btn_leaderboard": "LEADERBOARD",
		"btn_settings": "SETTINGS",
		"btn_quit": "QUIT",
		"best_chip": "Best: %s",
		"best_stars": "Stars: %d / 60",
		"level_header": "LEVEL %d",
		"level_complete": "LEVEL COMPLETE",
		"great_job": "Great Job!",
		"last_record": "Best record: %s",
		"not_available": "None",
		"multiplayer_title": "MULTIPLAYER MODE",
		"multiplayer_desc": "Multiplayer and Online Race modes coming soon!\n\nCurrently, Campaign levels are active.",
		"leaderboard_title": "LEADERBOARD",
		"leaderboard_desc": "Currently local records are tracked.\n\nYour overall best time:\n%s",
		"total_time": "Total Time: %ds",
		"leaderboard_total_stars": "Stars: %d",
		"leaderboard_total_time": "Total Time: %d seconds",
		"level_time_item": "Level %d: %s",
		"tab_global": "GLOBAL",
		"tab_friends": "FRIENDS",
		"player_you": "You",
		
		# Settings Modal
		"settings_title": "SETTINGS",
		"setting_language": "Language:",
		"setting_music": "Background Music (BGM):",
		"setting_music_volume": "Music Volume:",
		"setting_sound": "Sound Effects (SFX):",
		"setting_sound_volume": "SFX Volume:",
		"setting_shake": "Screen Shake:",
		"status_on": "ON",
		"status_off": "OFF",
		"controls_title": "Controls & Keyboard:",
		"controls_desc": "Movement: A / D or ◄ / ► (Touch D-Pad)\nJump: W / Space / ▲\nDash: Shift / J\nQuick Restart: R\nPause / Menu: Esc / P\nFullscreen: F11",
				"btn_close": "Close",
		"btn_customize_controls": "Customize Controls",
		"controls_customizer_title": "CUSTOMIZE CONTROLS",
		"controls_customizer_hint": "Drag buttons to your preferred positions",
		"btn_reset_default": "Reset Default",
		
		# Level Select
		"map_title": "LEVELS",
		"chapter_1_title": "CHAPTER 1: LEVELS",
		"chapter_2_title": "CHAPTER 2: LEVELS",
		"chapter_3_title": "CHAPTER 3: LEVELS",
		"chapter_4_title": "CHAPTER 4: GOLDEN CANYON",
		"chapter_5_title": "CHAPTER 5: INFERNO ABYSS",
		"chapter_4_desc": "Desert and Canyon update coming soon!",
		"chapter_5_desc": "Lava and Volcano update coming soon!",
		"chapter_nav_btn": "CHAPTER %d",
		"coming_soon_caps": "COMING SOON",
		"more_levels_soon": "New levels will be available in the next update!",
		"chapter_2_locked": "CHAPTER 2 LOCKED",
		"chapter_2_unlock_req": "Complete Chapter 1 (Level 20) to unlock",
		"chapter_3_locked": "CHAPTER 3 LOCKED",
		"chapter_3_unlock_req": "Complete Chapter 2 (Level 40) to unlock",
		"btn_chapter_1": "CH. 1",
		"btn_chapter_2": "CH. 2",
		"btn_chapter_3": "CH. 3",
		"btn_back": "Back",
		"btn_menu": "Menu",
		"lvl_label": "LVL %d",
		"lvl_ad_unlock": "Unlock",
		"lvl_locked": "Locked",
		"total_stars": "%d / 180",
		"lock_title": "LEVEL LOCKED",
		"lock_need_attempt": "To unlock this level with an ad, try playing level %d first!",
		"lock_cooldown": "Ad skip is allowed once every 3 levels!\n(Last skipped: lvl %d. Next available at level %d)",
		"lock_need_stars": "To unlock this level, earn at least 2 stars on level %d!",
		"lock_must_open_earlier": "First unlock earlier levels!",
		"zone2_title": "ZONE 2: MISTY CASTLE",
		"zone2_req": "Requires 50 stars to unlock",
		"zone2_status": "%d / 50",
		
		# Game HUD
		"hud_level": "LEVEL %d",
		"hud_time": "%.2fs",
		"hud_deaths": "%d deaths",
		"btn_jump": "JUMP",
		"btn_hud_menu": "Menu",
		
		# Pause Modal
		"pause_title": "PAUSED",
		"btn_resume": "RESUME",
		"btn_restart": "Restart",
		"btn_map": "Map",
		"btn_home": "Main Menu",
		
		# Win Overlay
		"win_title": "LEVEL %d COMPLETED!",
		"win_3_stars": "Perfect run! Next level unlocked!",
		"win_2_stars": "Great job! Next level unlocked!",
		"win_1_star": "Earn at least 2 stars to unlock the next level!",
		"win_time": "Time: %.2fs",
		"win_deaths": "%d deaths",
		"win_stats": "Time: %ds   •   Deaths: %d",
		"win_all_60_complete": "ALL 60 LEVELS COMPLETED! 🎉\nCHAPTER 4 & 5 COMING SOON",
		"btn_next_lvl": "NEXT LEVEL",

		# Splash Hints & Game Info
		"hint_0": "Checking game settings...",
		"hint_1": "Concealing all trap mechanisms...",
		"hint_2": "Never blindly trust floors or doors...",
		"hint_3": "Everything is ready. Welcome to the shadows!",
		"game_desc_info": (
			"Wrong Way — Competitive 2D Trap-Platformer.\n\nPoki Web Edition.\n"
			+ "Beat all 60 levels and collect all the stars!"
		),
		
		# Level & Trap Editor
		"btn_editor": "ZONE CREATOR",
		"editor_title": "ZONE & TRAP CREATOR",
		"btn_test": "PLAYTEST",
		"btn_stop_test": "RETURN TO EDIT",
		"btn_save": "SAVE",
		"btn_load": "LOAD",
		"btn_clear": "CLEAR",
		"btn_erase": "ERASER",
		"saved_notice": "Level saved successfully!",
		"cleared_notice": "Arena cleared!",
		"slot_label": "Slot %d",
		"slot_saved": "Saved",
		"slot_empty": "Empty",
		"loaded_notice": "Slot %d loaded!",
		"reloaded_notice": "Slot %d reloaded!",
		"btn_reload_current": "Reload (Revert)",
		"test_won_notice": "Playtest passed! Exit door reached.",
		"tool_platform": "Floor",
		"tool_trap_floor": "Trap Floor",
		"tool_spikes": "Spikes",
		"tool_saw": "Saw",
		"tool_crusher": "Crusher",
		"tool_spring": "Spring",
		"tool_fake_door": "Fake Door",
		"tool_falling": "Stalactite",
		"tool_laser": "Laser",
		"tool_door": "Exit Door",
		"tool_player": "Player",
		"tool_circular_saw": "Circular Saw",
		"tool_spike_ball": "Spike Ball",
		"tool_pop_up_spikes": "Pop-up Spikes"
	},
	
	"tr": {
		# Title Screen
		"game_title": "WRONG WAY",
		"game_subtitle": "Tuzaklar ve engeller arenası",
		"btn_start": "BAŞLA",
		
		# Main Menu
		"btn_play": "OYNA",
		"btn_continue": "DEVAM ET",
		"btn_level_select": "SEVİYELER",
		"btn_levels": "SEVİYELER",
		"btn_multiplayer": "ÇOK OYUNCULU",
		"btn_leaderboard": "LİDERLİK",
		"btn_settings": "AYARLAR",
		"btn_quit": "ÇIKIŞ",
		"best_chip": "Rekor: %s",
		"best_stars": "Yıldızlar: %d / 60",
		"level_header": "SEVİYE %d",
		"level_complete": "SEVİYE TAMAMLANDI",
		"great_job": "Harika iş!",
		"last_record": "En iyi rekor: %s",
		"not_available": "Yok",
		"multiplayer_title": "ÇOK OYUNCULU MOD",
		"multiplayer_desc": "Çok Oyunculu ve Çevrimiçi Yarış çok yakında!\n\nŞu anda Macera seviyeleri aktiftir.",
		"leaderboard_title": "LİDERLİK TABLOSU",
		"leaderboard_desc": "Şu anda yerel rekorlar kaydedilmektedir.\n\nEn iyi süreniz:\n%s",
		"total_time": "Toplam Süre: %ds",
		"leaderboard_total_stars": "Yıldızlar: %d",
		"leaderboard_total_time": "Toplam Süre: %d saniye",
		"level_time_item": "%d. Seviye: %s",
		"tab_global": "GLOBAL",
		"tab_friends": "ARKADAŞLAR",
		"player_you": "Sen",
		
		# Settings Modal
		"settings_title": "AYARLAR",
		"setting_language": "Dil (Language):",
		"setting_music": "Fon Müziği (BGM):",
		"setting_music_volume": "Müzik Düzeyi:",
		"setting_sound": "Ses Efektleri (SFX):",
		"setting_sound_volume": "Efekt Düzeyi:",
		"setting_shake": "Ekran Sarsıntısı:",
		"status_on": "AÇIK",
		"status_off": "KAPALI",
		"controls_title": "Kontroller ve Klavye:",
		"controls_desc": "Hareket: A / D veya ◄ / ► (Dokunmatik)\nZıplama: W / Boşluk / ▲\nHızlı Koşu (Dash): Shift / J\nHızlı Yeniden Başlat: R\nMenü / Duraklat: Esc / P\nTam Ekran: F11",
				"btn_close": "Kapat",
		"btn_customize_controls": "Tuşları Özelleştir",
		"controls_customizer_title": "TUŞLARI ÖZELLEŞTİR",
		"controls_customizer_hint": "Düğmeleri istediğiniz yere sürükleyin",
		"btn_reset_default": "Sıfırla",
		
		# Level Select
		"map_title": "SEVİYELER",
		"chapter_1_title": "BÖLÜM 1: SEVİYELER",
		"chapter_2_title": "BÖLÜM 2: SEVİYELER",
		"chapter_3_title": "BÖLÜM 3: SEVİYELER",
		"chapter_4_title": "BÖLÜM 4: ALTIN KANYON",
		"chapter_5_title": "BÖLÜM 5: CEHENNEM ÇUKURU",
		"chapter_4_desc": "Çöl ve Kanyon güncellemesi çok yakında!",
		"chapter_5_desc": "Lav ve Volkan güncellemesi çok yakında!",
		"chapter_nav_btn": "BÖLÜM %d",
		"coming_soon_caps": "YAKINDA",
		"more_levels_soon": "Yeni seviyeler bir sonraki güncellemede sunulacak!",
		"chapter_2_locked": "2. BÖLÜM KİLİTLİ",
		"chapter_2_unlock_req": "Kilidi açmak için 1. bölümü (20. seviye) tamamlayın",
		"chapter_3_locked": "3. BÖLÜM KİLİTLİ",
		"chapter_3_unlock_req": "Kilidi açmak için 2. bölümü (40. seviye) tamamlayın",
		"btn_chapter_1": "BÖLÜM 1",
		"btn_chapter_2": "BÖLÜM 2",
		"btn_chapter_3": "BÖLÜM 3",
		"btn_back": "Geri",
		"btn_menu": "Menü",
		"lvl_label": "LVL %d",
		"lvl_ad_unlock": "Aç",
		"lvl_locked": "Kilitli",
		"total_stars": "%d / 180",
		"lock_title": "SEVİYE KİLİTLİ",
		"lock_need_attempt": "Bu seviyeyi reklamla açmak için önce %d seviyesini oynayın!",
		"lock_cooldown": "Reklamla seviye atlama her 3 seviyede bir kullanılabilir!\n(Son açılan: %d. seviye. Sıradaki: %d. seviye)",
		"lock_need_stars": "Bu seviyeyi açmak için %d seviyesinde en az 2 yıldız alın!",
		"lock_must_open_earlier": "Önce önceki seviyeleri açın!",
		"zone2_title": "BÖLGE 2: SİSLİ KALE",
		"zone2_req": "Açmak için 50 yıldız gerekli",
		"zone2_status": "%d / 50",
		
		# Game HUD
		"hud_level": "LEVEL %d",
		"hud_time": "%.2fs",
		"hud_deaths": "%d ölüm",
		"btn_jump": "ZIPLA",
		"btn_hud_menu": "Menü",
		
		# Pause Modal
		"pause_title": "DURAKLATILDI",
		"btn_resume": "DEVAM ET",
		"btn_restart": "Yeniden Dene",
		"btn_map": "Harita",
		"btn_home": "Ana Menü",
		
		# Win Overlay
		"win_title": "%d. SEVİYE TAMAMLANDI!",
		"win_3_stars": "Kusursuz! Sonraki seviye açıldı!",
		"win_2_stars": "Harika! Sonraki seviye açıldı!",
		"win_1_star": "Sonraki seviyeyi açmak için en az 2 yıldız kazanın!",
		"win_time": "Süre: %.2fs",
		"win_deaths": "%d ölüm",
		"win_stats": "Süre: %ds   •   Ölüm: %d",
		"win_all_60_complete": "TÜM 60 SEVİYE TAMAMLANDI! 🎉\nBÖLÜM 4 VE 5 YAKINDA",
		"btn_next_lvl": "SONRAKİ SEVİYE",

		# Splash Hints & Game Info
		"hint_0": "Oyun ayarları kontrol ediliyor...",
		"hint_1": "Tüm tuzak mekanizmaları gizleniyor...",
		"hint_2": "Zeminlere ve kapılara asla körü körüne güvenmeyin...",
		"hint_3": "Her şey hazır. Karanlık dünyaya hoş geldiniz!",
		"game_desc_info": (
			"Wrong Way — 2D Tuzak Platform Oyunu.\n\nPoki Web Edition.\n"
			+ "Tüm 60 seviyeyi geçin ve yıldızları toplayın!"
		),
		
		# Level & Trap Editor
		"btn_editor": "BÖLGE OLUŞTUR",
		"editor_title": "BÖLGE VE TUZAK DÜZENLEYİCİ",
		"btn_test": "TEST ET",
		"btn_stop_test": "DÜZENLEMEYE DÖN",
		"btn_save": "KAYDET",
		"btn_load": "YÜKLE",
		"btn_clear": "TEMİZLE",
		"btn_erase": "SİLGİ",
		"saved_notice": "Seviye başarıyla kaydedildi!",
		"cleared_notice": "Alan temizlendi!",
		"slot_label": "Slot %d",
		"slot_saved": "Kaydedildi",
		"slot_empty": "Boş",
		"loaded_notice": "Slot %d yüklendi!",
		"reloaded_notice": "Slot %d yeniden yüklendi!",
		"btn_reload_current": "Yeniden yükle (geri al)",
		"test_won_notice": "Test başarılı! Çıkış kapısına ulaşıldı.",
		"tool_platform": "Zemin",
		"tool_trap_floor": "Tuzak Zemin",
		"tool_spikes": "Diken",
		"tool_saw": "Testere",
		"tool_crusher": "Ezici",
		"tool_spring": "Yay",
		"tool_fake_door": "Sahte Kapı",
		"tool_falling": "Düşen Taş",
		"tool_laser": "Lazer",
		"tool_door": "Çıkış",
		"tool_player": "Oyuncu",
		"tool_circular_saw": "Döner Testere",
		"tool_spike_ball": "Dikenli Top",
		"tool_pop_up_spikes": "Tuzak Diken"
	}
}

func _ready() -> void:
	# Load language from SaveManager if available
	var sm = get_node_or_null("/root/SaveManager")
	if sm and "current_language" in sm:
		current_language = sm.current_language

func set_language(lang_code: String) -> void:
	if not LANGUAGES.has(lang_code):
		return
	current_language = lang_code
	var sm = get_node_or_null("/root/SaveManager")
	if sm and "current_language" in sm:
		sm.current_language = lang_code
		sm.save_data()
	language_changed.emit(lang_code)

func t(key: String, args: Array = []) -> String:
	var dict: Dictionary = STRINGS.get(current_language, STRINGS["en"])
	var text: String = dict.get(key, key)
	if not args.is_empty():
		return text % args
	return text

# Convenience shorthand
func tr_text(key: String, args: Array = []) -> String:
	return t(key, args)

