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

const COLLISION_DAMAGE := 1
const PUSH_DAMAGE := 2
const PUSH_DISTANCE := 1
const OBSTACLE_DURABILITY := 2
const TREE_DURABILITY := 1
const NEST_DURABILITY := 3

const BURN_DAMAGE := 1
const BURN_TICKS := 2

const EXP_PER_KILL := 2
const EXP_PER_CAPTURE := 2

const CARRIED_LIMIT := 6
const DEPLOY_LIMIT := 3
const STORAGE_LIMIT := 30
const MOD_POINTS := 2

# 捕获范围统一使用训练家周围八格，由 CaptureSystem.in_range 判定。
const CAPTURE_CHANCE_BASE := 0.30
const CAPTURE_CHANCE_SLOPE := 0.55
const CAPTURE_CHANCE_MIN := 0.05
const CAPTURE_CHANCE_MAX := 0.95

const BATTLES_PER_RUN := 6

# 每场战斗结束后的全体恢复比例（生命上限的 30%）
const BATTLE_RECOVERY_RATIO := 0.30

# 补给点：每完成 SUPPLY_INTERVAL 场战斗进入，训练家恢复 50% 生命上限
const SUPPLY_INTERVAL := 2
const SUPPLY_TRAINER_RECOVERY_RATIO := 0.5

# 训练家使用固定实例号，避免与“未选择”哨兵值 0 冲突。
const TRAINER_UID := 900000

# 部署格：第 0 格为训练家，其余为宝可梦。
const DEPLOY_CELLS := [Vector2i(0, 3), Vector2i(0, 2), Vector2i(0, 4), Vector2i(1, 3)]

# 局内强化（只卖新解法）

const FRUITS_PER_BATTLE := 2
const FRUIT_HEAL := 2
