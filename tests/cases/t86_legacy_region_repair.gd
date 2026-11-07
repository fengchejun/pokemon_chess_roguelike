extends RefCounted

const Region = preload("res://scripts/run/region_state.gd")


func run(t: TestContext) -> void:
	t.begin("残缺区域旧档迁移")
	var snapshot := {"version": 11, "fields": {"round": 4}}
	var raw_region := {
		"floor": 1,
		"theme": "fire",
		"visits": 3,
		"active_node": "battle_1",
		"support_triggered": true,
		"camp_invaded": true,
		"notifications": "broken",
		"nodes": {
			"battle_1": {"snapshot": snapshot},
			"battle_2": "broken",
			"camp": {},
			"boss": {"type": "invalid"},
			"future_node": {"mode": "event"},
		},
	}
	var region := Region.from_dict(raw_region)
	t.check(region != null, "残缺节点不会导致区域迁移失败")
	if region == null:
		t.finish()
		return
	t.eq(region.nodes.size(), Region.AREA_CELLS.size() + 1, "缺失的标准节点被补齐且未知扩展节点保留")
	t.eq(region.node_type("battle_1"), "battle", "战斗节点按 ID 推断类型")
	t.eq(region.node_mode("battle_1"), "battle", "战斗节点获得默认模式")
	t.eq(region.node_type("camp"), "camp", "营地节点按 ID 推断类型")
	t.eq(region.node_type("boss"), "boss", "无效首领类型回退为 ID 推断值")
	t.eq(region.node_type("event_1"), "event", "缺失探索节点补齐为标准类型")
	t.eq(region.node_type("battle_2"), "battle", "非字典节点被安全忽略")
	t.eq(region.node_type("future_node"), "event", "未知扩展节点使用安全默认类型")
	t.eq(region.nodes["battle_1"].get("snapshot"), snapshot, "旧节点战斗快照完整保留")
	t.eq(region.active_node, "battle_1", "有效活动节点保持不变")
	t.check(not region.at_camp_scene, "活动节点非营地时不会误开营地场景")
	t.eq(region.visits, 3, "区域访问次数保持不变")
	t.check(region.notifications.is_empty(), "错误的通知类型回退为空数组")

	var invalid_shape := Region.from_dict({
		"floor": 0,
		"theme": "water",
		"active_node": "missing",
		"visit_pending": true,
		"nodes": [],
	})
	t.eq(invalid_shape.active_node, "camp", "无效活动节点回退到营地")
	t.check(not invalid_shape.visit_pending, "活动节点修复后清除悬空的进入状态")
	t.eq(invalid_shape.node_type("battle_4"), "battle", "非字典节点集合仍恢复标准区域")

	var run := RunState.new_run(8601)
	var data := run.to_dict()
	data["version"] = 11
	data["region_data"] = raw_region.duplicate(true)
	data["pending_region_entry_backup"] = raw_region.duplicate(true)
	var restored := RunState.from_dict(data)
	t.check(restored != null, "整局旧档可完成区域迁移")
	if restored == null:
		t.finish()
		return
	t.check(not restored.record_by_uid(1).is_empty(), "区域迁移失败不会吞掉本局成员")
	t.check(not restored.region_data.is_empty(), "主区域数据完成修复")
	t.check(not restored.pending_region_entry_backup.is_empty(), "待取消进入备份完成修复")
	t.eq(Region.from_dict(restored.region_data).node_type("battle_1"), "battle", "整局迁移后的主区域节点类型有效")
	t.eq(Region.from_dict(restored.pending_region_entry_backup).node_type("boss"), "boss", "整局迁移后的备份首领类型有效")

	var malformed_data := run.to_dict()
	malformed_data["region_data"] = "broken"
	malformed_data["pending_region_entry_backup"] = []
	var malformed := RunState.from_dict(malformed_data)
	t.check(malformed != null and malformed.region_data.is_empty() and malformed.pending_region_entry_backup.is_empty(), "错误区域容器类型被安全清空")
	t.finish()
