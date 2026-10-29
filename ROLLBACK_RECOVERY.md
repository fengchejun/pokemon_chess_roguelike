# 开放地图原型快照与恢复

回退基准提交：`5e64547943e9bce29183862afc777c9d5b4c6714`。

回退前的工作区（含已修改和未跟踪文件）已保存为 Git stash 对象 `a18ce94292bdc2a2bd55179863a7d608de5aaedb`，并设置永久引用 `refs/codex/pre-rollback-tracked`；未跟踪文件树另有 `refs/codex/pre-rollback-untracked`，指向 `7ca311db8a864c41e62d8b86e5b101b24b346ac0`。创建时核对结果为 110 个文件、6691 行新增、758 行删除，其中 53 个未跟踪文件。当前逐场流程的改动不包含在这个原型快照中。

先用 `git show --stat refs/codex/pre-rollback-tracked` 查看快照。若要完整恢复原型，建议在**另一个干净工作树**中执行：

```powershell
git worktree add -b codex/open-world-recovery ..\宝可梦战棋肉鸽-open-world 5e64547943e9bce29183862afc777c9d5b4c6714
git -C ..\宝可梦战棋肉鸽-open-world stash apply a18ce94292bdc2a2bd55179863a7d608de5aaedb
```

恢复前先检查目标目录不存在，避免覆盖现有工作；不要在当前含新改动的工作树直接执行 `stash apply`。已按要求删除 `user://open_world_v1.json`，该运行存档未保存在 Git 快照中；`user://collection_v1.json` 保留。

回退时的用户存档目录里没有 `save_v1.json`，因此没有真实的旧逐场进行中存档可做读档实测。`5e64547` 使用 v3 进行中格式；当前三层流程使用 v8，不能把 v3 文件直接当作可续局存档。新局遇到无法读取的进行中存档会先写出经字节核对的 `save_backup_*.json`，失败则停止开局；永久收藏仍从独立的 `collection_v1.json` 读取。
