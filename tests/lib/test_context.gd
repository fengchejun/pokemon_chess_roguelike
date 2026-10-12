class_name TestContext
extends RefCounted

var tree: SceneTree = null
var failures: Array = []
var checks: int = 0
var current: String = ""
var finished: Array = []


func _init(tree_ref: SceneTree = null) -> void:
	tree = tree_ref


func begin(case_name: String) -> void:
	current = case_name
	print("— %s" % case_name)


func finish() -> void:
	if not finished.has(current):
		finished.append(current)


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append("%s: %s" % [current, label])
		print("  [FAIL] %s" % label)


func eq(actual, expected, label: String) -> void:
	check(actual == expected, "%s（期望 %s，实际 %s）" % [label, str(expected), str(actual)])


func approx(actual: float, expected: float, label: String, epsilon: float = 0.0001) -> void:
	check(absf(actual - expected) <= epsilon, "%s（期望 %s，实际 %s）" % [label, str(expected), str(actual)])
