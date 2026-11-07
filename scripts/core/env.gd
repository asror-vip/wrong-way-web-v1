class_name Env
extends RefCounted

## Env: Safe Environment Stub for Poki Web Edition
## Provides offline fallbacks so no network calls or missing-class errors occur.

static func get_var(_key: String, default_val: String = "") -> String:
	return default_val

static func get_supabase_url() -> String:
	return ""

static func get_supabase_anon_key() -> String:
	return ""

