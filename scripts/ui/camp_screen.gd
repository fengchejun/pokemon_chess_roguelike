extends "res://scripts/ui/battle_screen.gd"
const CampMap = preload("res://scripts/run/camp_map.gd")
const FIRE_CELL := Vector2i(3, 3)
const STORAGE_CELL := Vector2i(6, 3)
var camp_units: Array:
	get: return state.units

func _ready() -> void:
	state = CampMap.open(app.run)
	super._ready()
	name = "CampScreen"
	hint_label.name = "CampFeedback"
	hint_label.text = "营地已夺回。" if app.run.get_region().nodes["camp"].get("cleared", false) else "营地安全。"
	hint_label.text += "可自由施法布置地形；篝火2耐久、仓库5耐久，被毁后本层永久失效。"

func do_leave_node() -> void:
	if busy or _playback_active():
		return
	app.sync_and_save(state)
	app.leave_camp()

func _on_cell_clicked(cell: Vector2i) -> void:
	_on_board_clicked(cell)

func _unit_at(cell: Vector2i):
	return state.unit_at(cell)

func _open_fire() -> void:
	camp_services._open_fire()

func _show_monster(uid: int) -> void:
	camp_services._show_monster(uid)
