# 怪物战棋肉鸽

Godot 4.6.2 / GDScript 的 2D 战棋肉鸽与怪物收集原型。当前实现到**阶段 5，并完成整队回合调整**。8×8 战场按区域与本局卡组生成，深浅水、逐回合蔓延的火焰、易碎地块、巢穴和额外奖励会改变战术选择。

项目方向参考《陷阵之志》《宝可梦》《幻兽帕鲁》《博德之门 3》和《暗黑地牢》：训练家参与战斗，怪物与环境共同形成战术解法。原仓库提出的“由宝可梦参与基地运作”仍是后续设想，当前原型尚未实现。

## 运行

1. 使用 Godot 4.6.2 打开本目录的 `project.godot`。
2. 按 F5 启动项目，点击“开始战斗”。蓝色为己方，红色为敌人。
3. 我方阶段可自由切换所有存活的己方单位。点击单位即可选中并显示可移动格；点击绿色终点，自动沿合法路径一次移动。移动途中可以穿过己方单位，但不能停在其格子上；敌人仍会阻挡。训练家、火怪、水怪最多走 3 格，岩怪最多走 2 格；浸湿使下一回合各减 1 格。每名己方单位每回合只能移动一次，移动与技能资源独立。悬停可看合法路线；成功施放技能、尝试捕获或结束回合之前，可从顶部按逆序撤回多名单位的移动。选择技能或取消瞄准不会关闭撤回。
4. 底栏列出当前怪物的全部技能、消耗及不可用原因。点击技能按钮瞄准，金色格显示可选目标，悬停可看落点和影响范围；再次点击该按钮、按 Esc 或右键可取消瞄准。合法施放后自动回到直接移动；无效施放不会消耗技能点或关闭撤回。火、水射线会被首个树木、岩石、巢穴或单位截断。火种不能打相邻格；中心命中单位造成 2 伤并灼烧，中心为空则十字范围各造成 1 伤。闪焰冲锋可越过中间一格，对经过的非火系单位施加灼烧，落点若是深水或深坑会死亡。水流命中单位造成 1 伤、击退并浸湿，不在原格造水；命中障碍则在障碍前一格造浅水。造雨术在五格曼哈顿距离内选点，将周围 3×3 可转化地块变成浅水。岩怪保留推击与碎岩；造岩时点选相邻方向格，在该方向的垂直线上生成最多三格短墙，命中单位造成 2 伤。短墙在之后的敌方行动结束时消失。普通点击另一名己方单位会选中它并退出瞄准；若造岩方向格有友军，或造雨中心要点在友军脚下，用 Shift＋点击施放。怪物每回合有 1 点技能点。
5. 选中训练家后，底栏显示“捕获”。训练家与生命值不高于一半的野生怪物相邻时，每回合有一次独立于移动的捕获机会；悬停可查看成功率。成功后怪物在战后加入本局携带队伍；失败会消耗本回合捕获机会。
6. 浅蓝“浅”是浅水：训练家和非水系怪物在回合末仍站在其中，会在下一回合浸湿、移动力减 1；水流直接命中的浸湿也会保证下一轮减速，即使离开水格。水系免疫。深蓝“深”不可由训练家或非水系怪物主动进入，水系可以进入；所有单位都不能主动进入已塌陷的“坑”。强制位移进入致死格仍立即结算死亡。绿色“草”可站立；火每次结算向相邻可燃物蔓延一格，燃烧两次结算后烧尽。非火系单位受到火种中心命中或站在火焰格结算时会获得灼烧，从下一次完整回合结算起每轮失去 1 HP，入水解除。“裂”是可站立的易碎地块：只有造岩命中会使它塌为永久的“坑”，其上单位立即坠落死亡；造雨可把裂地转为浅水。蒸汽“雾”使站在其中的怪物不能施法，移动与训练家捕获照常。放电沿深浅水连通传导。
7. 每场有一个紫色巢穴和一件黄色奖励。巢穴在第 2、4 回合开始时尝试从出口产怪；新怪出生后立刻移动一次，本轮不能再次移动或施法，下一完整回合才正常行动。占住出口或摧毁巢穴可阻止生成，巢穴存活不妨碍清敌获胜。己方单位站在奖励格直到回合结算才拾取；敌人若能伤及携带者会优先攻击它，携带者死亡则失去奖励。存活到正常战斗结算可在战后额外选择一张环境卡。第四回合后剩余野生怪物逃离；整备页处理捕获、经验、环境卡和下一场出战。
8. 在直接移动状态下点击敌人，可查看红色边框表示的当前合法移动范围；这显示它能走到哪里，并非下一回合的行动预告。技能或捕获瞄准时点击敌人仍会执行当前所选行动。

悬停浅水、深水、草丛、易碎地块、深坑、岩石、树木、燃烧、蒸汽雾、巢穴或奖励格时，右侧会显示地块效果。直接移动状态下点击敌人，右侧还会保留其生命、元素、状态、移动力和全部技能说明；再次选择己方单位会关闭敌人详情。右侧信息可滚动。

战斗画面右侧分为两个独立区域：中间栏查看地块、敌人和行动信息，最右栏滚动查看完整战斗日志。操作详情时不会挤掉日志记录。

Windows 命令行也可运行：

```powershell
& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --path 'D:\godot\宝可梦战棋肉鸽'
```

团队成员可在克隆仓库后用 Godot 4.6.2 打开 `project.godot`；若 `godot` 已加入命令行 PATH，也可在仓库根目录运行 `godot --path .`。首次打开时 Godot 会在本地生成 `.godot/` 缓存，无需提交。`artifacts/` 是测试生成的截图，也不纳入仓库。

行动顺序：每轮先由全部己方单位自由安排各自的一次移动、一次技能或捕获机会。点击“结束回合”后，敌人按初始火、水、岩及随后增援的顺序，逐只移动并施放一次技能。敌方行动结束后统一结算一次环境、奖励和回合。顶部显示己方各单位剩余行动。速度值保留在配置中，目前不影响行动。

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
```

## 当前结构

- `scenes/`：主菜单、静态棋盘预览和战斗场景。
- `scripts/grid_spec.gd`：固定 8×8 棋盘尺寸及边界判断。
- `scripts/battle_state.gd`：战斗状态与统一技能规则；`scripts/capture_system.gd`：捕获条件和成功率；`scripts/movement_pathfinder.gd`：一次移动的安全路径；`scripts/enemy_ai.gd`：训练家优先的敌人移动与技能选择。
- `scripts/run_state.gd`、`scripts/monster_catalog.gd`：本局携带队伍、出战名单、捕获记录和战后经验；`scenes/between_battles.tscn`：战后整备。
- `scripts/environment_card_system.gd` 与 `scripts/map_generator.gd`：环境卡、区域权重、组合与地图可玩性校验；`scripts/terrain_manager.gd` 与 `scripts/environment_resolver.gd`：生成后地形状态和统一元素反应；`scripts/push_resolver.gd`：推击与碰撞；`scripts/combat_config.gd`：原型测试数值和技能配置。
- `scripts/board_grid.gd` 与 `scripts/battle_board.gd`：棋盘显示及点击坐标；`tests/`：阶段 0 至阶段 5 检查。

自动回归仍可使用固定测试布局；实际战斗使用生成地图。环境卡与本局队伍只在当前运行时保留，重新开始本局会清除。经验在本局内累积并显示；永久等级、收藏、存档和路线尚未实现。水电怪的水流、放电与造雨术用于验证四元素联动。

## 团队协作

- 建议从默认分支创建功能分支，通过 Pull Request 合并；不要提交 `.godot/`、测试截图或个人编辑器配置。
- 修改战斗规则时同步更新 `GAME_DESIGN.md`、`TECHNICAL_NOTES.md`、`TEST_CHECKLIST.md` 和 `CHANGELOG.md`；阶段状态见 `DEVELOPMENT_PLAN.md`。
- 提交前运行受影响的 `tests/*.gd` 检查。命令格式为 `godot --headless --path . --script res://tests/测试文件.gd`；界面改动还需在 1280×720 实际窗口查看。

核心规则见 `GAME_DESIGN.md`，阶段状态见 `DEVELOPMENT_PLAN.md`，技术边界见 `TECHNICAL_NOTES.md`。
