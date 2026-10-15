class_name SaveSystem
extends RefCounted

## 存档：单槽位 JSON。濒死状态跨读档持久（只能经基地休养恢复），异常退出不复活。

const DEFAULT_PATH := "user://save_v1.json"


static func has_save(path: String = DEFAULT_PATH) -> bool:
	return FileAccess.file_exists(path)


static func save_run(run: RunState, path: String = DEFAULT_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("无法写入存档：%s" % path)
		return false
	file.store_string(JSON.stringify(run.to_dict(), "\t"))
	file.close()
	return true


static func load_run(path: String = DEFAULT_PATH) -> RunState:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return null
	var data: Dictionary = parsed
	if not [1, 2, RunState.SAVE_VERSION].has(int(data.get("version", -1))):
		return null
	return RunState.from_dict(data)


static func delete_save(path: String = DEFAULT_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
