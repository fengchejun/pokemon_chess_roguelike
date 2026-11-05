class_name SkillDB
extends RefCounted

## 五属性技能与旧版兼容技能；冰技能按水、风技能按电结算。kind 决定瞄准方式：
##  ray       行列射线（被第一个单位或障碍截断）
##  charge    闪焰冲锋：正交1至2格选方向，逐格前进并在撞击时停下
##  unit      单体选中
##  cell      指定落点
##  teleport  自身瞬移
##  direction 造岩：选择方向

const DEFS := {
	"fire_burst": {"name": "火球术", "element": "fire", "kind": "ray", "min_range": 2, "max_range": 4, "damage": 18, "ranged": true, "channel": true, "desc": "锁定射程 2–4 的格子，下次本方阶段开始落下；九宫格中心受18点、外围受9点基础伤害。吟唱后下一阶段不能行动，可被死亡、冻结或麻痹打断。"},
	"fire_amplify": {"name": "火焰增幅", "element": "fire", "kind": "self", "damage": 0, "ranged": false, "desc": "熄灭自身曼哈顿 2 格内所有燃烧格，每格积累 5 点增幅；下一次实际造成技能直伤时，每个受击单位额外承受全部增幅。"},
	"flame_jet": {"name": "喷射火焰", "element": "fire", "kind": "direction", "damage": 10, "adjacent_bonus": 3, "ranged": true, "desc": "沿选定方向喷射 3 格；障碍截断；命中单位受到 10 点基础伤害并灼烧，紧邻自身的单位额外受到 3 点伤害。"},
	"rain_call": {"name": "造雨术", "element": "water", "kind": "cell", "range": 4, "damage": 0, "ranged": false, "desc": "指定曼哈顿距离 4 格内中心，周围 3×3 格化为浅水；障碍与深坑不变。"},
	"surf": {"name": "冲浪", "element": "water", "kind": "self", "damage": 0, "ranged": false, "desc": "施放当回合及后两回合，沿相连浅水或深水移动不消耗普通移动机会，可重复移动并越过敌方单位；不能停在单位或障碍格。"},
	"mirror_water_moon": {"name": "镜花水月", "element": "water", "kind": "self", "damage": 0, "ranged": false, "battle_limit": 1, "category": "special", "desc": "水系特殊技能，每场限用一次。施加持续三回合的镜花水月：可移动到任意未被占用的浅水或深水格且不消耗普通移动机会；水系技能基础直伤 +5。施放时使全场敌人浸湿一回合；首次受到实际伤害时提前结束状态并免疫该次伤害。"},
	"tsunami": {"name": "海啸", "element": "water", "kind": "direction", "damage": 18, "ranged": true, "channel": true, "desc": "选择方向警示前方宽 5、长 5 的固定区域；下次本方阶段开始，对区域内当时站在水格上的敌方单位造成 18 点基础直伤；施法者该阶段不能行动。"},
	"rock_push": {"name": "推击", "element": "rock", "kind": "unit", "range": 1, "damage": 13, "ranged": false, "desc": "对相邻单位造成13点基础伤害并推开一格；直接推击岩障先扣1耐久，存活时推一格，撞单位造成碰撞伤害，填入深水、岩浆、深坑则变为易碎格。"},
	"rock_break": {"name": "碎岩", "element": "rock", "kind": "unit", "range": 2, "damage": 10, "ranged": true, "desc": "曼哈顿 2 格内攻击单位造成 10 点基础伤害，命中障碍直接摧毁；攻击冰冻目标时伤害三倍并解除冰冻。"},
	"rock_slide": {"name": "岩崩", "element": "rock", "kind": "cell", "range": 3, "damage": 30, "ranged": true, "channel": true, "desc": "锁定曼哈顿 3 格内一格；下次本方阶段开始，对该格当时的单位造成 30 点基础伤害，可误伤友军。"},
	"earth_shake": {"name": "撼地", "element": "rock", "kind": "direction", "damage": 18, "ranged": true, "channel": true, "desc": "蓄力锁定前方 3×3 格；下一本方阶段开始，对范围内敌人造成 18 点基础伤害，摧毁岩障和树木；平地变易碎地块、易碎地块变深坑。破障格本次不再改变地形，站在塌陷格上的地面单位立即坠落。"},
	"lightning": {"name": "打雷", "element": "electric", "kind": "self", "damage": 18, "ranged": true, "channel": true, "desc": "锁定全场所有敌方单位当前格子；下次本方阶段开始，对固定落点上的单位造成 18 点基础伤害并感电，可误伤友军。"},
	"electric_arc": {"name": "放电", "element": "electric", "kind": "cell", "range": 2, "damage": 10, "ranged": true, "desc": "可指定两格内的单位造成10点基础伤害，也可沿连通水域传导；从选定水格起每传播两格减2点基础伤害，最低4点。"},
	"volt_replace": {"name": "伏特替换", "element": "electric", "kind": "unit", "range": 3, "damage": 0, "ranged": false, "desc": "与曼哈顿 1～3 格内的单位交换位置，或移动到范围内可站立空格；无视途中障碍。"},
	"wild_vines": {"name": "疯狂藤蔓", "element": "grass", "kind": "direction", "range": 2, "damage": 0, "ranged": false, "desc": "在正前方两格生成藤蔓，强化后延长至三格；障碍格与巢穴格跳过。地面单位进入藤蔓格获得禁锢，停留不会刷新，离开后重入或隔一回合仍停留会再次触发。"},
	"herbal_heal": {"name": "药草治疗", "element": "grass", "kind": "self", "damage": 0, "ranged": false, "channel": true, "desc": "锁定宣告时自身所在格；下次本方阶段开始，为该格曼哈顿 2 格内友军回复 8 HP；可被打断，结算阶段不能行动。"},
	"leech_seed": {"name": "寄生种子", "element": "grass", "kind": "unit", "range": 1, "damage": 0, "ranged": false, "desc": "使相邻敌人寄生；每次整轮结算目标失去 4 HP、存活的施法者恢复至多 4 HP。目标受到其他实际伤害时解除。"},
	"tree_man": {"name": "大树守卫", "element": "grass", "kind": "cell", "range": 3, "damage": 0, "ranged": false, "desc": "立即在曼哈顿 3 格内空格召唤树人，基础 10 HP；落点周围八格每处水域 +3 HP、草丛/藤蔓 +5 HP、树木 +5 HP 和 5 技能威力。每名单位最多拥有一个存活召唤物，出生轮不能行动。"},
	"tree_wrath": {"name": "大树之怒", "element": "grass", "kind": "unit", "range": 1, "damage": 10, "ranged": false, "desc": "对相邻一格的一名敌方单位造成 10 点基础伤害。"},
	"first_aid": {"name": "急救", "element": "grass", "kind": "unit", "range": 2, "damage": 0, "ranged": true, "desc": "为曼哈顿 2 格内一名受伤友军或自己回复 8 HP，不超过生命上限。"},
	"rooted_grass": {"name": "落地生根", "element": "grass", "kind": "self", "damage": 0, "ranged": false, "desc": "将自身周围 3×3、包含脚下格在内的有效地面转为草丛；跳过障碍、树木、水域、冰面、熔岩、深坑和设施。"},
	"leaf_wind": {"name": "叶之风", "element": "grass", "kind": "unit", "range": 2, "damage": 8, "ranged": true, "desc": "对曼哈顿 2 格内一名敌人造成 8 点基础直伤；施法者位于草丛或藤蔓格时改为 12 点。"},
	"antidote": {"name": "解药", "element": "grass", "kind": "unit", "range": 2, "damage": 0, "ranged": true, "desc": "解除曼哈顿 2 格内一名友军或自己的所有可解除异常状态，冰冻除外，并回复 3 HP。"},
	"frozen_ground": {"name": "冰封大地", "element": "water", "kind": "direction", "damage": 0, "ranged": false, "desc": "前方 3×3 地形生成冰面，可覆盖深水和深坑。"},
	"ice_glide": {"name": "溜冰", "element": "water", "kind": "self", "damage": 0, "ranged": false, "desc": "施放当回合及后两回合，沿相连冰面移动不消耗普通移动机会，可重复移动并越过敌方单位；不能停在单位或障碍格。"},
	"freeze_ray": {"name": "急冻光线", "element": "water", "kind": "ray", "min_range": 1, "max_range": 6, "damage": 0, "ranged": true, "desc": "射程 6；树木与岩障截断射线。第一个敌人被冰冻一回合，期间无法行动；受到伤害时立即解冻并正常受伤。"},
	"ice_shard": {"name": "冰锥", "element": "water", "kind": "unit", "range": 3, "damage": 11, "ranged": true, "desc": "对 3 格内一个敌人造成 11 点基础直伤。"},
	"water_magic_burst": {"name": "水魔爆", "element": "water", "kind": "cell", "range": 4, "damage": 8, "ranged": true, "desc": "选择曼哈顿 4 格内的落点，可越过障碍；五格十字内敌人各受 8 点基础直伤，中心敌人额外受 3 点，外侧四格敌人沿远离中心方向被推 1 格。"},
	"ice_breath": {"name": "冰之息", "element": "water", "kind": "direction", "width": 3, "depth": 2, "damage": 8, "ranged": true, "freeze_combo": true, "desc": "选择正交方向，覆盖前方 3 格宽、2 格深的 3×2 区域；区域内所有敌人各受 8 点基础直伤。若目标已有浸湿，则清除浸湿并施加一回合冰冻。"},
	"tailwind": {"name": "磁场加速", "element": "electric", "kind": "self", "damage": 0, "ranged": false, "desc": "自身及横纵各延伸 2 格的 5×5 区域内友军，下一次可用移动机会移动力 +2。"},
	"double_cast": {"name": "电力引擎", "element": "electric", "kind": "unit", "range": 1, "damage": 0, "ranged": false, "desc": "令一名相邻友军本轮额外施法一次；强化后可依次选择两名相邻友军。蓄力宣告后获得的额外施法可在当轮使用，下一轮蓄力锁定仍生效。"},
	"magnet_pull": {"name": "磁吸", "element": "electric", "kind": "self", "damage": 0, "ranged": false, "desc": "自动选择四正交方向 5 格内最近且路径可见的敌人，将其向自身拉近 1 格；目标有感电或麻痹时拉近 2 格。障碍与中间单位会截断路径。"},
	"glare": {"name": "眩光", "element": "electric", "kind": "self", "damage": 0, "ranged": false, "desc": "对自身周围 3×3 内所有敌人施加一层感电；麻痹中的目标不能获得感电。已有感电的目标再获得一层时转为麻痹。"},
	"electromagnetic_laser": {"name": "电磁镭射", "element": "electric", "kind": "electric_laser", "range": 4, "damage": 12, "ranged": true, "desc": "选择四正交方向 4 格内一名敌人造成 12 点基础直伤；障碍会阻挡。目标有感电或麻痹时可越过地形障碍攻击，但仍不能越过中间单位。"},
	"electric_resonance": {"name": "电共鸣", "element": "electric", "kind": "self", "damage": 0, "ranged": false, "desc": "共鸣自身周围 3×3 内每名单位的感电或麻痹，为施法者下一次造成实际伤害的技能分别蓄积 3 点或 5 点伤害；不会消除感电与麻痹，范围内友军和敌人均生效。"},
	"electric_spark": {"name": "电极火花", "element": "electric", "kind": "direction", "range": 3, "damage": 8, "ranged": true, "desc": "选择四正交方向，对前方 3 格内所有敌人造成 8 点基础直伤；命中前已有感电或麻痹的目标额外尝试施加烧伤。障碍会截断。"},
	"fire_seed": {
		"name": "火种",
		"element": "fire",
		"kind": "ray",
		"min_range": 2,
		"max_range": 6,
		"damage": 11,
		"splash_damage": 8,
		"ranged": true,
		"desc": "沿行列 2 至 6 格射出，树木与岩障截断；命中首个单位造成 11 点基础伤害并附加灼烧；未命中单位时，终点相邻 4 格各受 8 点基础伤害。",
	},
	"flame_charge": {
		"name": "闪焰冲锋",
		"element": "fire",
		"kind": "charge",
		"distance": 2,
		"damage": 11,
		"ranged": false,
		"desc": "选择正交 1～2 格内的位置作为方向，冲撞最多 2 格；撞到单位或障碍就停下。单位受 11 点基础伤害并被推 1 格，障碍受 1 点耐久伤害；沿途致死地形仍会使地面单位倒下。",
	},
	"flame_rush": {
		"name": "炎袭",
		"element": "fire",
		"kind": "teleport",
		"damage": 10,
		"ranged": false,
		"desc": "全图选择一格未被占用、可站立的燃烧格并跃迁过去；对落点周围八格内的敌人各造成 10 点基础直伤。",
	},
	"windfire_breath": {
		"name": "风怒炎息",
		"element": "fire",
		"kind": "direction",
		"damage": 12,
		"ranged": false,
		"desc": "选择方向，覆盖正前方两排共 8 格；命中范围内敌人各造成 12 点基础直伤，并沿远离施法者的方向推动 1 格。",
	},
	"furnace_fist": {
		"name": "炎炉拳",
		"element": "fire",
		"kind": "unit",
		"range": 1,
		"damage": 10,
		"ranged": false,
		"desc": "攻击曼哈顿距离 1 格内的一名敌人，造成 10 点基础直伤并回复自身 5 HP；目标命中前已灼烧时回复 10 HP，并清除其灼烧。",
	},
	"skyfire": {
		"name": "天火",
		"element": "fire",
		"kind": "cell",
		"global_range": true,
		"damage": 8,
		"ranged": true,
		"desc": "全图选择中心，生成中心与上下左右共 5 格十字火焰；十字内所有单位受 8 点基础直伤并尝试附加灼烧。火焰保留两轮。",
	},
	"combustion": {
		"name": "爆燃",
		"element": "fire",
		"kind": "unit",
		"range": 2,
		"damage": 8,
		"ranged": true,
		"desc": "攻击曼哈顿距离 2 格内一名敌人，造成 8 点基础直伤；目标命中前已灼烧时改为基础 16 点，并清除其灼烧。",
	},
	"burn_out": {
		"name": "燃尽",
		"element": "fire",
		"kind": "unit",
		"range": 5,
		"damage": 0,
		"ranged": true,
		"desc": "对曼哈顿 5 格内一名敌人造成施法者最大生命一半的基础直伤并尝试附加灼烧；随后损失施法者最大生命一半的当前 HP，可能因此倒下。",
	},
	"water_flow": {
		"name": "水炮",
		"element": "water",
		"kind": "ray",
		"min_range": 1,
		"max_range": 3,
		"damage": 8,
		"ranged": true,
		"desc": "沿行列射程 3，树木与岩障截断；命中单位造成8点基础伤害并击退1格；命中障碍时在其前一格生成水面。",
	},
	"rain_dance": {
		"name": "造雨术",
		"element": "water",
		"kind": "cell",
		"range": 4,
		"damage": 0,
		"ranged": false,
		"desc": "曼哈顿距离 4 格内的 3×3 区域：平地与草丛转为水面；跳过障碍、深水与熔岩；可对单位所在格施放。",
	},
	"discharge": {
		"name": "放电",
		"element": "electric",
		"kind": "unit",
		"range": 3,
		"damage": 13,
		"ranged": true,
		"desc": "射程 3 的单体：13 点基础伤害；命中后目标下一次移动机会被取消（定身）。",
	},
	"volt_step": {
		"name": "电光步",
		"element": "electric",
		"kind": "teleport",
		"range": 2,
		"damage": 0,
		"ranged": false,
		"desc": "瞬移最多 2 格；可越过单位，不可越过障碍与深水、熔岩；落点必须可站立且无单位。",
	},
	"seed_sow": {
		"name": "播种",
		"element": "grass",
		"kind": "cell",
		"range": 3,
		"damage": 0,
		"ranged": false,
		"desc": "射程 3：目标平地生成草丛；可对单位所在格施放（脚下成荫）。",
	},
	"drain": {
		"name": "吸取",
		"element": "grass",
		"kind": "unit",
		"range": 2,
		"damage": 10,
		"ranged": true,
		"desc": "射程 2 单体：10 点基础伤害；自身回复 5 生命（不超过上限）。",
	},
	"push": {
		"name": "推击",
		"element": "rock",
		"kind": "unit",
		"range": 1,
		"damage": 13,
		"ranged": false,
		"desc": "对相邻单位造成13点基础伤害并推开一格；可损伤并推动岩障一格，撞人或填危险格，规则与推击相同。",
	},
	"rock_smash": {
		"name": "碎岩",
		"element": "rock",
		"kind": "unit",
		"range": 2,
		"damage": 10,
		"ranged": true,
		"desc": "射程 2：对单位 10 点基础伤害；对障碍每次命中最多扣 1 点耐久，破坏后地形立即更新。",
	},
	"rock_create": {
		"name": "造岩",
		"element": "rock",
		"kind": "direction",
		"damage": 10,
		"ranged": false,
		"desc": "选择上下左右方向，在正前方横排生成临时障碍（3 格，出界裁剪）；该格有单位时改为造成 10 点基础伤害且不生成；我方的临时障碍在本轮敌方阶段后消失，敌方的在下一轮敌方阶段后消失。",
	},
	"imprint": {
		"name": "拓印",
		"element": "rock",
		"kind": "unit",
		"range": 5,
		"damage": 0,
		"ranged": false,
		"uncopyable": true,
		"desc": "岩系普通技能。复制曼哈顿 5 格内一名单位最近使用的普通技能，按复制技能的规则即时打出；拓印不会保留复制招式。基础拓印不能复制已强化技能，拓印精通解除该限制；任何拓印都不能复制特殊技能或另一拓印。",
	},
	"mountain_chain": {
		"name": "山脉连袭",
		"element": "rock",
		"kind": "unit",
		"range": 1,
		"damage": 4,
		"segments_base": 2,
		"ranged": false,
		"enemy_only": true,
		"continuous": true,
		"desc": "攻击正交相邻的一名敌人；基础 2 段，自身 3×3 内每有一格岩石障碍则增加 1 段，每段造成 4 点连续伤害。",
	},
	"mountain_form": {
		"name": "山岳形态",
		"element": "rock",
		"kind": "self",
		"damage": 0,
		"ranged": false,
		"category": "special",
		"duration": 1,
		"buff": true,
		"desc": "岩系特殊技能。持续 1 回合的增益状态：自身 3×3 内友军与自身受到的伤害先减免三分之一并向上取整，再由施法者承受。解药只能解除异常状态，不会解除山岳形态。",
	},
	"guard_rock": {
		"name": "守岩",
		"element": "rock",
		"kind": "unit",
		"range": 3,
		"damage": 0,
		"shield": 10,
		"shield_duration": 2,
		"break_damage": 4,
		"ranged": false,
		"ally_only": true,
		"allows_self": true,
		"desc": "为自身或曼哈顿 3 格内一名友军施加 10 点护盾，持续 2 回合。护盾先抵挡伤害；被破坏时，目标四邻格中的敌人各受 4 点伤害，不影响障碍。",
	},
	"rock_blast": {
		"name": "岩爆弹",
		"element": "rock",
		"kind": "unit",
		"range": 3,
		"exact_range": true,
		"orthogonal": true,
		"damage": 12,
		"fragment_damage": 3,
		"fragment_range": 2,
		"ranged": true,
		"enemy_only": true,
		"desc": "攻击正交方向 3 格的一名敌人，造成 12 点伤害并向后推开 1 格；障碍和中间单位会阻挡。命中后从命中格向垂直于发射方向的两侧各延伸 2 格，首个命中单位各受 3 点伤害。",
	},
	"water_drop_stone": {
		"name": "水滴石穿",
		"element": "rock",
		"kind": "unit",
		"range": 1,
		"damage": 12,
		"wet_bonus": 3,
		"wet_bonus_element": "water",
		"ranged": false,
		"obstacle_extension": true,
		"desc": "攻击正交方向 1 格的单位；连续岩石障碍格可作为攻击范围延伸，途经的每格岩石失去 1 点耐久。目标受到 12 点岩系伤害；若已浸湿，额外独立结算 3 点水属性伤害。",
	},
}

const ROCK_SKILL_POOL := [
	"rock_push",
	"rock_break",
	"rock_create",
	"rock_slide",
	"earth_shake",
	"mountain_chain",
	"mountain_form",
	"guard_rock",
	"rock_blast",
	"water_drop_stone",
	"imprint",
]

static func get_def(skill_id: String) -> Dictionary:
	return DEFS.get(skill_id, {})


static func placeholder_ids_for(element: String) -> Array:
	# 保留接口供旧工具调用，但测试招式已永久退役。
	return []


static func learnable_ids_for(element: String) -> Array:
	var ids: Array = []
	match element:
		"fire": ids.append_array(["fire_amplify", "flame_rush", "windfire_breath", "furnace_fist", "skyfire", "combustion", "burn_out"])
		"water": ids.append_array(["surf", "water_magic_burst", "ice_breath", "tsunami", "frozen_ground", "ice_glide", "freeze_ray", "ice_shard"])
		"electric": ids.append_array(["tailwind", "double_cast", "magnet_pull", "glare", "electromagnetic_laser", "electric_resonance", "electric_spark"])
		"grass": ids.append_array(["leech_seed", "tree_man", "first_aid", "rooted_grass", "leaf_wind", "antidote"])
		"rock": ids.append_array(["rock_slide", "earth_shake", "mountain_chain", "guard_rock", "rock_blast", "water_drop_stone", "imprint"])
	return ids


static func is_placeholder(skill_id: String) -> bool:
	var parts := skill_id.split("_")
	return parts.size() == 3 and parts[0] == "trial" and ["fire", "water", "grass", "electric", "rock", "ice", "wind"].has(parts[1]) and ["1", "2"].has(parts[2])


static func is_special(skill_id: String) -> bool:
	return String(get_def(skill_id).get("category", "normal")) == "special"


static func is_copyable(skill_id: String) -> bool:
	var def := get_def(skill_id)
	return not def.is_empty() and not is_special(skill_id) and not bool(def.get("uncopyable", false))


static func has_tag(skill_id: String, tag: String) -> bool:
	return bool(get_def(skill_id).get(tag, false))


static func special_ids_for(element: String) -> Array:
	var result: Array = []
	for skill_id in DEFS:
		if String(DEFS[skill_id].get("element", "")) == element and is_special(String(skill_id)):
			result.append(String(skill_id))
	result.sort()
	return result


static func name_of(skill_id: String) -> String:
	return get_def(skill_id).get("name", skill_id)


static func element_of(skill_id: String) -> String:
	return get_def(skill_id).get("element", "")


static func is_ranged(skill_id: String) -> bool:
	return bool(get_def(skill_id).get("ranged", false))


static func kind_of(skill_id: String) -> String:
	return get_def(skill_id).get("kind", "")


static func damage_of(skill_id: String) -> int:
	return int(get_def(skill_id).get("damage", 0))


static func battle_limit_of(skill_id: String) -> int:
	return int(get_def(skill_id).get("battle_limit", 0))
