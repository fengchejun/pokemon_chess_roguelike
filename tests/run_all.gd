extends SceneTree

## 全量检查：解析所有脚本 + 运行 tests/cases 下的用例。
## 用法：godot --headless --path . --script res://tests/run_all.gd [-- 过滤词]

const TestContextLib = preload("res://tests/lib/test_context.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var filter := ""
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() > 0:
		filter = String(user_args[0])
	var failures: Array = []
	# 1) 全量解析检查
	var script_paths: Array = []
	_collect_scripts("res://scripts", script_paths)
	_collect_scripts("res://tests/cases", script_paths)
	for path in script_paths:
		var script = load(path)
		if script == null or not (script as GDScript).can_instantiate():
			failures.append("解析失败: " + path)
	print("解析检查：%d 个脚本" % script_paths.size())
	if not failures.is_empty():
		for message in failures:
			print("  [FAIL] " + message)
		print("RUN_ALL 失败（解析阶段）：%d 项" % failures.size())
		quit(1)
		return
	# 2) 用例
	var t := TestContextLib.new(self)
	var case_dir := DirAccess.open("res://tests/cases")
	var case_names: Array = []
	if case_dir != null:
		case_names = case_dir.get_files()
	case_names.sort()
	var executed := 0
	for case_name in case_names:
		if not String(case_name).ends_with(".gd"):
			continue
		var path := "res://tests/cases/" + String(case_name)
		if filter != "" and not String(case_name).contains(filter):
			continue
		var script = load(path)
		if script == null or not (script as GDScript).can_instantiate():
			failures.append("用例解析失败: " + path)
			continue
		print("  运行 %s ..." % String(case_name))
		var instance = script.new()
		instance.run(t)
		executed += 1
		if not t.finished.has(t.current):
			failures.append("用例未完成（运行中存在错误）: " + String(case_name))
		else:
			t.current = ""
	print("运行用例：%d 个，检查点 %d 个" % [executed, t.checks])
	if not t.failures.is_empty():
		print("失败 %d 项：" % t.failures.size())
		for message in t.failures:
			print("  [FAIL] " + message)
		print("RUN_ALL 失败")
		quit(1)
		return
	print("RUN_ALL 通过")
	quit(0)


func _collect_scripts(root: String, out: Array) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	for file in dir.get_files():
		if String(file).ends_with(".gd"):
			out.append(root + "/" + String(file))
	for sub in dir.get_directories():
		_collect_scripts(root + "/" + String(sub), out)
