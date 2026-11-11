# 草丛物体 v1

由 imagegen 生成，参考 `atlas-v1.png` 的树木和草地配色，透明背景。

Prompt: One isolated upright tall-grass clump for an isometric pixel-art tactical RPG. Muted olive and moss greens, yellow-green top-left highlights, dark forest-green base. Wide low mound of pointed blades, elevated 3/4 view, stepped pixel edges and broad clusters. Effective resolution approximately 80x48. Transparent background, no ground, labels, border, or other objects.

运行时按 94x52 绘制；草簇在单位本体之后绘制，遮挡脚部，双方均保持不透明。浅水和深水通过与地面纹理精确对齐的前景水层遮住下半身，深水遮挡更多；血条、选中框和状态提示绘制在遮挡层上方。
