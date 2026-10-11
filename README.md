# 怪物战棋肉鸽

Godot 4.6.2 / GDScript 的 2D 战棋肉鸽与怪物收集原型。当前实现到**阶段 5，并加入七元素战斗原型**。8×8 战场按区域与本局卡组生成，深浅水、火焰、藤蔓、冰面、易碎地块、巢穴和双方可争夺的奖励点会改变战术选择。

项目方向参考《陷阵之志》《宝可梦》《幻兽帕鲁》《博德之门 3》和《暗黑地牢》：训练家参与战斗，怪物与环境共同形成战术解法。原仓库提出的“由宝可梦参与基地运作”仍是后续设想，当前原型尚未实现。

## 七元素更新（当前规则）

水电怪拆为纯水怪与独立电怪。开局从七种怪物中选三只，本局最初仅携带这三只；未选物种可以在之后的战斗中捕获。湿地偏水、电、冰，森林偏火、草、风，遗迹偏岩、电、冰；具体敌人与巢穴增援依区域权重和本局种子确定。

- 电怪：闪电无视视线，对任意单位造成 2 点直伤并感电；第二次感电改为麻痹，跳过下一次行动。放电选两格内水格，伤及整片连通水域及其四邻格中浸湿的陆地单位，同次每单位最多受伤一次。
- 草怪：疯狂藤蔓在所选方向前方两格独立生成可燃藤蔓，能覆盖浅水和单位脚下；进入后下一次行动不能主动移动，但可以施法。药草治疗恢复自身周围 3×3 内所有友军 1 HP。浅水上的藤蔓也能燃烧，烧尽后露出水域。
- 冰怪：冰封大地从紧邻处向前铺三排、每排三格，能架过深水和深坑；急冻光线冻结直线首个敌人。冻结不会随回合结束消失；首次受非即死伤害时免疫整次命中并解冻，但仍跳过下一次行动；净化也可解除冻结，淹没与坠落照常致死。冰面本场持续，受火球术或喷射火焰命中后融化并恢复下层地形。
- 风怪：加速使前方宽三格、深两格的友军本轮移动力 +2；加速2使正前方一格的友方怪物本轮可多施法一次。敌方风怪先于其他敌人行动；加速在本轮结算后结束。

新控制状态与灼烧、浸湿均计入捕获减益：目标 2 HP 且带任意减益时必定捕获。净化 Buff 免疫并解除这些状态。草、冰、风环境卡及完整元素克制表尚未加入。

## 运行

1. 使用 Godot 4.6.2 打开本目录的 `project.godot`。
2. 按 F5 启动项目，点击“开始战斗”并选三只初始怪物。蓝色为己方，红色为敌人。
3. 我方阶段可自由切换所有存活的己方单位。点击单位即可选中并显示可移动格；点击绿色终点，自动沿合法路径一次移动。移动途中可以穿过己方单位，但不能停在其格子上；敌人仍会阻挡。训练家与火、水、电、风怪最多走 3 格，岩、草、冰怪最多走 2 格；浸湿使下一回合各减 1 格。每名己方单位每回合最多移动一次。悬停可看合法路线；成功施放技能会提交此前移动，并用完施法者尚未使用的移动机会。其他队员之后的新移动仍可按逆序撤回。捕获尝试提交此前移动，但训练家仍可在捕获后移动并撤回。选择技能、取消瞄准和无效行动不提交移动；结束回合关闭撤回。
4. 底栏列出当前怪物的全部技能、消耗及不可用原因。点击技能按钮瞄准，金色格显示可选目标，悬停可看落点和影响范围；再次点击该按钮、按 Esc 或右键可取消瞄准。合法施放后自动回到直接移动；无效施放不会消耗技能点或关闭撤回。火球术沿行列选择至少两格外的中心，可越过障碍，每只火怪每场限用一次；中心单位受 2 伤、四邻单位各受 1 伤，命中易碎格会令其塌陷，命中的草丛与树木可燃烧，普通地面不会燃烧，水格产生蒸汽。喷射火焰向选定正交方向延伸最多三格，沿线单位各受 1 伤并灼烧；首个树木、岩石或巢穴承受 1 耐久伤害并挡住后续格。闪焰冲锋可越过中间一格，对经过的非火系单位施加灼烧，落点若是深水或深坑会死亡。水流仍会被首个障碍或单位截断；命中单位造成 1 伤、击退并浸湿，不在原格造水；命中障碍则在障碍前一格造浅水。造雨术在五格曼哈顿距离内选点，将周围 3×3 可转化地块变成浅水。岩怪保留推击与碎岩；造岩时点选相邻方向格，在该方向的垂直线上生成最多三格短墙，命中单位造成 2 伤。短墙在之后的敌方行动结束时消失。技能瞄准时直接点击合法的友军目标格会施法；需要切换单位时先取消瞄准。怪物每回合有 1 点技能点。
5. 选中训练家后，底栏显示“捕获”。训练家周围八格内、生命值不高于一半的野生怪物可被捕获，每回合有一次独立于移动的机会；斜角可捕获，角落障碍不阻挡。目标仅剩 1 HP 时必定成功；有任意已实现减益时，2 HP 也必定成功。其他情况悬停可查看成功率。成功后怪物保留当前生命、状态和位置，立刻转为可操作的己方单位，本轮获得一次移动和一次技能；若战斗结束前阵亡，则不会加入本局队伍。存活者战后收容，满员时进入待收容；失败会消耗本回合捕获机会。
6. 浅蓝“浅”是浅水：训练家和非水系怪物在回合末仍站在其中，会在下一回合浸湿、移动力减 1；水流直接命中的浸湿也会保证下一轮减速，即使离开水格。水系免疫。深蓝“深”不可由训练家或非水系怪物主动进入，水系可以进入；地面单位不能主动进入已塌陷的“坑”。强制位移进入致死格仍立即结算死亡。绿色“草”可站立；点燃后的可燃物每次结算向相邻可燃物蔓延一格，燃烧两次结算后烧尽。非火系单位受到火球术中心命中、喷射火焰命中或站在火焰格结算时会获得灼烧，从下一次完整回合结算起每轮失去 1 HP，入水解除。“裂”是可站立的易碎地块：火球术、造岩或强化后的碎岩命中会使它塌为永久的“坑”，其上地面单位立即坠落死亡；造雨可把裂地转为浅水。蒸汽“雾”使站在其中的怪物不能施法，移动与训练家捕获照常。放电沿深浅水连通传导。飞行 Buff 的地面豁免见下文。
7. 每场有一个紫色巢穴和一个黄色奖励点。第 1、3 回合开始，顶部会预告下回合巢穴产怪，巢穴格也会标出警示；第 2、4 回合的增援加入队列。出口被占会推迟生成，下一回合空出便立即产怪；每回合最多生成一只，积压的增援继续排队。新怪出生当轮留在出口待机，不能主动移动或施法，下一完整回合才正常行动。它仍可被攻击、捕获或强制位移。**摧毁巢穴立即获胜**，全歼敌人也可获胜。敌方守住奖励点到我方阶段结束会自动获得随机二选一 Buff；我方守到敌方阶段结束会弹出二选一。Buff 只给守点单位且只在本场有效。奖励点受伤会毁坏，领取后消失；第 6 回合敌方阶段结束后不再给我方发奖。第 6 回合结算后仍未获胜，剩余野生怪物逃离；整备页处理捕获、经验、常规环境卡和下一场出战。
8. 在直接移动状态下点击敌人，可查看红色边框表示的当前合法移动范围；这显示它能走到哪里，并非下一回合的行动预告。技能或捕获瞄准时点击敌人仍会执行当前所选行动。

敌方单位站在巢穴出口时，巢穴每次受击有 1 点防御：1 点伤害无法降低耐久，2 点伤害只能降低 1 点。出口没有敌方单位时恢复正常伤害。推击抵达棋盘边缘会停下，不再产生额外碰撞伤害；撞单位和障碍的碰撞规则不变。技能瞄准时若友军所在格是合法目标，直接点击会施放技能；想切换选中单位可先按 Esc、右键或再次点击技能按钮退出瞄准。

悬停浅水、深水、草丛、易碎地块、深坑、岩石、树木、燃烧、蒸汽雾、巢穴或奖励格时，右侧会显示地块效果。直接移动状态下点击敌人，右侧还会保留其生命、元素、状态、移动力和全部技能说明；再次选择己方单位会关闭敌人详情。右侧信息可滚动。

战斗画面右侧分为两个独立区域：中间栏查看地块、敌人和行动信息，最右栏滚动查看完整战斗日志。操作详情时不会挤掉日志记录。

Windows 命令行也可运行：

```powershell
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --path 'D:\godot\宝可梦战棋肉鸽'
```

团队成员可在克隆仓库后用 Godot 4.6.2 打开 `project.godot`；若 `godot` 已加入命令行 PATH，也可在仓库根目录运行 `godot --path .`。首次打开时 Godot 会在本地生成 `.godot/` 缓存，无需提交。`artifacts/` 是测试生成的截图，也不纳入仓库。

行动顺序：每轮先由全部己方单位自由安排各自的一次移动、一次技能或捕获机会。点击“结束回合”后先检查敌方是否守住奖励点，再由敌方风怪先行动，其余敌人依部署及增援顺序逐只移动并施法。敌方行动结束后检查我方守点，必要时暂停让玩家选 Buff，再统一结算环境和回合。顶部显示己方各单位剩余行动。速度值保留在配置中，目前不影响行动。

战斗 Buff 包含移动力 +1、飞行、全部已实现减益免疫、技能直接伤害减免 1 点，以及八种技能各自的机制强化。飞行可越过单位、障碍与致死地形，但不能停在单位或障碍上；停在深水、深坑和火焰上不受地面效果影响。Buff 在战斗结束后清除，不进入战后环境卡组。

自动检查：

```powershell
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/stage0_smoke.gd
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/stage1_combat.gd
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/stage2_tactics.gd
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/stage3_environment.gd
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/stage4_capture_flow.gd
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/tactical_preview_undo.gd
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/stage5_environment_cards.gd
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/combat_pressure_rework.gd
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/terrain_status_revision.gd
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/initiative_order.gd
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/enemy_approach_los.gd
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/team_turn_lethal.gd
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/friendly_pass_through.gd
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/temporary_rock_wall.gd
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/skill_revision.gd
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/fire_skill_rework.gd
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/bottom_action_bar.gd
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/battle_inspection.gd
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/battle_buff_rounds.gd
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/buff_skill_upgrades.gd
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/nest_guard_edge_and_ally_cast.gd
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/seven_elements.gd
```

奖励弹窗的实际窗口检查：

```powershell
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/buff_choice_render.gd
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --path 'D:\godot\宝可梦战棋肉鸽' --script res://tests/seven_elements_render.gd
```

## 当前结构

- `scenes/`：主菜单、七选三界面、静态棋盘预览和战斗场景。
- `scripts/grid_spec.gd`：固定 8×8 棋盘尺寸及边界判断。
- `scripts/battle_state.gd`：战斗状态与统一技能规则；`scripts/battle_buff_system.gd`：本场 Buff 候选、描述与敌方选择；`scripts/capture_system.gd`：捕获条件和成功率；`scripts/movement_pathfinder.gd`：一次移动的合法路径；`scripts/enemy_ai.gd`：奖励争夺与训练家优先的敌人移动、技能选择。
- `scripts/run_state.gd`、`scripts/monster_catalog.gd`：本局携带队伍、出战名单、捕获记录和战后经验；`scenes/between_battles.tscn`：战后整备。
- `scripts/environment_card_system.gd` 与 `scripts/map_generator.gd`：环境卡、区域权重、组合与地图可玩性校验；`scripts/terrain_manager.gd` 与 `scripts/environment_resolver.gd`：生成后地形状态和统一元素反应；`scripts/push_resolver.gd`：推击与碰撞；`scripts/combat_config.gd`：原型测试数值和技能配置。
- `scripts/board_grid.gd` 与 `scripts/battle_board.gd`：棋盘显示及点击坐标；`tests/`：阶段 0 至阶段 5 检查。

自动回归仍可使用固定测试布局；实际战斗使用生成地图。环境卡与本局队伍只在当前运行时保留，重新开始本局会清除。经验在本局内累积并显示；永久等级、收藏、存档和路线尚未实现。水怪保有水流与造雨术；电怪使用闪电与放电。七种物种均可在本局出场。

## 团队协作

- 建议从默认分支创建功能分支，通过 Pull Request 合并；不要提交 `.godot/`、测试截图或个人编辑器配置。
- 修改战斗规则时同步更新 `GAME_DESIGN.md`、`TECHNICAL_NOTES.md`、`TEST_CHECKLIST.md` 和 `CHANGELOG.md`；阶段状态见 `DEVELOPMENT_PLAN.md`。
- 提交前运行受影响的 `tests/*.gd` 检查。命令格式为 `godot --headless --path . --script res://tests/测试文件.gd`；界面改动还需在 1280×720 实际窗口查看。

核心规则见 `GAME_DESIGN.md`，阶段状态见 `DEVELOPMENT_PLAN.md`，技术边界见 `TECHNICAL_NOTES.md`。
