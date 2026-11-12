extends RefCounted


func run(t: TestContext) -> void:
	t.begin("终局仓库保留选择")
	_collection_defaults(t)
	_final_ui_partial_retention(t)
	_no_storage_finishes_directly(t)
	t.finish()


func _collection_defaults(t: TestContext) -> void:
	var run := RunState.new_run(8501)
	var stored: Dictionary = run._make_record("rock_starter")
	run.storage.append(stored)
	var stored_uid := int(stored["uid"])
	var stored_source := _source(run, stored_uid)
	var profile := CollectionState.defaults()
	var added := profile.absorb_run(run)
	t.eq(added, run.carried.size(), "普通结算只新增携带队伍")
	t.check(profile.owned.all(func(entry: Dictionary) -> bool: return String(entry.get("source", "")) != stored_source), "普通结算不登记仓库成员")
	t.eq(profile.absorb_run(run, [stored_uid]), 1, "明确选择仓库成员后才登记收藏")
	t.check(profile.owned.any(func(entry: Dictionary) -> bool: return String(entry.get("source", "")) == stored_source), "勾选的仓库成员进入永久收藏")
	profile.settle_run(run)
	t.check(profile.owned.all(func(entry: Dictionary) -> bool: return String(entry.get("source", "")) != stored_source), "最终未勾选会清理曾提前登记的仓库记录")


func _final_ui_partial_retention(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(8502)
	var retained: Dictionary = app.run._make_record("rock_starter")
	var discarded: Dictionary = app.run._make_record("water_starter")
	app.run.storage.append(retained)
	app.run.storage.append(discarded)
	var retained_uid := int(retained["uid"])
	var discarded_uid := int(discarded["uid"])
	var retained_source := _source(app.run, retained_uid)
	var discarded_source := _source(app.run, discarded_uid)
	## 模拟旧版已经提前写入收藏的仓库记录，最终未勾选时必须被撤销。
	app.collection.absorb_run(app.run, [discarded_uid])
	app.show_run_end()
	t.eq(app.current_screen.name, "RunEndScreen", "最终结算进入结局页")
	var overlay: Control = app.current_screen.find_child("RunEndStorageRetention", true, false)
	t.check(overlay != null, "存在仓库成员时自动弹出最终保留选择")
	var back: Button = app.current_screen.find_child("BackToMenuButton", true, false)
	t.check(back != null and back.disabled, "未完成保留选择前不能返回主菜单")
	var confirm: Button = app.current_screen.find_child("ConfirmRunEndStorageButton", true, false)
	t.check(confirm != null and confirm.text.contains("全部抛弃"), "默认不勾选任何仓库成员")
	t.check(app.collection.owned.all(func(entry: Dictionary) -> bool: return String(entry.get("source", "")) != retained_source), "未确认前不提前登记勾选目标")
	var retain_check: CheckBox = app.current_screen.find_child("RetainStorage_%d" % retained_uid, true, false)
	t.check(retain_check != null, "仓库成员提供独立保留勾选框")
	if retain_check != null:
		retain_check.button_pressed = true
	if confirm != null:
		confirm.pressed.emit()
	t.check(app.run.storage.is_empty(), "确认后清理本局仓库")
	t.check(back != null and not back.disabled, "完成最终选择后允许返回主菜单")
	t.check(overlay != null and not overlay.visible, "确认后关闭保留选择层")
	t.check(app.collection.owned.any(func(entry: Dictionary) -> bool: return String(entry.get("source", "")) == retained_source), "勾选成员写入永久收藏")
	t.check(app.collection.owned.all(func(entry: Dictionary) -> bool: return String(entry.get("source", "")) != discarded_source), "未勾选成员从永久收藏排除")
	t.check(app.collection.owned.any(func(entry: Dictionary) -> bool: return String(entry.get("source", "")) == _source(app.run, int(app.run.carried[0]["uid"]))), "携带队伍自动进入永久收藏")
	var summary: Label = app.current_screen.find_child("RunEndSummary", true, false)
	t.check(summary != null and summary.text.contains("最终保留选择"), "结局摘要记录保留与抛弃数量")
	var owned_before: int = app.collection.owned.size()
	var repeated: Dictionary = app.resolve_run_end_storage([retained_uid])
	t.check(bool(repeated.get("ok", false)), "重复确认最终选择可安全结束")
	t.eq(app.collection.owned.size(), owned_before, "重复确认不会复制永久收藏")
	app.queue_free()


func _no_storage_finishes_directly(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(8503)
	app.show_run_end()
	var back: Button = app.current_screen.find_child("BackToMenuButton", true, false)
	t.check(back != null and not back.disabled, "无仓库成员时返回主菜单不被阻塞")
	t.check(app.current_screen.find_child("RunEndStorageRetention", true, false) == null, "无仓库成员时不弹出保留选择")
	app.queue_free()


func _source(run: RunState, uid: int) -> String:
	return "run:%d:%d" % [run.seed, uid]
