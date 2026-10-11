extends RefCounted

## Prototype values. Change here when testing the combat pacing.
const PLAYER_MOVE_POINTS: int = 3
const TRAINER_SPEED: int = 2
const SKILL_POINTS_PER_TURN: int = 1
const MAX_PLAYER_ROUNDS: int = 6
const CAPTURE_ATTEMPTS_PER_TURN: int = 1
const CAPTURE_MAX_HP_RATIO: float = 0.5
const CAPTURE_GUARANTEED_HP: int = 1
const CAPTURE_DEBUFF_GUARANTEED_HP: int = 2
const CAPTURE_BASE_CHANCE: float = 0.65
const CAPTURE_LOW_HP_BONUS: float = 0.15
const EXPERIENCE_PER_KILL: int = 2
const EXPERIENCE_PER_CAPTURE: int = 1
const CARRIED_MONSTER_LIMIT: int = 6
const DEPLOYED_MONSTER_LIMIT: int = 3
const PUSH_DISTANCE: int = 1
const COLLISION_DAMAGE: int = 1
const BURN_DAMAGE: int = 1
const ELECTRIC_DAMAGE: int = 1
const PUSH_OBJECT_DAMAGE: int = 1
const ROCK_SKILL_OBJECT_DAMAGE: int = 2
const NEST_HP: int = 3
const DEEP_WATER_CHANCE: float = 0.08
const BURNING_TURNS: int = 2
const WET_MOVE_PENALTY: int = 1

const SKILLS := {
	"fire_burst": {"name": "火球术", "element": "fire", "range": 8, "min_range": 2, "axis": true, "cost": 1, "damage": 1, "uses_per_battle": 1, "ignores_obstacles": true, "description": "沿行列选点并越过障碍；中心单位 2 伤、四邻单位各 1 伤；击碎易碎地块，只点燃命中的可燃物；每场限用一次"},
	"flame_jet": {"name": "喷射火焰", "element": "fire", "range": 3, "min_range": 1, "axis": true, "cost": 1, "damage": 1, "description": "点选正交方向，向前喷射最多 3 格；沿途单位各受 1 伤并灼烧，首个障碍受 1 耐久伤害且挡住后续格"},
	"flame_charge": {"name": "闪焰冲锋", "element": "fire", "range": 2, "min_range": 2, "axis": true, "cost": 1, "damage": 0, "description": "直线越过一格落在两格外；途中非火系单位灼烧，落在深水或深坑会死亡"},
	"water_flow": {"name": "水流", "element": "water", "range": 8, "axis": true, "cost": 1, "damage": 1, "description": "沿行列射击；命中单位造成 1 伤、击退并浸湿；命中障碍在其前方造浅水"},
	"rain_call": {"name": "造雨术", "element": "water", "range": 5, "min_range": 0, "cost": 1, "damage": 0, "description": "曼哈顿距离 5 格内选点，周围 3×3 可转化地块变浅水并熄火；Shift+点击友军格可作为中心"},
	"electric_arc": {"name": "放电", "element": "electric", "range": 2, "cost": 1, "damage": 1, "description": "命中水域时沿连通水域传导，各单位最多受 1 伤"},
	"lightning": {"name": "闪电", "element": "electric", "range": 99, "cost": 1, "damage": 2, "description": "指定场上任意单位造成 2 点直伤并感电；再次感电会麻痹下一次行动"},
	"wild_vines": {"name": "疯狂藤蔓", "element": "grass", "range": 1, "cost": 1, "damage": 0, "description": "指定方向，在前方两格生成可燃藤蔓；入格单位下一次行动不能主动移动"},
	"herbal_heal": {"name": "药草治疗", "element": "grass", "range": 0, "min_range": 0, "cost": 1, "damage": 0, "description": "以自身为中心 3×3 内所有友军恢复 1 HP"},
	"frozen_ground": {"name": "冰封大地", "element": "ice", "range": 1, "cost": 1, "damage": 0, "description": "指定方向，紧邻起前方 3×3 生成冰面；可覆盖深水与深坑"},
	"freeze_ray": {"name": "急冻光线", "element": "ice", "range": 8, "axis": true, "cost": 1, "damage": 0, "description": "直线首个敌人永久冻结，直到受击或净化；首次受击免伤解冻，但下一次行动仍跳过"},
	"tailwind": {"name": "加速", "element": "wind", "range": 1, "cost": 1, "damage": 0, "description": "指定方向，前方宽 3 格、深 2 格的友军本轮移动力 +2"},
	"double_cast": {"name": "加速2", "element": "wind", "range": 1, "cost": 1, "damage": 0, "description": "正前方一格的友方怪物本轮可施法两次"},
	"rock_break": {"name": "碎岩", "element": "rock", "range": 2, "cost": 1, "damage": 1, "description": "造成 1 伤；对岩石造成 2 点耐久伤害"},
	"rock_push": {"name": "推击", "element": "rock", "range": 1, "cost": 1, "damage": 2, "description": "造成 2 伤并推开相邻敌人；碰撞追加伤害"},
	"rock_create": {"name": "造岩", "element": "rock", "range": 1, "cost": 1, "damage": 2, "description": "点选相邻方向，在前方形成垂直三格短墙；有单位处造成 2 伤，易碎地块会塌陷；岩石在下一次敌方行动结束后消失"}
}

const TRAINER_HP: int = 6
const MONSTER_HP: int = 5
const WILD_HP: int = 4
