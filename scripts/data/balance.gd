class_name Balance
extends RefCounted

## v2.0 定稿数值集中于此。调整平衡时优先动威胁预算（battle_db）与克制修正，
## 最后再动基础伤害。

const GRID_W := 8
const GRID_H := 8

const MAX_ROUNDS := 6
const MOVE_DEFAULT := 3
const MOVE_ROCK := 2
const WATER_EXTRA_COST := 0 # 浅水减速在回合结算时改由浸湿状态处理

const COLLISION_DAMAGE := 1
const PUSH_DAMAGE := 2
const PUSH_DISTANCE := 1
const OBSTACLE_DURABILITY := 2
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

# 环境卡：在地图预览界面从卡表中自选 CARDS_PER_BATTLE 张（仅该界面出现）
const CARDS_PER_BATTLE := 2

# 训练家使用固定实例号，避免与“未选择”哨兵值 0 冲突。
const TRAINER_UID := 900000

# 部署格：第 0 格为训练家，其余为宝可梦。
const DEPLOY_CELLS := [Vector2i(0, 3), Vector2i(0, 2), Vector2i(0, 4), Vector2i(1, 3)]

# 奖励携带者存活至结算：额外经验（环境卡改为战前自选后，奖励格改用经验结算）
const CARRIER_BONUS_EXP := 2

# 局内强化（只卖新解法）
const UPGRADE_THRESHOLDS := [10, 20, 30, 40]

const FRUITS_PER_BATTLE := 2
const FRUIT_HEAL := 2
