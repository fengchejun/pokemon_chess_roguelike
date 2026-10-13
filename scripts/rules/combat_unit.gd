class_name CombatUnit
extends RefCounted

var uid: int = 0
var species_id: String = ""
var display_name: String = ""
var glyph: String = "?"
var element: String = ""
var side: String = "player"  # player / enemy
var is_trainer: bool = false
var cell: Vector2i = Vector2i.ZERO
var hp: int = 1
var max_hp: int = 1
var move_points: int = 3
var skills: Array = []
var reg_index: int = 0

# 每回合行动资源
var moved: bool = false
var skill_used: bool = false
var capture_used: bool = false

# 状态
var root_pending: bool = false      # 定身：下一次移动机会将被取消
var move_cancelled: bool = false    # 本回合移动被取消（定身生效中）
var slow_ticks: int = 0             # 减速：> 0 时移动上限 −1
var burn_ticks: int = 0             # 灼烧：回合结束 1 伤害
var burn_source_uid: int = -1
var burn_source_side: String = ""
var shock_ticks: int = 0
var paralyzed_ticks: int = 0
var frozen: bool = false
var vine_ticks: int = 0
var haste_ticks: int = 0
var extra_casts: int = 0
var battle_skill_uses: Dictionary = {}
var battle_buffs: Dictionary = {}
var last_move_direction: Vector2i = Vector2i.ZERO

# 其他
var fresh_spawn: bool = false       # 本回合新生成：只移动不施法


func is_alive() -> bool:
	return hp > 0


func hp_ratio() -> float:
	return float(hp) / float(maxi(1, max_hp))


func effective_move() -> int:
	var value := move_points
	if slow_ticks > 0 and not has_buff("status_immune"):
		value -= 1
	if haste_ticks > 0:
		value += 2
	if has_buff("move_plus"):
		value += 1
	return maxi(0, value)


func has_buff(id: String) -> bool:
	return bool(battle_buffs.get(id, false))


func can_act_skill() -> bool:
	return is_alive() and not frozen and paralyzed_ticks <= 0 and (not skill_used or extra_casts > 0)


func can_use_in_battle(skill_id: String) -> bool:
	var limit := SkillDB.battle_limit_of(skill_id)
	return limit <= 0 or int(battle_skill_uses.get(skill_id, 0)) < limit


func can_move_now() -> bool:
	return is_alive() and not frozen and paralyzed_ticks <= 0 and vine_ticks <= 0 and not moved and not move_cancelled and effective_move() > 0


func dup() -> CombatUnit:
	var copy := CombatUnit.new()
	copy.uid = uid
	copy.species_id = species_id
	copy.display_name = display_name
	copy.glyph = glyph
	copy.element = element
	copy.side = side
	copy.is_trainer = is_trainer
	copy.cell = cell
	copy.hp = hp
	copy.max_hp = max_hp
	copy.move_points = move_points
	copy.skills = skills.duplicate()
	copy.reg_index = reg_index
	copy.moved = moved
	copy.skill_used = skill_used
	copy.capture_used = capture_used
	copy.root_pending = root_pending
	copy.move_cancelled = move_cancelled
	copy.slow_ticks = slow_ticks
	copy.burn_ticks = burn_ticks
	copy.burn_source_uid = burn_source_uid
	copy.burn_source_side = burn_source_side
	copy.shock_ticks = shock_ticks
	copy.paralyzed_ticks = paralyzed_ticks
	copy.frozen = frozen
	copy.vine_ticks = vine_ticks
	copy.haste_ticks = haste_ticks
	copy.extra_casts = extra_casts
	copy.battle_skill_uses = battle_skill_uses.duplicate()
	copy.battle_buffs = battle_buffs.duplicate()
	copy.last_move_direction = last_move_direction
	copy.fresh_spawn = fresh_spawn
	return copy


static func make(species_id: String, side: String, uid_value: int) -> CombatUnit:
	var species := SpeciesDB.get_species(species_id)
	var unit := CombatUnit.new()
	unit.uid = uid_value
	unit.species_id = species_id
	unit.display_name = species.get("name", species_id)
	unit.glyph = species.get("glyph", "?")
	unit.element = species.get("element", "")
	unit.side = side
	unit.is_trainer = bool(species.get("is_trainer", false))
	unit.hp = int(species.get("hp", 4))
	unit.max_hp = unit.hp
	unit.move_points = int(species.get("move", 3))
	unit.skills = species.get("skills", []).duplicate()
	return unit
