class_name MusicDirector
extends AudioStreamPlayer

## 保持一个播放器跨页面存活；相同曲目不重新开始。

const TRACK_PATHS := {
	"title": "res://assets/audio/title.mp3",
	"battle": "res://assets/audio/battle.mp3",
	"prep": "res://assets/audio/prep.mp3",
}

var current_track: String = ""


func _ready() -> void:
	name = "MusicDirector"
	volume_db = -10.0


func _exit_tree() -> void:
	stop()
	stream = null


func play_track(track_id: String) -> void:
	if not TRACK_PATHS.has(track_id):
		return
	if current_track == track_id:
		return
	# 无界面运行没有扬声器；仍更新路由状态，避免测试残留音频线程。
	if DisplayServer.get_name() == "headless":
		current_track = track_id
		return
	var next_stream := load(String(TRACK_PATHS[track_id])) as AudioStreamMP3
	if next_stream == null:
		push_error("无法载入背景音乐：%s" % TRACK_PATHS[track_id])
		return
	next_stream.loop = true
	current_track = track_id
	stream = next_stream
	play()
