class_name BattleDB
extends RefCounted

## 六种关卡布局在三层中重复使用；主题决定地貌权重和敌方物种。

const THEME_IDS := ["fire", "water", "grass", "rock"]
const THEMES := {
	"fire": {"name": "火谷", "primary": ["fire_wild1", "fire_wild2"], "support": ["rock_wild1", "electric_wild1"]},
	"water": {"name": "深潭", "primary": ["water_wild1", "water_wild2"], "support": ["electric_wild1", "ice_wild1"]},
	"grass": {"name": "密林", "primary": ["grass_wild1", "grass_wild2"], "support": ["water_wild1", "wind_wild1"]},
	"rock": {"name": "岩窟", "primary": ["rock_wild1", "rock_wild2"], "support": ["fire_wild1", "ice_wild1"]},
}

const CONFIGS := [
	{
		"region": "草原",
		"enemies": [["fire_wild1", Vector2i(6, 2)], ["grass_wild1", Vector2i(6, 5)]],
		"nest_cell": Vector2i(7, 0),
		"nest_exits": [],
		"reinforce": ["fire_wild1", "grass_wild1"],
		"lethal_budget": 1,
	},
	{
		"region": "溪谷",
		"enemies": [["water_wild1", Vector2i(6, 2)], ["rock_wild1", Vector2i(5, 5)], ["fire_wild1", Vector2i(6, 5)]],
		"nest_cell": Vector2i(7, 0),
		"nest_exits": [],
		"reinforce": ["water_wild1", "rock_wild1"],
		"lethal_budget": 2,
	},
	{
		"region": "密林",
		"enemies": [["electric_wild1", Vector2i(5, 2)], ["grass_wild1", Vector2i(6, 3)], ["water_wild2", Vector2i(6, 6)]],
		"nest_cell": Vector2i(7, 1),
		"nest_exits": [],
		"reinforce": ["electric_wild1", "wind_wild1"],
		"lethal_budget": 2,
	},
	{
		"region": "火谷",
		"enemies": [["fire_wild1", Vector2i(5, 1)], ["fire_wild2", Vector2i(6, 3)], ["rock_wild2", Vector2i(6, 6)], ["electric_wild1", Vector2i(5, 5)]],
		"nest_cell": Vector2i(7, 0),
		"nest_exits": [],
		"reinforce": ["fire_wild1", "rock_wild2"],
		"lethal_budget": 3,
	},
	{
		"region": "岩窟",
		"enemies": [["rock_wild1", Vector2i(7, 2)], ["rock_wild2", Vector2i(6, 4)], ["water_wild1", Vector2i(5, 6)], ["ice_wild1", Vector2i(7, 6)]],
		"nest_cell": Vector2i(7, 0),
		"nest_exits": [],
		"reinforce": ["rock_wild2", "ice_wild1"],
		"lethal_budget": 3,
	},
	{
		"region": "深潭",
		"enemies": [["water_wild1", Vector2i(5, 1)], ["water_wild2", Vector2i(6, 2)], ["electric_wild2", Vector2i(6, 4)], ["rock_wild1", Vector2i(6, 6)], ["wind_wild1", Vector2i(5, 5)]],
		"nest_cell": Vector2i(7, 0),
		"nest_exits": [],
		"reinforce": ["electric_wild2", "water_wild2"],
		"lethal_budget": 4,
	},
]


static func floor_of(battle_index: int) -> int:
	return clampi(battle_index / Balance.BATTLES_PER_FLOOR, 0, Balance.FLOORS_PER_RUN - 1)


static func local_battle_of(battle_index: int) -> int:
	return posmod(battle_index, Balance.BATTLES_PER_FLOOR)


static func theme_offers(run_seed: int, floor_index: int, chosen: Array) -> Array:
	var available: Array = []
	for theme_id in THEME_IDS:
		if not chosen.has(theme_id):
			available.append(theme_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("themes:%d:%d" % [run_seed, floor_index])
	for index in range(available.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var value = available[index]
		available[index] = available[swap_index]
		available[swap_index] = value
	return available.slice(0, mini(2, available.size()))


static func config_for(battle_index: int, run_seed: int = 0, theme_id: String = "") -> Dictionary:
	var local := local_battle_of(battle_index)
	var cfg: Dictionary = CONFIGS[local].duplicate(true)
	if theme_id == "" or not THEMES.has(theme_id):
		return cfg
	var theme: Dictionary = THEMES[theme_id]
	cfg["region"] = theme["name"]
	cfg["theme_id"] = theme_id
	cfg["floor"] = floor_of(battle_index)
	cfg["enemy_level"] = 1 + floor_of(battle_index) * 2
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("enemies:%d:%d:%s" % [run_seed, battle_index, theme_id])
	var template: Array = cfg["enemies"]
	var primary_count := roundi(float(template.size()) * 0.6)
	var primary: Array = theme["primary"]
	var support: Array = theme["support"]
	var enemies: Array = []
	for index in template.size():
		var pool: Array = primary if index < primary_count else support
		enemies.append([pool[rng.randi_range(0, pool.size() - 1)], template[index][1]])
	cfg["enemies"] = enemies
	cfg["reinforce"] = [primary[0], primary[1], support[0]]
	cfg["boss_index"] = rng.randi_range(0, enemies.size() - 1) if local == Balance.BATTLES_PER_FLOOR - 1 else -1
	return cfg


static func enemy_skill_count(level: int) -> int:
	return 3 if level >= 4 else (2 if level >= 2 else 1)


static func enemy_skills_for_level(species_id: String, level: int) -> Array:
	var skills: Array = SpeciesDB.skills_of(species_id).slice(0, enemy_skill_count(level))
	if skills.size() < enemy_skill_count(level):
		for skill_id in SkillDB.learnable_ids_for(SpeciesDB.element_of(species_id)):
			if not skills.has(skill_id):
				skills.append(skill_id)
			if skills.size() >= enemy_skill_count(level):
				break
	return skills


static func enemy_upgrade_ids(run_seed: int, battle_index: int, spawn_index: int, species_id: String, make_boss: bool = false) -> Array:
	var level := 1 + floor_of(battle_index) * 2 + (1 if make_boss else 0)
	return enemy_upgrade_ids_at_level(run_seed, battle_index, spawn_index, species_id, level)


static func enemy_upgrade_ids_at_level(run_seed: int, battle_index: int, spawn_index: int, species_id: String, level: int) -> Array:
	var count := clampi((level - 4) / 2, 0, 3)
	if count <= 0:
		return []
	var candidates: Array = []
	for skill_id in enemy_skills_for_level(species_id, level):
		var upgrade_id := RunState.upgrade_id_for_skill(String(skill_id))
		if upgrade_id != "" and not candidates.has(upgrade_id):
			candidates.append(upgrade_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("enemy-upgrades:%d:%d:%d:%s" % [run_seed, battle_index, spawn_index, species_id])
	var chosen: Array = []
	while chosen.size() < count and not candidates.is_empty():
		chosen.append(candidates.pop_at(rng.randi_range(0, candidates.size() - 1)))
	return chosen


static func enemy_upgrade_values(run_seed: int, battle_index: int, spawn_index: int, species_id: String, make_boss: bool = false) -> Dictionary:
	var values := {}
	for upgrade_id in enemy_upgrade_ids(run_seed, battle_index, spawn_index, species_id, make_boss):
		var info := RunState.upgrade_info(String(upgrade_id))
		if not info.is_empty():
			values[String(info["key"])] = int(info["value"])
	return values


static func configure_enemy(unit: CombatUnit, run_seed: int, battle_index: int, spawn_index: int, make_boss: bool = false) -> void:
	unit.enemy_level = 1 + floor_of(battle_index) * 2 + (1 if make_boss else 0)
	unit.combat_level = unit.enemy_level
	unit.skills = enemy_skills_for_level(unit.species_id, unit.enemy_level)
	unit.max_hp = MonsterProgression.max_hp(unit.species_id, unit.enemy_level)
	unit.hp = unit.max_hp
	unit.upgrades = enemy_upgrade_values(run_seed, battle_index, spawn_index, unit.species_id, make_boss)
	if make_boss:
		unit.is_boss = true
		unit.max_hp += Balance.BOSS_HP_BONUS
		unit.hp += Balance.BOSS_HP_BONUS


static func count() -> int:
	return Balance.BATTLES_PER_RUN
