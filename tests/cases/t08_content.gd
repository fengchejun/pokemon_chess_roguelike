extends RefCounted

## 验收扫描：无反应断言、数据完整性

const BANNED_TERMS := ["导电", "蒸汽", "冰面", "湿地", "焦土", "岩浆化"]


func run(t: TestContext) -> void:
	t.begin("内容扫描")
	_t_no_removed_reactions(t)
	_t_data_integrity(t)
	_t_element_toolkit(t)
	t.finish()


func _t_no_removed_reactions(t: TestContext) -> void:
	var offenders: Array = []
	var files: Array = []
	_collect_files("res://scripts", [".gd"], files)
	_collect_files("res://scenes", [".tscn"], files)
	for path in files:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var text := file.get_as_text()
		file.close()
		for term in BANNED_TERMS:
			if text.contains(term):
				offenders.append("%s 含「%s」" % [path, term])
	t.eq(offenders, [], "已删除的元素反应与地形在代码与文案中不存在：%s" % str(offenders))


func _collect_files(root: String, suffixes: Array, out: Array) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	for file in dir.get_files():
		for suffix in suffixes:
			if String(file).ends_with(String(suffix)):
				out.append(root + "/" + String(file))
	for sub in dir.get_directories():
		_collect_files(root + "/" + String(sub), suffixes, out)


func _t_data_integrity(t: TestContext) -> void:
	for skill_id in SkillDB.DEFS:
		var def: Dictionary = SkillDB.DEFS[skill_id]
		t.check(Elements.LIST.has(String(def.get("element", ""))), "技能 %s 属性有效" % skill_id)
		t.check(String(def.get("desc", "")) != "", "技能 %s 有描述" % skill_id)
	for species_id in SpeciesDB.SPECIES:
		var species: Dictionary = SpeciesDB.SPECIES[species_id]
		for skill_id in species.get("skills", []):
			t.check(SkillDB.DEFS.has(String(skill_id)), "物种 %s 的技能 %s 存在" % [species_id, skill_id])
	t.eq(SpeciesDB.STARTER_TEAM.size(), 5, "初始队伍覆盖五属性")
	t.eq(BattleDB.count(), Balance.BATTLES_PER_RUN, "关卡数量与一局长度一致")
	for battle_index in BattleDB.count():
		var cfg := BattleDB.config_for(battle_index)
		var occupied := {}
		for pair in cfg["enemies"]:
			var species_id := String(pair[0])
			var cell: Vector2i = pair[1]
			t.check(SpeciesDB.SPECIES.has(species_id), "第 %d 场敌人物种 %s 存在" % [battle_index + 1, species_id])
			t.check(GridSpec.is_inside(cell), "第 %d 场敌人出生格在棋盘内" % (battle_index + 1))
			t.check(not occupied.has(cell), "第 %d 场敌人出生格不重复" % (battle_index + 1))
			occupied[cell] = true
			t.check(not Balance.DEPLOY_CELLS.has(cell), "第 %d 场敌人不与部署区重叠" % (battle_index + 1))
			t.check(cell != cfg["nest_cell"], "第 %d 场敌人不与巢穴重叠" % (battle_index + 1))
		for species_id in cfg["reinforce"]:
			t.check(SpeciesDB.SPECIES.has(String(species_id)), "第 %d 场增援物种存在" % (battle_index + 1))
		t.check(int(cfg["lethal_budget"]) >= 1, "第 %d 场致死预算合理" % (battle_index + 1))
	for card_id in CardDB.CARDS:
		var card: Dictionary = CardDB.CARDS[card_id]
		t.check(String(card.get("anchor", "")) != "", "环境卡 %s 有对应位置" % card_id)
		t.check(String(card.get("effect", "")) != "", "环境卡 %s 有站位增益" % card_id)
		t.check((card.get("effect_types", {}) as Dictionary).size() > 0, "环境卡 %s 有已接线的效果键" % card_id)


func _t_element_toolkit(t: TestContext) -> void:
	var damage_skills: Array = ["fire_seed", "water_flow", "discharge", "drain", "push", "rock_smash", "rock_create"]
	var displace_skills: Array = ["flame_charge", "water_flow", "volt_step", "push"]
	var terrain_skills: Array = ["water_flow", "rain_dance", "seed_sow", "rock_create", "rock_smash"]
	for element in Elements.LIST:
		var has_damage := false
		var has_displace := false
		var has_terrain := false
		for skill_id in SkillDB.DEFS:
			if String(SkillDB.DEFS[skill_id].get("element", "")) != element:
				continue
			if damage_skills.has(skill_id):
				has_damage = true
			if displace_skills.has(skill_id):
				has_displace = true
			if terrain_skills.has(skill_id):
				has_terrain = true
		var categories := int(has_damage) + int(has_displace) + int(has_terrain)
		t.check(categories >= 2, "属性 %s 至少提供两类工具（伤害/位移/地形）" % element)
