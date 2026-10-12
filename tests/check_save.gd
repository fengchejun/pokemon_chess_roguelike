extends SceneTree

## 存档自检：读取 user:// 存档并统计修复前后缺失 uid 的记录数。


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var path := SaveSystem.DEFAULT_PATH
	if not FileAccess.file_exists(path):
		print("SAVE CHECK: no save file at ", path)
		quit(0)
		return
	var run := SaveSystem.load_run(path)
	if run == null:
		print("SAVE CHECK: load failed (corrupted or version mismatch)")
		quit(1)
		return
	var missing := 0
	for group in [run.carried, run.storage, run.pending_captures]:
		for record in (group as Array):
			if not (record as Dictionary).has("uid"):
				missing += 1
	print("SAVE CHECK: carried=%d storage=%d pending=%d missing_uid_after_repair=%d" % [
		run.carried.size(), run.storage.size(), run.pending_captures.size(), missing,
	])
	quit(0)
