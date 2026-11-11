# 像素战斗实机样板

分支：codex/pixel-battle-sample。基线：f2c02ec。
本目录是独立工作区中的单场战斗样板；主工作区保留回退后的版本。

运行：

```powershell
& D:/godot/tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --path D:/godot/pixel-battle-sample --rendering-method gl_compatibility --script res://sample/capture_sample.gd -- --interactive
```

去掉 `-- --interactive` 会自动保存 battle-v1.png 并退出。窗口为1280×720；8×8棋盘576×576，使用邻近过滤。游戏操作调用原有BattleScreen与BattleState；样板关闭自动存档。

## 美术来源与限制

atlas-v1.png：通过内置image_gen生成的透明4×4图集；未经人工逐像素修整。使用AtlasTexture切片，不把界面截图当游戏背景。生成要求：16格等分，首行为草地、浅水、泥地、岩地；第二行为小火龙、杰尼龟、妙蛙种子、皮卡丘；第三行为治疗药、书、火球、水晶；第四行为树、岩石、宝箱、精灵球。统一左上光源、深紫轮廓、有限色板、透明物体背景；无文字或网格线。

已接入：前三个初始伙伴及皮卡丘的映射、普通泥地、浅水、草地、树木、岩障、技能图标、队伍头像。其他物种与特殊地形保留原始渲染，不能以本样板宣称全部美术完成。第二张补充图集请求未获得图像，未接入。

主题面板为StyleBoxFlat生成；字体为系统中文字体。未制作专用像素字体、动画帧或完整像素九宫格面板资源。

## 验证

- 实机截图：battle-v1.png，1280×720。
- t09_ui_flow：150检查点通过，日志ui-test.log。
- 对应截图渲染日志render.log、render-error.log；日志与截图是本地验证产物。
