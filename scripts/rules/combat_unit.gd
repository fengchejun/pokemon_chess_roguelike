class_name CombatUnit
extends RefCounted

signal feedback_changed(kind: String, text: String, value: int, at: Vector2i)

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
var enemy_level: int = 1
var combat_level: int = 1
var is_boss: bool = false
var inspired: bool = false:
	set(value):
		var was_active := inspired
		var active := value
		var announce := active != was_active
		inspired = value
		if announce:
			feedback_changed.emit("buff" if active else "clear", "首领鼓舞" + ("解除" if not active else ""), int(value), cell)

# 每回合行动资源
var moved: bool = false
var skill_used: bool = false
var capture_used: bool = false

# 状态
var root_pending: bool = false:
	set(value):
		var was_active := root_pending or move_cancelled
		var active := value or move_cancelled
		var announce := active != was_active
		root_pending = value
		if announce:
			feedback_changed.emit("status" if active else "clear", "定身" + ("解除" if not active else ""), int(value), cell)
var move_cancelled: bool = false:
	set(value):
		var was_active := move_cancelled or root_pending
		move_cancelled = value
		if was_active and not move_cancelled and not root_pending:
			feedback_changed.emit("clear", "定身解除", 0, cell)
var slow_ticks: int = 0:
	set(value):
		var was_active := slow_ticks > 0
		var active := value > 0
		var announce := active != was_active
		slow_ticks = value
		if announce:
			feedback_changed.emit("status" if active else "clear", "浸湿" + ("解除" if not active else ""), int(value), cell)
var burn_ticks: int = 0:
	set(value):
		var was_active := burn_ticks > 0
		var active := value > 0
		var announce := active != was_active
		burn_ticks = value
		if announce:
			feedback_changed.emit("status" if active else "clear", "灼烧" + ("解除" if not active else ""), int(value), cell)
var burn_source_uid: int = -1
var burn_source_side: String = ""
var shock_ticks: int = 0:
	set(value):
		var was_active := shock_ticks > 0
		var active := value > 0
		var announce := active != was_active
		shock_ticks = value
		if announce:
			feedback_changed.emit("status" if active else "clear", "感电" + ("解除" if not active else ""), int(value), cell)
var paralyzed_ticks: int = 0:
	set(value):
		var was_active := paralyzed_ticks > 0
		var active := value > 0
		var announce := active != was_active
		paralyzed_ticks = value
		if announce:
			feedback_changed.emit("status" if active else "clear", "麻痹" + ("解除" if not active else ""), int(value), cell)
var frozen: bool = false:
	set(value):
		var was_active := frozen
		var active := value
		var announce := active != was_active
		frozen = value
		if announce:
			feedback_changed.emit("status" if active else "clear", "冰冻" + ("解除" if not active else ""), int(value), cell)
var vine_ticks: int = 0:
	set(value):
		var was_active := vine_ticks > 0
		var active := value > 0
		var announce := active != was_active
		vine_ticks = value
		if announce:
			feedback_changed.emit("status" if active else "clear", "藤蔓束缚" + ("解除" if not active else ""), int(value), cell)
var vine_sources: Dictionary = {} # 束缚来源格 -> 剩余行动阶段；地块消失时按来源清除。
var haste_ticks: int = 0:
	set(value):
		var was_active := haste_ticks > 0
		var active := value > 0
		var announce := active != was_active
		haste_ticks = value
		if announce:
			feedback_changed.emit("buff" if active else "clear", "加速" + ("解除" if not active else ""), int(value), cell)
var extra_casts: int = 0:
	set(value):
		var was_active := extra_casts > 0
		var active := value > 0
		var announce := active != was_active or (value > extra_casts and value > 0)
		extra_casts = value
		if announce:
			feedback_changed.emit("buff" if active else "clear", "额外施法" + ("解除" if not active else ""), int(value), cell)
var battle_skill_uses: Dictionary = {}
var channel_lock_round: int = 0
var battle_buffs: Dictionary = {}
var upgrades: Dictionary = {} # 仅此怪物本局取得的强化；敌人默认为空。
var last_move_direction: Vector2i = Vector2i.ZERO
var parasite_ticks: int = 0
var parasite_source_uid: int = -1:
	set(value):
		var was_active := parasite_source_uid >= 0
		var active := value >= 0
		var announce := active != was_active
		parasite_source_uid = value
		if announce:
			feedback_changed.emit("status" if active else "clear", "寄生" + ("解除" if not active else ""), int(value), cell)
var parasite_source_side: String = ""
var ice_glide_until_round: int = 0:
	set(value):
		var was_active := ice_glide_until_round > 0
		var active := value > 0
		var announce := active != was_active
		ice_glide_until_round = value
		if announce:
			feedback_changed.emit("buff" if active else "clear", "溜冰" + ("解除" if not active else ""), int(value), cell)
var surf_until_round: int = 0:
	set(value):
		var was_active := surf_until_round > 0
		var active := value > 0
		var announce := active != was_active
		surf_until_round = value
		if announce:
			feedback_changed.emit("buff" if active else "clear", "冲浪" + ("解除" if not active else ""), int(value), cell)
var fire_amp_stacks: int = 0:
	set(value):
		var was_active := fire_amp_stacks > 0
		var active := value > 0
		var announce := active != was_active or (value > fire_amp_stacks and value > 0)
		fire_amp_stacks = value
		if announce:
			feedback_changed.emit("buff" if active else "clear", "火焰增幅" + ("解除" if not active else ""), int(value), cell)

# 其他
var fresh_spawn: bool = false       # 本回合新生成：在巢穴格待机，不能移动或施法
var summon_owner_uid: int = -1
var summon_power_bonus: int = 0


func is_alive() -> bool:
	return hp > 0


func hp_ratio() -> float:
	return float(hp) / float(maxi(1, max_hp))


func effective_move() -> int:
	var value := move_points
	if inspired:
		value += 1
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
	return is_alive() and not fresh_spawn and not frozen and paralyzed_ticks <= 0 and (not skill_used or extra_casts > 0)


func can_use_in_battle(skill_id: String) -> bool:
	var limit := SkillDB.battle_limit_of(skill_id)
	return limit <= 0 or int(battle_skill_uses.get(skill_id, 0)) < limit


func can_move_now(free_terrain: bool = false) -> bool:
	return is_alive() and not fresh_spawn and not frozen and paralyzed_ticks <= 0 and vine_ticks <= 0 and not move_cancelled and (free_terrain or (not moved and effective_move() > 0))


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
	copy.enemy_level = enemy_level
	copy.combat_level = combat_level
	copy.is_boss = is_boss
	copy.inspired = inspired
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
	copy.vine_sources = vine_sources.duplicate()
	copy.haste_ticks = haste_ticks
	copy.extra_casts = extra_casts
	copy.battle_skill_uses = battle_skill_uses.duplicate()
	copy.channel_lock_round = channel_lock_round
	copy.battle_buffs = battle_buffs.duplicate()
	copy.upgrades = upgrades.duplicate()
	copy.last_move_direction = last_move_direction
	copy.parasite_ticks = parasite_ticks
	copy.parasite_source_uid = parasite_source_uid
	copy.parasite_source_side = parasite_source_side
	copy.ice_glide_until_round = ice_glide_until_round
	copy.surf_until_round = surf_until_round
	copy.fire_amp_stacks = fire_amp_stacks
	copy.fresh_spawn = fresh_spawn
	copy.summon_owner_uid = summon_owner_uid
	copy.summon_power_bonus = summon_power_bonus
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
	unit.hp = int(species.get("hp", 40))
	unit.max_hp = unit.hp
	unit.move_points = int(species.get("move", 3))
	unit.skills = (species.get("skills", []) as Array).slice(0, Balance.SKILL_SLOTS)
	return unit
