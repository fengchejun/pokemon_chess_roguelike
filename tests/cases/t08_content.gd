extends RefCounted

## 验收扫描：合并后七系技能数据完整性。


func run(t: TestContext) -> void:
	t.begin("内容扫描")
	_t_data_integrity(t)
	_t_element_toolkit(t)
	t.finish()


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
	for element in Elements.LIST:
		var found := false
		for species_id in SpeciesDB.SPECIES:
			var species: Dictionary = SpeciesDB.SPECIES[species_id]
			if String(species.get("element", "")) == element and (species.get("skills", []) as Array).size() >= 2:
				found = true
		t.check(found, "属性 %s 至少有一种具备两项技能的怪物" % element)
