class_name RunState
extends RefCounted

## 一局游戏的持久状态：出战名单、仓库、经验、环境卡、强化、战损记录与统计。

const SAVE_VERSION := 18
var essence: int = 0
var trainer_items: Dictionary = {}
var sold_monster_uids: Array = []
const MAX_EQUIPPED_SKILLS := Balance.SKILL_SLOTS
const RETIRED_GENERIC_UPGRADES := ["move_plus", "max_hp_plus", "direct_guard", "collision_guard", "grass_resilience", "recovery_plus"]

const MONSTER_UPGRADES := {
	"push_distance": {
		"name": "推击距离 +1",
		"desc": "推击基础直伤 +3，并额外推开 1 格；中途碰撞照常结算。",
		"key": "push_distance",
		"value": 2,
		"damage_bonus": 3,
		"requires_skill": "rock_push",
	},
	"rock_create_width": {
		"name": "造岩扩建",
		"desc": "造岩横排由 3 格扩为 4 格；命中单位时基础直伤 +3。",
		"key": "rock_create_width",
		"value": 4,
		"damage_bonus": 3,
		"requires_skill": "rock_create",
	},
	"rain_radius": {
		"name": "造雨扩张",
		"desc": "造雨术保留原九格，四个方向各扩一格，形成13格菱形。",
		"key": "rain_radius_bonus",
		"value": 1,
		"requires_skill": "rain_call",
	},
	"fireball_damage": {"name": "炽烈火球", "desc": "火球术中心基础直伤 +5，外围伤害不变。", "key": "fireball_damage", "value": 5, "damage_bonus": 0, "requires_skill": "fire_burst"},
	"flame_jet_length": {"name": "长焰", "desc": "喷射火焰基础直伤 +3，直线长度由 3 格增至 4 格。", "key": "flame_jet_length", "value": 1, "damage_bonus": 3, "requires_skill": "flame_jet"},
	"water_flow_push": {"name": "急流", "desc": "水炮基础直伤 +4，击退距离仍为 1 格。", "key": "water_flow_push", "value": 0, "damage_bonus": 4, "requires_skill": "water_flow"},
	"drain_range": {"name": "蔓延吸取", "desc": "吸取基础直伤 +3，射程由 2 格增至 3 格。", "key": "drain_range", "value": 1, "damage_bonus": 3, "requires_skill": "drain"},
	"herbal_heal_amount": {"name": "丰茂药草", "desc": "我方药草治疗每个目标回复 13 点生命。", "key": "herbal_heal_amount", "value": 5, "requires_skill": "herbal_heal"},
	"ice_shard_damage": {"name": "尖锐冰锥", "desc": "冰锥基础直伤 +5。", "key": "ice_shard_damage", "value": 5, "damage_bonus": 5, "requires_skill": "ice_shard"},
	"water_magic_burst_damage": {"name": "爆水", "desc": "水魔爆十字范围与中心额外伤害不变，中心基础直伤 +4、外侧基础直伤 +4。", "key": "water_magic_burst_damage", "value": 4, "damage_bonus": 4, "requires_skill": "water_magic_burst"},
	"ice_breath_damage": {"name": "冻息", "desc": "冰之息基础直伤 +4。", "key": "ice_breath_damage", "value": 4, "damage_bonus": 4, "requires_skill": "ice_breath"},
	"ice_ground_reach": {"name": "冰面延展", "desc": "我方冰封大地向前延展至第 4 排。", "key": "ice_ground_reach", "value": 1, "requires_skill": "frozen_ground"},
	"electric_arc_damage": {"name": "高压传导", "desc": "放电基础直伤 +3；水域传导每两格减2，最低4。", "key": "electric_arc_damage", "value": 3, "damage_bonus": 3, "requires_skill": "electric_arc"},
	"tailwind_reach": {"name": "扩域磁场", "desc": "磁场加速半径从 2 格扩大至 3 格，覆盖自身周围 7×7 区域。", "key": "tailwind_reach", "value": 1, "requires_skill": "tailwind"},
	"magnet_pull_reach": {"name": "强磁牵引", "desc": "磁吸的可见目标范围由四正交 5 格扩大至 6 格。", "key": "magnet_pull_reach", "value": 1, "requires_skill": "magnet_pull"},
	"glare_radius": {"name": "眩目扩散", "desc": "眩光范围由自身周围 3×3 扩大至 5×5。", "key": "glare_radius", "value": 1, "requires_skill": "glare"},
	"electromagnetic_laser_damage": {"name": "高能镭射", "desc": "电磁镭射基础直伤 +5。", "key": "electromagnetic_laser_damage", "value": 5, "damage_bonus": 5, "requires_skill": "electromagnetic_laser"},
	"electric_resonance_power": {"name": "共振增幅", "desc": "电共鸣每层感电蓄伤由 3 提高至 5，每层麻痹由 5 提高至 8。", "key": "electric_resonance_power", "value": 2, "requires_skill": "electric_resonance"},
	"electric_spark_damage": {"name": "爆裂电花", "desc": "电极火花基础直伤 +5。", "key": "electric_spark_damage", "value": 5, "damage_bonus": 5, "requires_skill": "electric_spark"},
	"flame_charge_damage": {"name": "冲锋余焰", "desc": "闪焰冲锋撞击基础直伤 +5，破障能力 +1。", "key": "flame_charge_damage", "value": 1, "damage_bonus": 5, "requires_skill": "flame_charge"},
	"wild_vines_reach": {"name": "藤蔓延展", "desc": "疯狂藤蔓向前延长至第 3 格。", "key": "wild_vines_reach", "value": 1, "requires_skill": "wild_vines"},
	"lightning_first_shock": {"name": "首击蓄电", "desc": "打雷基础直伤 +5，第一个落点额外施加一层感电。", "key": "lightning_first_shock", "value": 1, "damage_bonus": 5, "requires_skill": "lightning"},
	"rock_break_range": {"name": "长距碎岩", "desc": "碎岩基础直伤 +3，射程由 2 格增至 3 格。", "key": "rock_break_range", "value": 1, "damage_bonus": 3, "requires_skill": "rock_break"},
	"freeze_ray_range": {"name": "远距急冻", "desc": "急冻光线射程由 6 格增至 7 格。", "key": "freeze_ray_range", "value": 1, "requires_skill": "freeze_ray"},
	"double_cast_range": {"name": "双重电力引擎", "desc": "电力引擎可同时选择两名相邻友军，各获得一次额外施法机会；施法距离仍为 1 格。", "key": "double_cast_range", "value": 1, "requires_skill": "double_cast"},
	"fire_amplify_power": {"name": "炽焰积蓄", "desc": "火焰增幅每熄灭一格火焰改为积累 8 点直伤。", "key": "fire_amplify_power", "value": 8, "requires_skill": "fire_amplify"},
	"surf_duration": {"name": "长浪", "desc": "冲浪的地形移动效果延长 1 回合。", "key": "surf_duration", "value": 1, "requires_skill": "surf"},
	"tsunami_damage": {"name": "巨浪", "desc": "海啸基础直伤 +5。", "key": "tsunami_damage", "value": 1, "damage_bonus": 5, "requires_skill": "tsunami"},
	"rock_slide_damage": {"name": "重岩", "desc": "岩崩基础直伤 +5。", "key": "rock_slide_damage", "value": 1, "damage_bonus": 5, "requires_skill": "rock_slide"},
	"earth_shake_damage": {"name": "震源", "desc": "撼地基础直伤 +5，地形塌陷规则不变。", "key": "earth_shake_damage", "value": 1, "damage_bonus": 5, "requires_skill": "earth_shake"},
	"leech_seed_tick_bonus": {"name": "深根", "desc": "寄生每轮伤害与施法者回复上限各 +2。", "key": "leech_seed_tick_bonus", "value": 2, "requires_skill": "leech_seed"},
	"tree_man_hp_bonus": {"name": "坚根守卫", "desc": "大树守卫召唤树人最大生命 +10。", "key": "tree_man_hp_bonus", "value": 10, "requires_skill": "tree_man"},
	"first_aid_healing": {"name": "急救包扎", "desc": "急救回复量由 8 提升至 13。", "key": "first_aid_healing", "value": 5, "requires_skill": "first_aid"},
	"rooted_grass_radius": {"name": "盘根错节", "desc": "落地生根范围由 3×3 扩大至 5×5。", "key": "rooted_grass_radius", "value": 1, "requires_skill": "rooted_grass"},
	"leaf_wind_damage": {"name": "劲风", "desc": "叶之风基础直伤 +4，草丛或藤蔓上的 12 点形态同步提高。", "key": "leaf_wind_damage", "value": 4, "damage_bonus": 4, "requires_skill": "leaf_wind"},
	"antidote_healing": {"name": "浓缩解药", "desc": "解药回复量由 3 提升至 8。", "key": "antidote_healing", "value": 5, "requires_skill": "antidote"},
	"ice_glide_duration": {"name": "长滑", "desc": "溜冰的地形移动效果延长 1 回合。", "key": "ice_glide_duration", "value": 1, "requires_skill": "ice_glide"},
	"mirror_water_moon_duration": {"name": "镜水长明", "desc": "镜花水月的持续效果延长 1 回合。", "key": "mirror_water_moon_duration", "value": 1, "requires_skill": "mirror_water_moon"},
	"flame_rush_damage": {"name": "烈焰掠袭", "desc": "炎袭落点范围的基础直伤 +5。", "key": "flame_rush_damage", "value": 5, "damage_bonus": 5, "requires_skill": "flame_rush"},
	"windfire_breath_damage": {"name": "风火怒号", "desc": "风怒炎息的基础直伤 +5。", "key": "windfire_breath_damage", "value": 5, "damage_bonus": 5, "requires_skill": "windfire_breath"},
	"furnace_fist_training": {"name": "炎炉精修", "desc": "炎炉拳基础直伤 +5，命中回复量 +3。", "key": "furnace_fist_healing", "value": 3, "damage_bonus": 5, "requires_skill": "furnace_fist"},
	"skyfire_damage": {"name": "焚天", "desc": "天火基础直伤 +4。", "key": "skyfire_damage", "value": 4, "damage_bonus": 4, "requires_skill": "skyfire"},
	"combustion_damage": {"name": "爆焰", "desc": "爆燃基础直伤 +4，灼烧目标仍按双倍基础值结算。", "key": "combustion_damage", "value": 4, "damage_bonus": 4, "requires_skill": "combustion"},
	"burn_out_damage": {"name": "焚魂", "desc": "燃尽造成的基础直伤 +5，自身生命代价不变。", "key": "burn_out_damage", "value": 5, "damage_bonus": 5, "requires_skill": "burn_out"},
	"imprint_mastery": {"name": "拓印精通", "desc": "拓印可以复制已经强化的普通技能。", "key": "imprint_upgraded", "value": 1, "requires_skill": "imprint"},
	"mountain_chain_segments": {"name": "群山回响", "desc": "山脉连袭基础段数由 2 增至 3；周围岩障追加段数不变。", "key": "mountain_chain_segments", "value": 1, "requires_skill": "mountain_chain"},
	"mountain_form_radius": {"name": "磐岳延展", "desc": "山岳形态吸收范围由 3×3 扩大至 5×5。", "key": "mountain_form_radius", "value": 1, "requires_skill": "mountain_form"},
	"guard_rock_reinforcement": {"name": "磐岩加固", "desc": "守岩护盾值由 10 提升至 15，破盾伤害仍为 4。", "key": "guard_rock_shield_bonus", "value": 5, "requires_skill": "guard_rock"},
	"rock_blast_damage": {"name": "裂岩增爆", "desc": "岩爆弹主弹基础直伤 +5，两侧分裂弹各 +2。", "key": "rock_blast_damage", "value": 5, "damage_bonus": 5, "fragment_bonus": 2, "requires_skill": "rock_blast"},
	"water_drop_stone_damage": {"name": "水势穿石", "desc": "水滴石穿主伤害 +4，浸湿追加伤害由 3 提高至 5。", "key": "water_drop_stone_damage", "value": 4, "damage_bonus": 4, "wet_bonus": 2, "requires_skill": "water_drop_stone"},
}


static func upgrade_info(upgrade_id: String) -> Dictionary:
	return MONSTER_UPGRADES.get(upgrade_id, {})


static func upgrade_id_for_skill(skill_id: String) -> String:
	for upgrade_id in MONSTER_UPGRADES:
		if String(MONSTER_UPGRADES[upgrade_id].get("requires_skill", "")) == skill_id:
			return String(upgrade_id)
	return ""

static func rebase_upgrade_values(values: Dictionary) -> void:
	for info in MONSTER_UPGRADES.values():
		var key := String(info["key"])
		if values.has(key):
			values[key] = int(info["value"])
	for key in values.keys():
		var info := upgrade_info(String(key))
		if not info.is_empty() and SkillDB.is_placeholder(String(info.get("requires_skill", ""))):
			values[key] = int(info["value"])

static func migrate_snapshot(snapshot: Dictionary) -> Dictionary:
	if snapshot.is_empty():
		return {}
	var state := BattleSnapshot.load_state(snapshot)
	return BattleSnapshot.save_state(state) if state != null else snapshot.duplicate(true)

static func migrate_region_snapshots(region: Dictionary) -> void:
	for node in (region.get("nodes", {}) as Dictionary).values():
		if not (node.get("snapshot", {}) as Dictionary).is_empty():
			node["snapshot"] = migrate_snapshot(node["snapshot"])

var seed: int = 0
const Region = preload("res://scripts/run/region_state.gd")
const FoodDB = preload("res://scripts/data/food_db.gd")
var region_mode: bool = false
var region_data: Dictionary = {}
var pending_region_entry_backup: Dictionary = {}
var pending_region_battle_index: int = 0
var food: int = 3
var food_inventory: Dictionary = {"basic": 3}
var battle_index: int = 0
var floor_themes: Array = []
var offered_floor_themes: Array = []
var in_battle: bool = false
var battle_snapshot: Dictionary = {}
var run_failed: bool = false # 训练家倒下后整局终止；旧存档默认未失败。
var debug_tainted: bool = false # 使用 F7 修改过本局；仍可存档，但不进入永久收藏统计。
var trainer_xp: int = 0
var trainer_level: int = 1
var trainer_hp: int = 35
var carried: Array = []
var storage: Array = []
var pending_captures: Array = []
var next_uid: int = 1
var exp: int = 0
var cards: Array = [] # 旧存档字段；新规则不再免费选取站位卡。
var environment_deck: Array = [] # 旧存档字段；读取时按已确认规则清空。
var environment_reward_pending: bool = false # 旧结算字段。
var reward_inventory: Array = []
var relic_stacks: Dictionary = {}
var invasion_level_bonus: int = 0
var pending_invasion_bonus: int = 0
var claimed_supply_battles: Array = []
var recovered_supply_battles: Array = []
var selected_reward_item: String = ""
var preview_used_reward_item: String = ""
var preview_modifications: Array = []
var preview_deploy_positions: Dictionary = {}
var pending_reward_choices: int = 0
var reward_choice_index: int = 0
var settlement_pending: bool = false
var last_settlement: Dictionary = {}
var pending_bonus_choices: int = 0
var upgrades: Dictionary = {}
var upgrades_taken: Array = []
var xp_upgrades_claimed: int = 0
var deaths: Array = []
var stats := {"kills": 0, "captures": 0, "victories": 0, "escapes": 0, "retreats": 0}
var captured_applied: int = 0
var deployed_uids: Array = []
var pending_supply: bool = false
var options := {"threat_preview": false, "capture_low_hp": false, "capture_field_join": false}


static func new_run(seed_value: int = 0, starting_collection: Array = []) -> RunState:
	var run := RunState.new()
	run.seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system() * 1000000.0)
	run.trainer_hp = int(SpeciesDB.get_species("trainer").get("hp", 6))
	if starting_collection.is_empty():
		## 兼容旧代码与旧存档；实际新局由收藏界面传入三只。
		for species_id in SpeciesDB.STARTER_TEAM:
			var record := run._make_record(String(species_id))
			var opening_skills: Array = SpeciesDB.skills_of(String(species_id))
			if not opening_skills.is_empty():
				record["known_skills"] = [opening_skills[0]]
				record["equipped_skills"] = [opening_skills[0]]
			run.carried.append(record)
	else:
		for source in starting_collection:
			var record := run._make_record(String(source["species_id"]))
			record["collection_id"] = int(source["id"])
			record["affinity"] = maxi(0, int(source.get("affinity", 0)))
			var opening_skills: Array = SpeciesDB.skills_of(String(source["species_id"]))
			var chosen_skill := String(source.get("starting_skill_id", ""))
			if not opening_skills.has(chosen_skill) and not opening_skills.is_empty():
				chosen_skill = String(opening_skills[0])
			if chosen_skill != "":
				record["known_skills"] = [chosen_skill]
				record["equipped_skills"] = [chosen_skill]
			run.carried.append(record)
	run.refresh_theme_offers()
	return run


func supply_due() -> bool:
	## 每完成 SUPPLY_INTERVAL 场战斗进入补给点。
	if battle_index <= 0 or battle_index >= Balance.BATTLES_PER_RUN:
		return false
	return battle_index % Balance.SUPPLY_INTERVAL == 0


func apply_supply_recovery() -> Dictionary:
	## 补给点：训练家恢复 50% 生命上限（四舍五入，至少 1 点）。
	var trainer_max := trainer_max_hp()
	var before := trainer_hp
	if recovered_supply_battles.has(battle_index):
		return {"trainer_from": before, "trainer_to": before}
	var amount := maxi(1, roundi(float(trainer_max) * Balance.SUPPLY_TRAINER_RECOVERY_RATIO))
	trainer_hp = mini(trainer_max, trainer_hp + amount)
	recovered_supply_battles.append(battle_index)
	return {"trainer_from": before, "trainer_to": trainer_hp}


func _make_record(species_id: String, hp: int = -1) -> Dictionary:
	var species_skills := SpeciesDB.skills_of(species_id)
	var starting_level := 1 + floor_index() * 2
	var starting_max_hp := MonsterProgression.max_hp(species_id, starting_level)
	var record := {
		"uid": next_uid,
		"species_id": species_id,
		"hp": mini(hp, starting_max_hp) if hp > 0 else starting_max_hp,
		"level": starting_level,
		"xp": MonsterProgression.threshold_for_level(starting_level),
		"affinity": 0,
		"known_skills": species_skills.duplicate(),
		"equipped_skills": species_skills.slice(0, MAX_EQUIPPED_SKILLS),
		"upgrades": {},
		"upgrades_taken": [],
		"claimed_even_levels": [],
		"level_choices": {},
		"trait_upgrade_claimed": false,
	}
	next_uid += 1
	return record


func record_by_uid(uid: int) -> Dictionary:
	for record in carried:
		if int(record["uid"]) == uid:
			return record
	return {}


func owned_record_by_uid(uid: int) -> Dictionary:
	var record := record_by_uid(uid)
	if not record.is_empty():
		return record
	for stored in storage:
		if int(stored["uid"]) == uid:
			return stored
	return {}


func monster_max_hp(record: Dictionary) -> int:
	return MonsterProgression.max_hp_for_record(record)


func battle_seed() -> int:
	return hash("battle:%d:%d" % [seed, battle_index])


func floor_index() -> int:
	return BattleDB.floor_of(battle_index)


func level_cap_for_floor(_index: int = -1) -> int:
	# Compatibility API: floor-specific level caps have been removed.
	return MonsterProgression.MAX_LEVEL


func apply_floor_level_caps() -> Array:
	var unlocked: Array = []
	var cap := level_cap_for_floor()
	var old_trainer_level := trainer_level
	trainer_level = maxi(trainer_level, mini(cap, MonsterProgression.level_for_xp(trainer_xp)))
	if trainer_hp > 0:
		trainer_hp += MonsterProgression.max_hp("trainer", trainer_level) - MonsterProgression.max_hp("trainer", old_trainer_level)
	for record in carried + storage:
		var before := int(record.get("level", 1))
		MonsterProgression.unlock_for_level_cap(record, cap)
		var after := int(record.get("level", 1))
		if after > before:
			unlocked.append({"uid": int(record["uid"]), "from": before, "to": after})
	return unlocked


func battle_in_floor() -> int:
	return BattleDB.local_battle_of(battle_index)


func needs_theme_choice() -> bool:
	return not run_finished() and floor_themes.size() <= floor_index()


func refresh_theme_offers() -> void:
	if needs_theme_choice():
		offered_floor_themes = BattleDB.theme_offers(seed, floor_index(), floor_themes)
	else:
		offered_floor_themes.clear()


func choose_floor_theme(theme_id: String) -> bool:
	if not needs_theme_choice() or not offered_floor_themes.has(theme_id):
		return false
	floor_themes.append(theme_id)
	offered_floor_themes.clear()
	return true


func current_theme() -> String:
	if floor_themes.size() <= floor_index():
		return ""
	return String(floor_themes[floor_index()])


func get_region():
	if region_data.is_empty():
		region_data = (preload("res://scripts/run/exploration_flow.gd").create(floor_index(), current_theme()) if bool(options.get("exploration_v2", false)) and floor_index() == 0 else Region.create_floor(floor_index(), current_theme())).to_dict()
	var region = Region.from_dict(region_data)
	if region.flow_version != 2:
		Merchant.ensure_region(region, seed)
	# Skill upgrades now belong exclusively to the merchant.
	for node in region.nodes.values():
		node.erase("mentor")
	region_data = region.to_dict()
	return region


func enter_region_node(id: String) -> bool:
	var region = get_region()
	var previous := region_data.duplicate(true)
	var previous_index := battle_index
	var pressure_before: int = region.boss_level_bonus
	if not region.record_entry(id):
		return false
	invasion_level_bonus += region.boss_level_bonus - pressure_before
	if region.node_mode(id) != "camp":
		pending_invasion_bonus = region.boss_level_bonus - pressure_before
		pending_region_entry_backup = previous
		pending_region_battle_index = previous_index
	region_data = region.to_dict()
	var kind := region.node_mode(id)
	if kind == "battle" or kind == "boss":
		var slot := 5 if kind == "boss" else maxi(0, int(id.trim_prefix("battle_")) - 1)
		battle_index = region.floor_index * 6 + slot
		apply_floor_level_caps()
	return true


func cancel_region_entry() -> void:
	if pending_region_entry_backup.is_empty() or not battle_snapshot.is_empty():
		return
	invasion_level_bonus -= pending_invasion_bonus
	pending_invasion_bonus = 0
	if preview_used_reward_item != "" and RewardDB.is_consumable(preview_used_reward_item):
		reward_inventory.append(preview_used_reward_item)
	preview_used_reward_item = ""
	selected_reward_item = ""
	preview_modifications.clear()
	preview_deploy_positions.clear()
	region_data = pending_region_entry_backup.duplicate(true)
	battle_index = pending_region_battle_index
	pending_region_entry_backup.clear()


func rest_at_region_camp() -> bool:
	return bool(rest_with_food({"basic": 3}).get("ok", false))


func needs_camp_rest() -> bool:
	if trainer_hp < trainer_max_hp():
		return true
	for record in carried:
		if int(record["hp"]) < monster_max_hp(record):
			return true
	return false


func add_food(kind: String, amount: int) -> void:
	if FoodDB.definition(kind).is_empty() or amount <= 0:
		return
	food_inventory[kind] = int(food_inventory.get(kind, 0)) + amount
	food = total_food()


func total_food() -> int:
	var result := 0
	for count in food_inventory.values():
		result += maxi(0, int(count))
	return result


func camp_facility_destroyed(id: String) -> bool:
	if not region_mode:
		return false
	var region = get_region()
	var facilities: Dictionary = BattleSnapshot.decode(region.nodes["camp"].get("facilities", {}))
	return bool(facilities.get(id, {}).get("destroyed", false))


func camp_service_available(id: String) -> bool:
	var region = get_region()
	if region.active_node != "camp" or region.node_mode("camp") != "camp":
		return false
	return not camp_facility_destroyed(id)


func rest_with_food(selection: Dictionary) -> Dictionary:
	if not camp_service_available("fire"):
		return {"ok": false, "reason": "篝火已毁或营地被占，本层无法恢复。"}
	var region = get_region()
	if region.active_node != "camp" or region.node_mode(region.active_node) != "camp":
		return {"ok": false, "reason": "请先进入营地。"}
	if not needs_camp_rest():
		return {"ok": false, "reason": "队伍当前无需恢复。"}
	if selection.size() != 1:
		return {"ok": false, "reason": "请选择一种食物。"}
	var kind := String(selection.keys()[0])
	var definition: Dictionary = FoodDB.definition(kind)
	if definition.is_empty() or String(definition.get("effect", "")) != "full_party_heal":
		return {"ok": false, "reason": "这种食物尚不能用于篝火休息。"}
	var cost := int(definition["rest_cost"])
	if int(selection[kind]) != cost:
		return {"ok": false, "reason": "本次需要选择 %d 份%s。" % [cost, definition["name"]]}
	if int(food_inventory.get(kind, 0)) < cost:
		return {"ok": false, "reason": "%s不足 %d 份。" % [definition["name"], cost]}
	var results: Array = []
	results.append("训练家 HP %d → %d" % [trainer_hp, trainer_max_hp()])
	food_inventory[kind] = int(food_inventory[kind]) - cost
	food = total_food()
	trainer_hp = trainer_max_hp()
	for record in carried:
		var before := int(record["hp"])
		var healed := ceili(monster_max_hp(record) / 2.0) if before <= 0 else monster_max_hp(record)
		results.append("%s HP %d → %d" % [SpeciesDB.name_of(String(record["species_id"])), before, healed])
		record["hp"] = healed
	return {"ok": true, "spent": {kind: cost}, "results": results}


func battle_config() -> Dictionary:
	var cfg := BattleDB.config_for(battle_index, seed, current_theme())
	cfg["experience_level_cap"] = level_cap_for_floor()
	if region_mode and not region_data.is_empty():
		var region = get_region()
		cfg = cfg.duplicate(true)
		if region.active_node != "" and region.node_mode(region.active_node) == "event":
			cfg["enemies"] = []
			cfg["reinforce"] = []
			cfg["boss_index"] = -1
		elif region.active_node != "":
			var source: Array = cfg["enemies"]
			var count := 5 if region.active_node == "boss" and region.support_triggered else 3
			var chosen: Array = []
			if region.active_node == "boss":
				var boss_index := clampi(int(cfg.get("boss_index", 0)), 0, source.size() - 1)
				chosen.append(source[boss_index])
				for index in source.size():
					if index != boss_index and chosen.size() < count:
						chosen.append(source[index])
				cfg["boss_index"] = 0
			else:
				chosen = source.slice(0, count)
			while chosen.size() < count:
				var pool: Array = cfg.get("reinforce", [])
				chosen.append([pool[chosen.size() % pool.size()] if not pool.is_empty() else source[0][0], Vector2i(-1, -1)])
			cfg["enemies"] = chosen
			cfg["enemy_level_bonus"] = invasion_level_bonus
			cfg["corrupted"] = region.corrupted or bool(region.nodes[region.active_node].get("corrupted", false))
	if region_mode and get_region().flow_version == 2:
		cfg = preload("res://scripts/run/exploration_flow.gd").configure(self, cfg)
	return cfg


func place_region_enemies(cfg: Dictionary, map_data: Dictionary) -> Dictionary:
	if not region_mode:
		return cfg
	var result := cfg.duplicate(true)
	var pairs: Array = result.get("enemies", [])
	var used: Array = []
	for pair in pairs:
		if GridSpec.is_inside(pair[1]) and TerrainDB.can_stand(int(map_data["terrain"][GridSpec.index(pair[1])]), SpeciesDB.element_of(String(pair[0]))) and not used.has(pair[1]) and not (map_data.get("nest_cells", [map_data["nest_cell"]]) as Array).has(pair[1]):
			used.append(pair[1])
		else:
			pair[1] = Vector2i(-1, -1)
	for pair in pairs:
		if GridSpec.is_inside(pair[1]):
			continue
		for cell in GridSpec.all_cells():
			if cell.x < 4 or used.has(cell) or (map_data.get("nest_cells", [map_data["nest_cell"]]) as Array).has(cell) or (map_data.get("deploy_cells", []) as Array).has(cell):
				continue
			if TerrainDB.can_stand(int(map_data["terrain"][GridSpec.index(cell)]), SpeciesDB.element_of(String(pair[0]))):
				pair[1] = cell
				used.append(cell)
				break
	return result


func region_name() -> String:
	return String(battle_config().get("region", "待选择")) if not needs_theme_choice() else "待选择"


func effects() -> Dictionary:
	if preview_used_reward_item.begins_with("position:"):
		return CardDB.active_effects([preview_used_reward_item.trim_prefix("position:")])
	return {}


func map_deck() -> Array:
	if preview_used_reward_item.begins_with("map:"):
		return [preview_used_reward_item.trim_prefix("map:")]
	return []


func mod_points() -> int:
	return Balance.MOD_POINTS if preview_used_reward_item == RewardDB.MOD_ITEM else 0


func use_reward_item_in_preview(reward_id: String) -> bool:
	if preview_used_reward_item != "" or not RewardDB.is_consumable(reward_id) or not reward_inventory.has(reward_id):
		return false
	reward_inventory.erase(reward_id)
	preview_used_reward_item = reward_id
	selected_reward_item = ""
	preview_modifications.clear()
	preview_deploy_positions.clear()
	return true


func select_reward_item(reward_id: String) -> bool:
	if reward_id != "" and (not RewardDB.is_consumable(reward_id) or not reward_inventory.has(reward_id)):
		return false
	selected_reward_item = reward_id
	return true


func consume_selected_reward_item() -> String:
	var used := selected_reward_item
	if used == "":
		return ""
	if not reward_inventory.has(used):
		selected_reward_item = ""
		return ""
	reward_inventory.erase(used)
	selected_reward_item = ""
	return used


func reward_choices() -> Array:
	return RelicDB.offer(seed, battle_index, reward_choice_index, relic_stacks)


func choose_reward(reward_id: String) -> bool:
	if pending_reward_choices <= 0 or not reward_choices().has(reward_id):
		return false
	if not RelicDB.DEFINITIONS.has(reward_id) or RelicDB.rank(relic_stacks, reward_id) >= RelicDB.MAX_RANK:
		return false
	relic_stacks[reward_id] = RelicDB.rank(relic_stacks, reward_id) + 1
	pending_reward_choices -= 1
	reward_choice_index += 1
	return true


func supply_choices() -> Array:
	if not pending_supply or claimed_supply_battles.has(battle_index):
		return []
	return RewardDB.offer(seed, battle_index, 0)


func choose_supply_item(item_id: String) -> bool:
	if not supply_choices().has(item_id):
		return false
	reward_inventory.append(item_id)
	claimed_supply_battles.append(battle_index)
	return true


static func recovery_amount(max_hp: int) -> int:
	## 备战席恢复：生命上限的 50%（四舍五入，至少 1 点）。
	return maxi(1, roundi(float(max_hp) * Balance.BENCH_RECOVERY_RATIO))


func trainer_max_hp() -> int:
	return MonsterProgression.max_hp("trainer", trainer_level)


func build_deploy_units(deploy_uids: Array) -> Array:
	var units: Array = []
	var trainer := CombatUnit.make("trainer", "player", Balance.TRAINER_UID)
	trainer.max_hp = trainer_max_hp()
	trainer.combat_level = trainer_level
	trainer.combat_xp = trainer_xp
	trainer.hp = trainer_hp
	units.append(trainer)
	for uid in deploy_uids:
		var record := record_by_uid(int(uid))
		if record.is_empty():
			continue
		var unit := CombatUnit.make(String(record["species_id"]), "player", int(record["uid"]))
		unit.upgrades = (record.get("upgrades", {}) as Dictionary).duplicate()
		unit.skills = (record.get("equipped_skills", SpeciesDB.skills_of(String(record["species_id"]))) as Array).duplicate()
		unit.combat_xp = int(record.get("xp", 0))
		unit.max_hp = monster_max_hp(record)
		unit.combat_level = clampi(int(record.get("level", 1)), 1, MonsterProgression.MAX_LEVEL)
		unit.hp = mini(int(record["hp"]), unit.max_hp)
		units.append(unit)
	return units


func mark_deployed(deploy_uids: Array) -> void:
	deployed_uids = deploy_uids.duplicate()
	in_battle = true


func sync_from_battle(battle: BattleState) -> void:
	if region_mode and battle.is_camp_map:
		preload("res://scripts/run/camp_map.gd").save(self, battle)
	if region_mode and battle.timed_corruption_triggered:
		var region = get_region()
		if region.nodes.has(region.active_node):
			region.nodes[region.active_node]["corrupted"] = true
		region_data = region.to_dict()
	essence += maxi(0, battle.essence_earned - battle.essence_applied)
	battle.essence_applied = battle.essence_earned
	if region_mode:
		add_food("basic", maxi(0, battle.food_collected - battle.food_applied))
		battle.food_applied = battle.food_collected
	## 战斗中的倒下、捕获与生命变化即时写回（濒死当帧写入）。
	var known_death_uids := {}
	for entry in deaths:
		known_death_uids[int(entry.get("uid", -1))] = true
	for unit in battle.units:
		if unit.side != "player":
			continue
		if unit.summon_owner_uid >= 0:
			continue
		if unit.is_trainer:
			trainer_xp = unit.combat_xp
			trainer_level = unit.combat_level
			trainer_hp = unit.hp
			continue
		var record := record_by_uid(unit.uid)
		if record.is_empty():
			continue
		record["xp"] = unit.combat_xp
		record["level"] = unit.combat_level
		if unit.is_alive():
			record["hp"] = unit.hp
		else:
			record["hp"] = 0
			if not known_death_uids.has(unit.uid):
				known_death_uids[unit.uid] = true
				for entry in battle.deaths:
					if int(entry.get("uid", -1)) == unit.uid:
						deaths.append(entry.duplicate())
						break
	while captured_applied < battle.captured.size():
		var cap: Dictionary = battle.captured[captured_applied]
		if bool(cap.get("on_field", false)) and not battle.ended:
			break
		captured_applied += 1
		stats["captures"] = int(stats["captures"]) + 1
		if bool(cap.get("on_field", false)):
			var survivor := battle.unit_by_uid(int(cap.get("uid", -1)))
			if survivor == null or not survivor.is_alive() or survivor.side != "player":
				continue
			pending_captures.append(_make_record(String(cap["species_id"]), survivor.hp))
		else:
			pending_captures.append(_make_record(String(cap["species_id"]), int(cap["hp"])))


func _add_capture(species_id: String, hp: int) -> void:
	## 便捷注入（测试用）：优先名单、其次仓库、最后进入待处理队列。
	var record := _make_record(species_id, hp)
	if carried.size() < Balance.CARRIED_LIMIT:
		carried.append(record)
	elif region_mode or storage.size() < Balance.STORAGE_LIMIT:
		storage.append(record)
	else:
		pending_captures.append(record)


func pending_capture() -> Dictionary:
	return pending_captures[0] if not pending_captures.is_empty() else {}


func capture_join_team() -> bool:
	if pending_captures.is_empty() or carried.size() >= Balance.CARRIED_LIMIT:
		return false
	var record: Dictionary = pending_captures.pop_front()
	_ensure_uid(record)
	carried.append(record)
	return true


func capture_to_storage() -> bool:
	if camp_facility_destroyed("storage"):
		return false
	if pending_captures.is_empty() or (not region_mode and storage.size() >= Balance.STORAGE_LIMIT):
		return false
	var record: Dictionary = pending_captures.pop_front()
	_ensure_uid(record)
	storage.append(record)
	return true


func capture_replace(replace_uid: int) -> bool:
	## 用捕获替换名单中的一名成员：被替换者进入仓库。
	if region_mode or pending_captures.is_empty() or storage.size() >= Balance.STORAGE_LIMIT:
		return false
	for index in carried.size():
		if int(carried[index]["uid"]) == replace_uid:
			storage.append(carried[index])
			carried.remove_at(index)
			var incoming: Dictionary = pending_captures.pop_front()
			_ensure_uid(incoming)
			carried.append(incoming)
			return true
	return false


func camp_swap(carried_uid: int, stored_uid: int) -> bool:
	if not camp_service_available("storage"):
		return false
	if not region_mode or get_region().active_node != "camp" or not get_region().at_camp_scene:
		return false
	for i in carried.size():
		if int(carried[i]["uid"]) != carried_uid:
			continue
		for j in storage.size():
			if int(storage[j]["uid"]) == stored_uid:
				var old = carried[i]
				carried[i] = storage[j]
				storage[j] = old
				return true
	return false


func _ensure_uid(record: Dictionary) -> void:
	## 兜底：历史/异常来源的记录可能缺少 uid，补发一个保证唯一。
	if not record.has("uid"):
		record["uid"] = next_uid
		next_uid += 1


func capture_discard() -> void:
	if not pending_captures.is_empty():
		pending_captures.pop_front()


func release_storage(uid: int) -> bool:
	if camp_facility_destroyed("storage"):
		return false
	for index in storage.size():
		if int(storage[index]["uid"]) == uid:
			storage.remove_at(index)
			return true
	return false


func battle_kill_xp_for(battle: BattleState, uid: int) -> int:
	return battle_event_xp_for(battle, uid, "kill:")

func battle_capture_xp_for(battle: BattleState, uid: int) -> int:
	return battle_event_xp_for(battle, uid, "capture:")

func battle_event_xp_for(battle: BattleState, uid: int, prefix: String) -> int:
	var total := 0
	for key in battle.experience_events:
		if String(key).begins_with(prefix) and battle.experience_events[key] is Dictionary:
			total += int(battle.experience_events[key].get(uid, 0))
	return total

func unit_by_record_fainted(battle: BattleState, uid: int) -> bool:
	var unit := battle.unit_by_uid(uid)
	return unit == null or not unit.is_alive()


func settle_battle(battle: BattleState) -> Dictionary:
	## 结算口径：胜利 / 强制撤退（失败） / 野生逃离。
	if battle.reward.has("run_settled_outcome"):
		return (battle.reward["run_settled_outcome"] as Dictionary).duplicate(true)
	if not battle.end_reason in ["forced_retreat", "boss_timeout"] and not (region_mode and battle.node_kind == "event"):
		battle.award_battle_experience("participation", 1, true)
	sync_from_battle(battle)
	var outcome := {
		"reason": battle.end_reason,
		"exp": 0,
		"monster_exp": [],
		"escape_penalties": battle.escape_penalties.duplicate(true),
		"trainer_exp": {"gained": int(battle.experience_gains.get(Balance.TRAINER_UID, 0)), "level": trainer_level, "xp": trainer_xp},
		"monster_affinity": [],
		"kills": battle.enemy_kills.size(),
		"captures": battle.captured.size(),
		"nest_exp": 0,
		"boss_blood": 0,
		"captured_names": [],
		"deaths": battle.deaths.duplicate(true),
		"flee_penalty": [],
		"recovery": [],
		"base_rest": [],
		"trainer_from": trainer_hp,
	}
	for entry in battle.captured:
		(outcome["captured_names"] as Array).append(SpeciesDB.name_of(String(entry.get("species_id", ""))))
	var failure := battle.end_reason in ["forced_retreat", "boss_timeout"]
	# 首领之血按捕获首领并获胜发放；回巢阶段拆巢不能取消奖励。
	if battle.end_reason == "victory":
		for entry in battle.captured:
			if not bool(entry.get("was_boss", false)):
				continue
			if bool(entry.get("on_field", false)):
				var survivor := battle.unit_by_uid(int(entry.get("uid", -1)))
				if survivor == null or not survivor.is_alive() or survivor.side != "player":
					continue
			outcome["boss_blood"] = int(outcome["boss_blood"]) + 1
	if failure:
		run_failed = true
		# 本场尚未战后收容的捕获失效；此前已在名单或仓库的收藏保留。
		pending_captures.clear()
		pending_reward_choices = 0
		pending_bonus_choices = 0
	var bonus_points := battle.earned_reward_points(true) if not failure else []
	var bonus_count := bonus_points.size()
	var bonus_earned := bonus_count > 0
	if not failure and (not region_mode or battle.node_kind != "event"):
		var gains: Dictionary = {}
		var original: Dictionary = {}
		for uid in deployed_uids:
			var id := int(uid)
			if not record_by_uid(id).is_empty():
				original[id] = true
				gains[id] = 0
		var shared_bonus := 0
		if bonus_earned:
			shared_bonus += bonus_count
		for current in battle.all_nests():
			if bool(current.get("destroyed_by_player", false)):
				var nest_bonus := Balance.EXP_PER_NEST
				shared_bonus += nest_bonus
				outcome["nest_exp"] = int(outcome["nest_exp"]) + nest_bonus
		for id in original:
			var unit := battle.unit_by_uid(int(id))
			if unit != null and unit.is_alive():
				gains[id] = int(gains[id]) + shared_bonus
		for id in original:
			var record := record_by_uid(int(id))
			var growth := MonsterProgression.award_xp(record, int(gains[id]), level_cap_for_floor())
			growth["gained"] = int(growth["gained"]) + int(battle.experience_gains.get(id, 0))
			record["hp"] = 0 if unit_by_record_fainted(battle, int(id)) else mini(int(record["hp"]), monster_max_hp(record))
			growth["uid"] = int(id)
			growth["name"] = SpeciesDB.name_of(String(record["species_id"]))
			(outcome["monster_exp"] as Array).append(growth)
			outcome["exp"] = int(outcome["exp"]) + int(growth["gained"])
			var affinity_growth := MonsterProgression.award_affinity(record, 1)
			affinity_growth["uid"] = int(id)
			(outcome["monster_affinity"] as Array).append(affinity_growth)
	var kills := 0
	for entry in battle.enemy_kills:
		if bool(entry.get("by_player", false)):
			kills += 1
	stats["kills"] = int(stats["kills"]) + kills
	if bonus_earned:
		pending_bonus_choices += bonus_count
		for point in bonus_points:
			point["credited"] = true
	outcome["bonus_choice_earned"] = bonus_earned
	outcome["bonus_choices_earned"] = bonus_count
	pending_reward_choices += pending_bonus_choices
	pending_bonus_choices = 0
	outcome["pending_reward_choices"] = pending_reward_choices
	match battle.end_reason:
		"victory":
			stats["victories"] = int(stats["victories"]) + 1
		"escape":
			stats["escapes"] = int(stats["escapes"]) + 1
		"forced_retreat":
			## 战斗失败：不结算经验、出战宝可梦生命减半（不致死）并退回基地。
			stats["retreats"] = int(stats["retreats"]) + 1
			var penalty: Array = []
			for uid in deployed_uids:
				var record := record_by_uid(int(uid))
				if record.is_empty():
					continue
				var before := int(record["hp"])
				if before <= 0:
					continue
				var after := maxi(1, ceili(float(before) * 0.5))
				if after < before:
					penalty.append({"name": SpeciesDB.name_of(String(record["species_id"])), "from": before, "to": after})
				record["hp"] = after
			outcome["flee_penalty"] = penalty
	# 出战成员保持战后生命；濒死成员留守一场后恢复到 BENCH_REVIVE_HP。
	outcome["recovery"] = []
	var rested: Array = []
	for record in carried:
		if region_mode:
			continue
		if deployed_uids.has(int(record["uid"])):
			continue
		var max_hp := monster_max_hp(record)
		var before := int(record["hp"])
		var after := mini(max_hp, Balance.BENCH_REVIVE_HP) if before <= 0 else mini(max_hp, before + recovery_amount(max_hp))
		if after > before:
			rested.append({"name": SpeciesDB.name_of(String(record["species_id"])), "from": before, "to": after})
		record["hp"] = after
	outcome["base_rest"] = rested
	var storage_healed := 0
	for record in storage:
		if region_mode:
			continue
		var max_hp := monster_max_hp(record)
		if int(record["hp"]) < max_hp:
			storage_healed += 1
		record["hp"] = max_hp
	outcome["storage_rest"] = storage_healed
	var trainer_max := int(SpeciesDB.get_species("trainer").get("hp", 7))
	outcome["trainer_from"] = trainer_hp
	if not failure and not region_mode:
		trainer_hp = trainer_max
	outcome["trainer_to"] = trainer_hp
	in_battle = false
	environment_reward_pending = false
	settlement_pending = not failure
	last_settlement = outcome.duplicate(true)
	battle.reward["run_settled_outcome"] = outcome.duplicate(true)
	return outcome


func advance_battle() -> void:
	if run_failed:
		return
	settlement_pending = false
	last_settlement = {}
	preview_used_reward_item = ""
	preview_modifications.clear()
	preview_deploy_positions.clear()
	battle_index += 1
	refresh_theme_offers()
	apply_floor_level_caps()


func run_finished() -> bool:
	return battle_index >= Balance.BATTLES_PER_RUN


func run_lost() -> bool:
	if run_failed:
		return true
	if region_mode:
		return trainer_hp <= 0
	## 全员濒死（无可出战成员）即本局结束；濒死成员需留守基地休养一场才能恢复。
	for record in carried:
		if int(record["hp"]) > 0:
			return false
	return true


func available_monster_upgrades(uid: int) -> Array:
	var record := owned_record_by_uid(uid)
	if record.is_empty():
		return []
	var learned: Array = record.get("known_skills", SpeciesDB.skills_of(String(record["species_id"])))
	var taken: Array = record.get("upgrades_taken", [])
	var pool: Array = []
	for skill_id in learned:
		var upgrade_id := upgrade_id_for_skill(String(skill_id))
		if upgrade_id != "" and not taken.has(upgrade_id):
			pool.append(upgrade_id)
	pool.sort()
	return pool


func available_new_skills(uid: int) -> Array:
	var record := owned_record_by_uid(uid)
	if record.is_empty():
		return []
	var known: Array = record.get("known_skills", SpeciesDB.skills_of(String(record["species_id"])))
	var pool: Array = []
	for skill_id in SpeciesDB.skills_of(String(record["species_id"])):
		if not known.has(skill_id) and not SkillDB.is_special(String(skill_id)):
			pool.append(skill_id)
	for skill_id in SkillDB.learnable_ids_for(SpeciesDB.element_of(String(record["species_id"]))):
		if not known.has(skill_id) and not pool.has(skill_id) and not SkillDB.is_special(String(skill_id)):
			pool.append(skill_id)
	return pool


func _expected_level(record: Dictionary) -> int:
	for level in [2, 4, 6, 8, 10]:
		if int(record.get("level", 1)) < level:
			break
		if not (record.get("claimed_even_levels", []) as Array).has(level):
			return level
	return -1


func _claim_level(record: Dictionary, level: int) -> void:
	var claimed: Array = record.get("claimed_even_levels", [])
	if not claimed.has(level):
		claimed.append(level)
	record["claimed_even_levels"] = claimed
	var choices: Dictionary = record.get("level_choices", {})
	choices.erase(str(level))
	record["level_choices"] = choices


func _skill_growth_candidates(record: Dictionary, level: int) -> Array:
	if level not in [2, 4, 6, 8]:
		return []
	var choices: Dictionary = record.get("level_choices", {})
	var key := str(level)
	var pool := available_new_skills(int(record["uid"]))
	if choices.has(key) and choices[key] is Array:
		var cached: Array = choices[key]
		var valid := true
		if cached.size() != mini(3, pool.size()):
			valid = false
		for candidate in cached:
			if not pool.has(candidate):
				valid = false
				break
		if valid:
			return cached.duplicate()
	pool.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("skill-growth:%d:%d:%d" % [seed, int(record["uid"]), level])
	var candidates: Array = []
	while candidates.size() < 3 and not pool.is_empty():
		candidates.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	choices[key] = candidates.duplicate()
	record["level_choices"] = choices
	return candidates


func pending_monster_levels() -> Array:
	var pending: Array = []
	var records: Array = carried.duplicate() + storage.duplicate()
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["uid"]) < int(b["uid"]))
	for record in records:
		for level in [2, 4, 6, 8, 10]:
			if int(record.get("level", 1)) < level:
				break
			if (record.get("claimed_even_levels", []) as Array).has(level):
				continue
			pending.append({"uid": int(record["uid"]), "level": level})
	return pending


func monster_level_choices(uid: int, level: int) -> Array:
	var record := owned_record_by_uid(uid)
	if record.is_empty() or _expected_level(record) != level:
		return []
	return _skill_growth_candidates(record, level)


func monster_engraving_slots(record: Dictionary) -> int:
	if record.is_empty():
		return 0
	return mini(4, floori(float(record.get("level", 1)) / 2.0))


func monster_empty_engraving_slots(record: Dictionary) -> int:
	return maxi(0, monster_engraving_slots(record) - (record.get("upgrades_taken", []) as Array).size())


func take_monster_level_choice(uid: int, level: int, upgrade_id: String) -> bool:
	## 兼容旧调用：技能强化已迁移到技能商人，升级时不再免费发放。
	return false


func enhance_monster_skill(uid: int, level: int, skill_id: String) -> bool:
	return take_monster_level_choice(uid, level, upgrade_id_for_skill(skill_id))


func learn_monster_skill(uid: int, level: int, skill_id: String, replace_skill_id: String = "") -> bool:
	var record := owned_record_by_uid(uid)
	if record.is_empty() or level != _expected_level(record) or level not in [2, 4, 6, 8]:
		return false
	if not monster_level_choices(uid, level).has(skill_id):
		return false
	var known: Array = record.get("known_skills", [])
	var equipped: Array = record.get("equipped_skills", [])
	if known.has(skill_id):
		return false
	if equipped.size() >= MAX_EQUIPPED_SKILLS:
		if replace_skill_id == "" or not equipped.has(replace_skill_id):
			return false
		equipped[equipped.find(replace_skill_id)] = skill_id
	else:
		if replace_skill_id != "":
			return false
		equipped.append(skill_id)
	known.append(skill_id)
	record["known_skills"] = known
	record["equipped_skills"] = equipped
	_claim_level(record, level)
	return true


func claim_monster_trait_upgrade(uid: int, level: int) -> bool:
	var record := owned_record_by_uid(uid)
	if record.is_empty() or level != 10 or _expected_level(record) != 10:
		return false
	record["trait_upgrade_claimed"] = true
	_claim_level(record, level)
	return true


func skip_monster_skill_choice(uid: int, level: int) -> bool:
	var record := owned_record_by_uid(uid)
	if record.is_empty() or level != _expected_level(record) or level not in [2, 4, 6, 8]:
		return false
	if not monster_level_choices(uid, level).is_empty():
		return false
	_claim_level(record, level)
	return true


func apply_merchant_skill_upgrade(uid: int, skill_id: String) -> bool:
	var record := owned_record_by_uid(uid)
	if record.is_empty() or monster_empty_engraving_slots(record) <= 0:
		return false
	var upgrade_id := upgrade_id_for_skill(skill_id)
	var info := upgrade_info(upgrade_id)
	if info.is_empty():
		return false
	var taken: Array = record.get("upgrades_taken", [])
	if taken.has(upgrade_id) or not (record.get("known_skills", []) as Array).has(skill_id):
		return false
	var values: Dictionary = record.get("upgrades", {})
	values[String(info["key"])] = int(info["value"])
	taken.append(upgrade_id)
	record["upgrades"] = values
	record["upgrades_taken"] = taken
	return true


func merchant_skill_upgrade_cost(record: Dictionary) -> int:
	var discount := mini(4, floori(float(record.get("affinity", 0)) / 5.0))
	return maxi(4, 12 - discount)


func equip_monster_skill(uid: int, slot: int, skill_id: String) -> bool:
	var record := owned_record_by_uid(uid)
	if record.is_empty():
		return false
	var known: Array = record.get("known_skills", [])
	var equipped: Array = record.get("equipped_skills", [])
	if slot < 0 or slot > equipped.size() or slot >= MAX_EQUIPPED_SKILLS:
		return false
	if skill_id == "":
		if slot >= equipped.size() or equipped.size() <= 1:
			return false
		equipped.remove_at(slot)
	elif not known.has(skill_id) or (equipped.has(skill_id) and (slot == equipped.size() or equipped[slot] != skill_id)):
		return false
	elif slot == equipped.size():
		equipped.append(skill_id)
	else:
		equipped[slot] = skill_id
	record["equipped_skills"] = equipped
	return true


func pending_upgrades() -> bool:
	return not pending_monster_levels().is_empty()


func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"progression_schema": "hybrid_instant_v1",
		"essence": essence, "trainer_items": trainer_items.duplicate(), "sold_monster_uids": sold_monster_uids.duplicate(),
		"seed": seed,
		"region_mode": region_mode,
		"region_data": region_data.duplicate(true),
		"pending_region_entry_backup": pending_region_entry_backup.duplicate(true),
		"pending_region_battle_index": pending_region_battle_index,
		"food": food,
		"food_inventory": food_inventory.duplicate(),
		"battle_index": battle_index,
		"floor_themes": floor_themes.duplicate(),
		"offered_floor_themes": offered_floor_themes.duplicate(),
		"in_battle": in_battle,
		"battle_snapshot": battle_snapshot.duplicate(true),
		"run_failed": run_failed,
		"debug_tainted": debug_tainted,
		"trainer_hp": trainer_hp, "trainer_xp": trainer_xp, "trainer_level": trainer_level,
		"carried": carried.duplicate(true),
		"storage": storage.duplicate(true),
		"pending_captures": pending_captures.duplicate(true),
		"next_uid": next_uid,
		"cards": cards.duplicate(),
		"environment_deck": environment_deck.duplicate(),
		"environment_reward_pending": environment_reward_pending,
		"reward_inventory": reward_inventory.duplicate(),
		"relic_stacks": relic_stacks.duplicate(),
		"invasion_level_bonus": invasion_level_bonus,
		"pending_invasion_bonus": pending_invasion_bonus,
		"claimed_supply_battles": claimed_supply_battles.duplicate(),
		"recovered_supply_battles": recovered_supply_battles.duplicate(),
		"selected_reward_item": selected_reward_item,
		"preview_used_reward_item": preview_used_reward_item,
		"preview_modifications": preview_modifications.duplicate(true),
		"preview_deploy_positions": BattleSnapshot.encode(preview_deploy_positions),
		"pending_reward_choices": pending_reward_choices,
		"reward_choice_index": reward_choice_index,
		"settlement_pending": settlement_pending,
		"last_settlement": last_settlement.duplicate(true),
		"pending_bonus_choices": pending_bonus_choices,
		"deaths": deaths.duplicate(true),
		"stats": stats.duplicate(),
		"captured_applied": captured_applied,
		"deployed_uids": deployed_uids.duplicate(),
		"pending_supply": pending_supply,
		"options": options.duplicate(),
	}


static func from_dict(data: Dictionary) -> RunState:
	var run := RunState.new()
	run.invasion_level_bonus = int(data.get("invasion_level_bonus", 0))
	run.pending_invasion_bonus = int(data.get("pending_invasion_bonus", 0))
	run.essence = maxi(0, int(data.get("essence", 0)))
	run.trainer_items = (data.get("trainer_items", {}) as Dictionary).duplicate()
	run.sold_monster_uids = (data.get("sold_monster_uids", []) as Array).map(func(uid): return int(uid))
	var version := int(data.get("version", 1))
	var mainline_curve := not data.has("progression_schema") and version >= 12 and data.has("trainer_xp")
	var legacy_growth := version < 2
	var legacy_upgrade_style := version < 3
	var old_hp_scale := version <= 11
	run.seed = int(data.get("seed", 0))
	run.region_mode = bool(data.get("region_mode", false))
	run.region_data = (data.get("region_data", {}) as Dictionary).duplicate(true)
	run.pending_region_entry_backup = (data.get("pending_region_entry_backup", {}) as Dictionary).duplicate(true)
	run.pending_region_battle_index = int(data.get("pending_region_battle_index", 0))
	run.food = maxi(0, int(data.get("food", 3)))
	run.food_inventory = (data.get("food_inventory", {"basic": run.food}) as Dictionary).duplicate()
	run.food = run.total_food()
	run.battle_index = int(data.get("battle_index", 0))
	run.floor_themes = (data.get("floor_themes", []) as Array).duplicate()
	run.offered_floor_themes = (data.get("offered_floor_themes", []) as Array).duplicate()
	if run.offered_floor_themes.is_empty():
		run.refresh_theme_offers()
	run.in_battle = bool(data.get("in_battle", false))
	run.battle_snapshot = (data.get("battle_snapshot", {}) as Dictionary).duplicate(true)
	run.run_failed = bool(data.get("run_failed", false))
	run.debug_tainted = bool(data.get("debug_tainted", false))
	run.trainer_xp = clampi(int(data.get("trainer_xp", 0)), 0, 400)
	run.trainer_level = MonsterProgression.level_for_xp(run.trainer_xp)
	run.trainer_hp = clampi(_migrate_hp(int(data.get("trainer_hp", 6)), _old_max_hp("trainer", 1, version), SpeciesDB.hp_of("trainer")) if old_hp_scale else int(data.get("trainer_hp", SpeciesDB.hp_of("trainer"))), 0, run.trainer_max_hp())
	run.carried = (data.get("carried", []) as Array).duplicate(true)
	run.storage = (data.get("storage", []) as Array).duplicate(true)
	run.pending_captures = (data.get("pending_captures", []) as Array).duplicate(true)
	run.next_uid = int(data.get("next_uid", 1))
	## v1 的全队经验与强化无对应的新规则，迁移时清除。
	run.exp = 0
	run.upgrades = {}
	run.upgrades_taken = []
	run.xp_upgrades_claimed = 0
	run.deaths = (data.get("deaths", []) as Array).duplicate(true)
	run.stats = (data.get("stats", {}) as Dictionary).duplicate()
	run.captured_applied = int(data.get("captured_applied", 0))
	run.deployed_uids = []
	for deployed_uid in data.get("deployed_uids", []):
		run.deployed_uids.append(int(deployed_uid))
	run.pending_supply = bool(data.get("pending_supply", false))
	for relic_id in (data.get("relic_stacks", {}) as Dictionary):
		if RelicDB.DEFINITIONS.has(relic_id):
			run.relic_stacks[relic_id] = clampi(int(data["relic_stacks"][relic_id]), 0, RelicDB.MAX_RANK)
	for battle_number in data.get("claimed_supply_battles", []):
		var number := int(battle_number)
		if number > 0 and number % Balance.SUPPLY_INTERVAL == 0 and not run.claimed_supply_battles.has(number):
			run.claimed_supply_battles.append(number)
	for battle_number in data.get("recovered_supply_battles", []):
		var number := int(battle_number)
		if number > 0 and number % Balance.SUPPLY_INTERVAL == 0 and not run.recovered_supply_battles.has(number):
			run.recovered_supply_battles.append(number)
	run.options.merge((data.get("options", {}) as Dictionary), true)
	run.cards = []
	run.environment_deck = []
	run.environment_reward_pending = false
	run.options.erase("card_mode")
	for reward_id in data.get("reward_inventory", []):
		var id := String(reward_id)
		if RewardDB.is_consumable(id):
			run.reward_inventory.append(id)
	run.selected_reward_item = String(data.get("selected_reward_item", ""))
	if not run.reward_inventory.has(run.selected_reward_item):
		run.selected_reward_item = ""
	run.preview_used_reward_item = String(data.get("preview_used_reward_item", ""))
	if not RewardDB.is_consumable(run.preview_used_reward_item):
		run.preview_used_reward_item = ""
	run.preview_modifications = (data.get("preview_modifications", []) as Array).duplicate(true)
	run.preview_deploy_positions = BattleSnapshot.decode(data.get("preview_deploy_positions", {}))
	run.pending_reward_choices = maxi(0, int(data.get("pending_reward_choices", 0)))
	run.reward_choice_index = maxi(0, int(data.get("reward_choice_index", 0)))
	run.settlement_pending = bool(data.get("settlement_pending", false))
	run.last_settlement = (data.get("last_settlement", {}) as Dictionary).duplicate(true)
	if run.settlement_pending and String(run.last_settlement.get("reason", "")) == "forced_retreat":
		# 旧单槽存档若停在失败结算页，按新规则直接进入本局结束页。
		run.run_failed = true
		run.settlement_pending = false
		run.trainer_hp = 0
	if run.run_failed:
		run.pending_captures.clear()
	run.pending_bonus_choices = maxi(0, int(data.get("pending_bonus_choices", 0)))
	## 修复历史存档：补齐缺失的 uid（否则名单/仓库相关界面会取键失败）。
	for group in [run.carried, run.storage, run.pending_captures]:
		for record in (group as Array):
			var old_hp := int(record.get("hp", 0))
			var old_level := int(record.get("level", 1))
			run._ensure_uid(record)
			if legacy_growth:
				record["level"] = 1
				record["xp"] = 0
				record["affinity"] = 0
			if version < SAVE_VERSION and not data.has("progression_schema") and not legacy_growth:
				MonsterProgression.migrate_mainline_xp(record, mainline_curve)
			MonsterProgression.normalize_record(record, run.level_cap_for_floor())
			run._normalize_record_growth(record, legacy_upgrade_style)
			if mainline_curve or version < 12:
				var claimed_count := mini(4, (record.get("claimed_even_levels", []) as Array).size())
				record["claimed_even_levels"] = MonsterProgression.LEARN_LEVELS.slice(0, claimed_count)
			var new_max_hp := run.monster_max_hp(record)
			record["hp"] = _migrate_hp(old_hp, _old_max_hp(String(record.get("species_id", "")), old_level, version), new_max_hp) if old_hp_scale or (version < 18 and not mainline_curve and not data.has("progression_schema")) else clampi(old_hp, 0, new_max_hp)
	if legacy_growth and run.settlement_pending:
		## 旧结算页中已累计的经验/等级文案不能在迁移后继续展示。
		run.last_settlement["exp"] = 0
		run.last_settlement["monster_exp"] = []
		run.last_settlement["growth_migrated"] = true
	elif legacy_upgrade_style and run.settlement_pending:
		run.last_settlement["upgrade_migrated"] = true
	if version < 12:
		run.battle_snapshot = migrate_snapshot(run.battle_snapshot)
		migrate_region_snapshots(run.region_data)
		migrate_region_snapshots(run.pending_region_entry_backup)
	if version < SAVE_VERSION and not data.has("progression_schema"):
		run.battle_snapshot = run.migrate_progression_snapshot(run.battle_snapshot, run.in_battle, mainline_curve, version)
		for region in [run.region_data, run.pending_region_entry_backup]:
			for node in (region.get("nodes", {}) as Dictionary).values():
				node["snapshot"] = run.migrate_progression_snapshot(node.get("snapshot", {}), false, mainline_curve, version)
	return run


func migrate_progression_snapshot(snapshot: Dictionary, active: bool = false, mainline: bool = false, version: int = 12) -> Dictionary:
	if snapshot.is_empty():
		return snapshot
	var state := BattleSnapshot.load_state(snapshot)
	if state == null:
		return snapshot
	state.experience_level_cap = 10
	if version < 13 and not mainline:
		state.experience_recipients.clear()
	for unit in state.units:
		var old_max: int = unit.max_hp
		var level: int = unit.combat_level
		var converted := {"xp": unit.combat_xp, "level": level}
		MonsterProgression.migrate_mainline_xp(converted, mainline)
		unit.combat_xp = int(converted["xp"])
		unit.combat_level = int(converted["level"])
		if unit.side == "player" and unit.summon_owner_uid < 0:
			var growth_record := owned_record_by_uid(unit.uid)
			if unit.is_trainer:
				unit.combat_xp = trainer_xp
				unit.combat_level = trainer_level
			elif not growth_record.is_empty():
				unit.combat_xp = int(growth_record["xp"])
				unit.combat_level = int(growth_record["level"])
		if not mainline or version < 13:
			var old_base := SpeciesDB.hp_of(unit.species_id) + int((maxi(1, level) - 1) / 2) * 10 if version == 12 else _old_max_hp(unit.species_id, level, version)
			if version == 12 and unit.side == "player" and not unit.is_trainer:
				old_base = SpeciesDB.hp_of(unit.species_id) + int([0, 3, 6, 10, 14, 18, 23, 28, 34, 40][clampi(level, 1, 10) - 1])
			unit.max_hp += MonsterProgression.max_hp(unit.species_id, unit.combat_level) - old_base
			unit.hp = _migrate_hp(unit.hp, old_max, unit.max_hp)
		if unit.side == "player" and unit.summon_owner_uid < 0:
			var record := owned_record_by_uid(unit.uid)
			if unit.is_trainer:
				unit.combat_xp = trainer_xp
				unit.combat_level = trainer_level
			elif not record.is_empty():
				unit.combat_xp = int(record["xp"])
				unit.combat_level = int(record["level"])
			if (unit.is_trainer or not record.is_empty()) and not state.experience_recipients.has(unit.uid):
				state.experience_recipients.append(unit.uid)
	if active and not state.ended and version < 13 and not mainline:
		for event in state.enemy_kills:
			if event.get("killer_side", "player" if event.get("by_player", false) else "") == "player":
				state.award_kill_experience(event, true)
		for event in state.captured:
			state.award_battle_experience("capture:%d" % int(event.get("uid", -1)), Balance.EXP_PER_CAPTURE, true)
		for uid in state.experience_recipients:
			var unit := state.unit_by_uid(uid)
			if unit.is_trainer:
				trainer_xp = unit.combat_xp
				trainer_level = unit.combat_level
				trainer_hp = unit.hp
			else:
				var record := owned_record_by_uid(uid)
				record["xp"] = unit.combat_xp
				record["level"] = unit.combat_level
				record["hp"] = unit.hp
	return BattleSnapshot.save_state(state)


static func _old_max_hp(species_id: String, level: int, version: int) -> int:
	var current_base := SpeciesDB.hp_of(species_id)
	if version <= 4:
		return maxi(1, roundi(float(current_base) / 5.0) + int((maxi(1, level) - 1) / 2))
	if version == 5:
		return maxi(1, current_base * 2 + int((maxi(1, level) - 1) / 2) * 10)
	if version == 12:
		return current_base + int([0, 3, 6, 10, 14, 18, 23, 28, 34, 40][clampi(level, 1, 10) - 1])
	if version >= 7:
		return current_base + int((maxi(1, level) - 1) / 2) * 10
	return maxi(1, current_base + (maxi(1, level) - 1) * 10)


static func _migrate_hp(old_hp: int, old_max_hp: int, new_max_hp: int) -> int:
	if old_hp <= 0:
		return 0
	return clampi(roundi(float(old_hp) / float(maxi(1, old_max_hp)) * float(new_max_hp)), 1, new_max_hp)


func _normalize_record_growth(record: Dictionary, legacy_upgrade_style: bool) -> void:
	var species_id := String(record.get("species_id", ""))
	var base_skills: Array = SpeciesDB.skills_of(species_id).duplicate()
	var known: Array = []
	var source_skills: Array = base_skills if legacy_upgrade_style or not record.has("known_skills") else record.get("known_skills", [])
	var explicitly_known: Array = record.get("known_skills", [])
	for skill_id in source_skills:
		var id := String(skill_id)
		if SkillDB.is_special(id) and not explicitly_known.has(id):
			continue
		if not known.has(id) and not SkillDB.get_def(id).is_empty() and SkillDB.element_of(id) == SpeciesDB.element_of(species_id):
			known.append(id)
	if known.is_empty() and not base_skills.is_empty():
		known.append(base_skills[0])
	var equipped: Array = []
	if not legacy_upgrade_style:
		for skill_id in record.get("equipped_skills", []):
			var id := String(skill_id)
			if known.has(id) and not equipped.has(id) and equipped.size() < MAX_EQUIPPED_SKILLS:
				equipped.append(id)
	if equipped.is_empty():
		equipped = known.slice(0, MAX_EQUIPPED_SKILLS)
	record["known_skills"] = known
	record["equipped_skills"] = equipped
	var old_taken: Array = record.get("upgrades_taken", [])
	var old_claimed: Array = record.get("claimed_even_levels", [])
	var kept_taken: Array = []
	var kept_claimed: Array = []
	if legacy_upgrade_style:
		# v2 的每次升级必为强化，两个数组逐项对应；清除通用项时退还对应等级。
		for index in range(mini(old_taken.size(), old_claimed.size())):
			var upgrade_id := String(old_taken[index])
			var info := upgrade_info(upgrade_id)
			var level := int(old_claimed[index])
			if info.is_empty() or not known.has(String(info.get("requires_skill", ""))) or kept_taken.has(upgrade_id) or not [2, 4, 6, 8, 10].has(level):
				continue
			kept_taken.append(upgrade_id)
			kept_claimed.append(level)
	else:
		# v3 的学招也会领取等级，强化记录与已领取等级不再逐项对应。
		for upgrade_id in old_taken:
			var id := String(upgrade_id)
			var info := upgrade_info(id)
			if not info.is_empty() and known.has(String(info.get("requires_skill", ""))) and not kept_taken.has(id):
				kept_taken.append(id)
		for level_value in old_claimed:
			var level := int(level_value)
			if [2, 4, 5, 6, 7, 8, 10].has(level) and level <= int(record.get("level", 1)) and not kept_claimed.has(level):
				kept_claimed.append(level)
	if not legacy_upgrade_style:
		var retired_count := 0
		for retired in ["wind_gust_distance", "volt_replace_flex"]:
			if old_taken.has(retired):
				retired_count += 1
		kept_claimed.sort()
		for index in range(mini(retired_count, kept_claimed.size())):
			kept_claimed.pop_back()
	var values := {}
	for upgrade_id in kept_taken:
		var info := upgrade_info(String(upgrade_id))
		values[String(info["key"])] = int(info["value"])
	record["upgrades"] = values
	record["upgrades_taken"] = kept_taken
	record["claimed_even_levels"] = kept_claimed
	record["level_choices"] = {} if legacy_upgrade_style else (record.get("level_choices", {}) as Dictionary).duplicate(true)
