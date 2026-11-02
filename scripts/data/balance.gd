class_name Balance
extends RefCounted

## 原型数值集中于此；属性克制暂时停用，地图密度由区域权重决定。

const GRID_W := 8
const GRID_H := 8

const MAX_ROUNDS := 8
const NEST_SPAWN_INTERVAL := 2

static func nest_wave_due(battle_round: int) -> bool:
	return battle_round > 0 and battle_round < MAX_ROUNDS and battle_round % NEST_SPAWN_INTERVAL == 0


static func nest_warning_due(battle_round: int) -> bool:
	return nest_wave_due(battle_round + 1)

const MOVE_DEFAULT := 3
const MOVE_ROCK := 2
const WATER_EXTRA_COST := 0 # 浅水在阶段交接时赋予浸湿；冰面滑入浅水在整轮结算时补发

const COLLISION_DAMAGE := 5
const PUSH_DAMAGE := 13
const PUSH_DISTANCE := 1
const OBSTACLE_DURABILITY := 2
const TREE_DURABILITY := 1
const NEST_DURABILITY := 3

const BURN_DAMAGE := 4
const BURN_TICKS := 2
const STATUS_MAX_STACKS := 4
const PARASITE_TICKS := 2

# 战斗数值刻度：Lv1 普通敌人 20–30 HP，常规技能约 10–13 直伤。
# 敌人通常成群行动，单次技能伤害按此比例结算，避免放大数字后集火过猛。
const ENEMY_SKILL_DAMAGE_RATIO := 0.7
const SKILL_DAMAGE_UPGRADE := 5
const DIRECT_GUARD_REDUCTION := 4
const PARASITE_DAMAGE := 4
const PARASITE_HEAL := 4
const DRAIN_HEAL := 5
const HERBAL_HEAL := 8
const HERBAL_HEAL_UPGRADE := 5
const TREE_WATER_HP := 3
const TREE_GRASS_HP := 5
const BOSS_HP_BONUS := 20
const INSPIRATION_HP_BONUS := 5
const BENCH_REVIVE_HP := 5
const CAPTURE_GUARANTEE_HP := 5
const CAPTURE_DEBUFF_GUARANTEE_HP := 10

static func skill_damage_for_side(base: int, side: String) -> int:
	if base <= 0:
		return 0
	return maxi(1, roundi(float(base) * ENEMY_SKILL_DAMAGE_RATIO)) if side == "enemy" else base

const EXP_PER_KILL := 2
const EXP_PER_CAPTURE := 2

static func xp_for_enemy_level(level: int) -> int:
	return maxi(1, level) + 1

static func xp_for_event(entry: Dictionary) -> int:
	return maxi(0, int(entry.get("xp_reward", EXP_PER_KILL)))

const CARRIED_LIMIT := 6
const DEPLOY_LIMIT := 3
const SKILL_SLOTS := 3
const STORAGE_LIMIT := 30
const MOD_POINTS := 2

# 捕获范围统一使用训练家周围八格，由 CaptureSystem.in_range 判定。
const CAPTURE_CHANCE_BASE := 0.30
const CAPTURE_CHANCE_SLOPE := 0.55
const CAPTURE_CHANCE_MIN := 0.05
const CAPTURE_CHANCE_MAX := 0.95

const FLOORS_PER_RUN := 3
const BATTLES_PER_FLOOR := 6
const BATTLES_PER_RUN := FLOORS_PER_RUN * BATTLES_PER_FLOOR

# 每场战斗结束时，未出战的携带怪物恢复生命上限的 50%。
const BENCH_RECOVERY_RATIO := 0.50

# 补给点：每完成 SUPPLY_INTERVAL 场战斗进入，训练家恢复 50% 生命上限
const SUPPLY_INTERVAL := 2
const SUPPLY_TRAINER_RECOVERY_RATIO := 0.5

# 训练家使用固定实例号，避免与“未选择”哨兵值 0 冲突。
const TRAINER_UID := 900000

# 部署格：第 0 格为训练家，其余为宝可梦。
const DEPLOY_AREA := [Vector2i(0, 2), Vector2i(1, 2), Vector2i(0, 3), Vector2i(1, 3), Vector2i(0, 4), Vector2i(1, 4), Vector2i(0, 5), Vector2i(1, 5)]
const DEPLOY_CELLS := [Vector2i(0, 3), Vector2i(0, 2), Vector2i(0, 4), Vector2i(1, 3)]

# 局内强化（只卖新解法）

const FRUITS_PER_BATTLE := 2
const FRUIT_HEAL := 10
