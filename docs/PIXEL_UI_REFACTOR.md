# 像素 UI 重构覆盖清单

基线：88ade89。场景由脚本动态构建；此清单记录待验收范围，不代表已全部完成。

## 场景

- scenes/main.tscn → scripts/main.gd（公共主题由 UIKit.setup_theme 应用）

## UI 脚本
- [ ] scripts/ui/battle_feedback.gd
- [ ] scripts/ui/battle_notice.gd
- [ ] scripts/ui/battle_playback.gd
- [ ] scripts/ui/battle_screen.gd
- [ ] scripts/ui/board_view.gd
- [ ] scripts/ui/camp_screen.gd
- [ ] scripts/ui/camp_services.gd
- [ ] scripts/ui/collection_screen.gd
- [ ] scripts/ui/debug_console.gd
- [ ] scripts/ui/exploration_map_screen.gd
- [ ] scripts/ui/exploration_node_screen.gd
- [ ] scripts/ui/floor_theme_screen.gd
- [ ] scripts/ui/garrison_dialog.gd
- [ ] scripts/ui/item_bag_screen.gd
- [ ] scripts/ui/menu_screen.gd
- [ ] scripts/ui/monster_growth_choices.gd
- [ ] scripts/ui/music_director.gd
- [ ] scripts/ui/prep_screen.gd
- [ ] scripts/ui/preview_screen.gd
- [ ] scripts/ui/region_screen.gd
- [ ] scripts/ui/run_end_screen.gd
- [ ] scripts/ui/settlement_screen.gd
- [ ] scripts/ui/skill_banner.gd
- [ ] scripts/ui/skill_stats_screen.gd
- [ ] scripts/ui/speech_bubble_shape.gd
- [ ] scripts/ui/speech_bubbles.gd
- [ ] scripts/ui/supply_screen.gd
- [ ] scripts/ui/ui_kit.gd

## 当前验证

- t09_ui_flow：150 检查点通过。
- t90_item_bag_shops：25 检查点通过。
- t91_growth_intel：58 检查点通过。
- 截图流程 tests/capture_pixel_ui.gd 输出 outputs/pixel_ui，待逐图验收。
- 全量回归输出 outputs/pixel_regression.log，结果待检查。

## 尚需逐项完成

- 各界面属性和数量展示接入 Icon + Value。
- 技能库、整备、商店、奖励背包等剩余列表网格化。
- 所有主界面容器、紧凑边距、滚动与尺寸适配。
- 键盘导航、悬浮详情、禁用状态及弹窗视觉验收。
- 确认测试日志无脚本错误；完成后仅提交本次改动。

## 阶段检查点（2026-11-10）

- 公共主题、按钮反馈、属性徽章、血条、方格与详情组件已接入。
- 战斗技能/道具、整备装备位、背包、节点商店、补给奖励、战后奖励、学招替换已完成首轮布局改造。
- 收藏改为宽屏双列/窄屏单列；菜单与主题选择页收拢布局。
- 当前完整回归：101 用例、13261 检查点通过，日志 outputs/pixel_regression.log。
- 已查看收藏、整备、战斗技能、主题选择、补给的渲染截图；其余截图仍需逐项检查。
- t87 曾出现随机新局宝箱不可直接移动拾取的间歇失败；本轮通过，不代表根因已消除。未修改机制或用例规避。
- 此提交是阶段回退点，所有覆盖清单勾选保留待最终审计。
