# 技术说明

更新：2026-10-16。Godot 4.7 / GDScript。主场景为 `scenes/main.tscn`，无在线玩法依赖。

## 本轮数据边界

`Balance.SKILL_SLOTS` 统一限制敌我装备数量为 3；`CollectionScreen` 把玩家选择的 `starting_skill_id` 传给 `RunState.new_run()`，仅把这一招加入开局 `known_skills` 与 `equipped_skills`。物种其余基础招式进入 `available_new_skills()`，可在偶数级选择学习。旧本局记录读取时保留已学招式库并将装备裁到三格。`RunState.settle_battle()` 不再给出战者自动回血；携带留守成员按 `BENCH_RECOVERY_RATIO` 恢复，0 HP 特判为 1 HP，仓库恢复流程仍独立。

PP 是局内持久资源：宝可梦记录的 `skill_pp_uses` 保存每个已学技能已消耗次数，`RunState.build_deploy_units()` 在开战前注入 `CombatUnit.battle_skill_uses`，`sync_from_battle()` 在施法、读档和结算后回写。`BattleState.setup()` 不再清空我方 PP；敌方每场新生成并自然满 PP。存档 v19 对旧快照按五倍比例迁移消耗次数；旧记录无 PP 数据时默认满 PP。营地基础食物调用 `restore_record_pp()` 回满全队，商人 `pp_tonic` 通过 `CombatUnit.restore_pp(5)` 为每项已装备技能恢复至多 5 PP。

`SkillResolver` 让冲浪、溜冰保留施放前的移动消耗状态，截止回合为当前回合加一；`PathFinder._connected_terrain_paths()` 允许路线经过敌方占据格，`stop_cells()` 仍禁止停在任何单位所在格。普通移动寻路及阻挡不变。推风射程、海啸区域和顺风长度分别由 `SkillDB` 与 `SkillResolver` 的共享规则定义。

推风现在使用 `direction` 选点。`SkillResolver.front_area_cells()` 统一产生横宽三格的方向区域：推风纵深 2，顺风纵深 3（强化可再延长）；瞄准、预览与实际结算复用该函数。推风只收集施法时位于区域内的敌方单位，按投影距离从远到近交给 `PushResolver`，保证同列多目标不会因遍历顺序不同而产生预览分叉。敌人 AI 继续在克隆战场执行技能并比较结果。

## 关卡数据流

`RunState` 保存本局种子、0–17 的战斗索引、三层已选主题及当前候选。`BattleDB` 用战斗索引取原六场部署模板，用主题确定地图区域、敌人物种与增援池；候选、编成和首领抽选均由种子决定。`MapGenerator` 使用同一主题配置生成棋盘，预览页和实际战斗读取同一配置。主题与消耗品地图卡分别影响生成；安全通路检查仍执行。

普通敌人等级按楼层为 1/3/5，首领加一级。`BattleDB.configure_enemy()` 为初始敌人与增援配置生命、按 Lv1/2/4 开放的 1/2/3 招，以及 Lv6/8/10 各一次的已装备招式强化；基础技能不足时依同属性可学表补足，当前水系第三招为可强化的占位试招。战前预览读取配置后单位的实际技能与强化，避免展示和实战分叉。`CombatUnit.dup()` 复制敌方等级、首领和鼓舞状态，使 AI 的战场克隆保持一致。

首领 UID 与鼓舞是否触发由 `BattleState` 保存。首领一次存活的伤害使其达到半血时，对当前友军施加鼓舞；触发后新增增援同样得到效果。捕获时移除该单位的敌方等级、技能强化和首领属性，不把首领化带入本局怪物记录。

## 存档边界

本局存档版本为 4；旧六场进行中存档不可继续，菜单提示重新开局。永久收藏路径仍为 `user://collection_v1.json`，数据版本为 3；旧 v1/v2 收藏继续读取，v2 亲密度保留，首领之血缺失时按 0 处理。首领之血仅在捕获首领且巢穴存活的清场胜利中入账，毁巢、逃离和失败均不发放；本局种子与场次用于去重。调试控制台污染的本局不写永久收藏。

## 验证入口

藤蔓束缚在 `CombatUnit.vine_sources` 中按来源格记录剩余行动阶段；`vine_ticks` 是这些来源的最大剩余值，供移动判定和界面读取。`BattleState.set_terrain()` 在藤蔓烧尽、到期或被其他地貌覆盖时，遍历单位清除该格对应来源，即使单位已因推击或换位离开原格也能解除；撤回与战场克隆复制来源记录。藤蔓本身不禁止技能，`BattleScreen` 将其他施法限制的具体原因显示在单位信息和技能按钮上。

敌方阶段的主要耗时位于 `EnemyAI.plan()`：它会枚举可达位置与技能目标、复制战场模拟结果。`_route_opening_score()` 现先检查地貌变化是否真的改变敌方通行性；造雨等仍可通行的地貌改写不再重复执行全队寻路。固定种子耗时可用 `tests/profile_enemy_phase.gd` 测量；该脚本区分整轮规划与动作执行，不含 UI 每动作 0.42 秒的播放间隔。复杂场次仍可能有约 1–2 秒规划停顿，需后续继续优化。

全量解析与回归：`godot --headless --path . --script res://tests/run_all.gd`。主题、首领、等级及资源专项用例为 `tests/cases/t31_floor_boss.gd`；窗口截图脚本为 `tests/capture_shots.gd`。固定种子被动承压脚本为 `tests/sample_floor_pressure.gd`，不代替主动试玩与十八战连续流程验收。
