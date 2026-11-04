extends Control
## All records are detached presentation snapshots. No rule method is called here.
var screen: Control
var frames: Array = []
var queue: Array = []
var current: Dictionary = {}
var visual: BattleState
var elapsed := 0.0
var duration := 1.0
var steps: Array = []
var next_step := 0
var applied_final := false
var final_time := 0.5
var collision_cues: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 10
	visual = screen.state.clone()

func active() -> bool:
	return not current.is_empty() or not queue.is_empty() or not frames.is_empty()

func begin(info: Dictionary) -> void:
	var snapshot: BattleState = screen.state.clone()
	if not frames.is_empty() and info["kind"] == "result":
		frames.append({"info": info, "before": snapshot, "events": [], "merge": true})
		return
	if not frames.is_empty():
		_flush(frames.back(), snapshot, {})
		frames.back()["before"] = snapshot
		frames.back()["events"] = []
	frames.append({"info": info.duplicate(true), "before": snapshot, "events": []})

func finish(meta: Dictionary) -> void:
	if frames.is_empty():
		return
	var snapshot: BattleState = screen.state.clone()
	var frame: Dictionary = frames.pop_back()
	if bool(frame.get("merge", false)):
		frames.back()["events"].append_array(frame["events"])
		return
	if bool(meta.get("ok", true)):
		_flush(frame, snapshot, meta)
	if not frames.is_empty():
		frames.back()["before"] = snapshot
		frames.back()["events"] = []

func capture(event: Dictionary) -> void:
	var step := {"event": event.duplicate(true), "after": screen.state.clone()}
	if not frames.is_empty():
		frames.back()["events"].append(step)
	else:
		var prior: BattleState = queue.back()["after"] if not queue.is_empty() else current["after"] if not current.is_empty() else visual
		queue.append({"info": {"kind": "environment", "uid": event["uid"]}, "before": prior, "after": step["after"], "events": [step], "meta": {}})

func _flush(frame: Dictionary, after: BattleState, meta: Dictionary) -> void:
	var info: Dictionary = frame["info"]
	var uid := int(info.get("uid", -1))
	var before_unit: CombatUnit = frame["before"].unit_by_uid(uid)
	var after_unit := after.unit_by_uid(uid)
	var moved := before_unit != null and after_unit != null and before_unit.cell != after_unit.cell
	if frame["events"].is_empty() and not moved:
		return
	# Environmental ticks on different units get separate short result groups.
	if info["kind"] == "environment":
		var group: Array = []
		var prior: BattleState = frame["before"]
		var last_uid := -9999
		for step in frame["events"]:
			var target_uid := int(step["event"]["uid"])
			if not group.is_empty() and target_uid != last_uid:
				var end: BattleState = group.back()["after"]
				queue.append({"info": info, "before": prior, "after": end, "events": group, "meta": {}})
				prior = end
				group = []
			group.append(step)
			last_uid = target_uid
		if not group.is_empty():
			queue.append({"info": info, "before": prior, "after": after, "events": group, "meta": meta})
	else:
		queue.append({"info": info, "before": frame["before"], "after": after, "events": frame["events"].duplicate(), "meta": meta.duplicate(true)})

func _start() -> void:
	screen.feedback_layer.clear()
	current = queue.pop_front()
	elapsed = 0.0
	next_step = 0
	applied_final = false
	steps = []
	collision_cues = []
	screen.board.presentation_offsets.clear()
	visual = current["before"]
	var info: Dictionary = current["info"]
	var kind := String(info["kind"])
	var declare := kind == "skill" and bool(SkillDB.get_def(String(info.get("skill", ""))).get("channel", false)) and not bool(info.get("release", false))
	duration = 0.55 if declare else 1.0 if kind == "skill" else 0.22 if kind == "move" else 0.35
	var impact := 0.25 if declare else 0.5 if kind == "skill" else 0.12 if kind == "move" else 0.04
	var previous: BattleState = current["before"]
	var shift := 0.0
	var damaged: Dictionary = {}
	for step in current["events"]:
		var event: Dictionary = step["event"]
		if event["kind"] == "skill":
			screen.skill_banner.present(String(event["text"]))
			continue
		var uid := int(event["uid"])
		var earlier := previous.unit_by_uid(uid)
		var later: CombatUnit = step["after"].unit_by_uid(uid)
		var moved := earlier != null and later != null and earlier.cell != later.cell
		var repeated_damage: bool = event["kind"] in ["damage", "collision_damage"] and damaged.has(uid)
		if event["kind"] == "collision":
			shift += 0.24
			collision_cues.append({"time": impact + shift, "event": event.duplicate(true)})
		elif event["kind"] == "collision_damage" and not collision_cues.is_empty():
			shift = maxf(shift, float(collision_cues.back()["time"]) - impact + 0.04)
		elif moved or repeated_damage:
			shift += 0.12
		if event["kind"] in ["damage", "collision_damage"]:
			damaged[uid] = true
		steps.append({"time": impact + shift, "event": event, "after": step["after"]})
		previous = step["after"]
	if not steps.is_empty():
		duration = maxf(duration, steps.back()["time"] + 0.5)
	final_time = 0.5 if kind == "skill" else 0.12 if kind == "move" else 0.04
	if kind == "skill":
		for unit in current["before"].units:
			var later: CombatUnit = current["after"].unit_by_uid(unit.uid)
			if later != null and later.cell != unit.cell:
				final_time = 0.68
				duration = maxf(duration, 1.1)
	screen._render_playback(visual)

func _process(delta: float) -> void:
	if screen.modal_layer != null:
		return
	advance(delta * screen.app.battle_playback_speed)

func advance(delta: float) -> void:
	if current.is_empty():
		if queue.is_empty():
			return
		_start()
	elapsed += delta
	while next_step < steps.size() and elapsed >= float(steps[next_step]["time"]):
		var step: Dictionary = steps[next_step]
		visual = step["after"]
		screen._render_playback(visual)
		screen._show_feedback(step["event"])
		next_step += 1
	var completion_time := 0.5 if current["info"]["kind"] == "skill" else 0.12 if current["info"]["kind"] == "move" else 0.04
	if not steps.is_empty():
		completion_time = maxf(completion_time, steps.back()["time"])
	if not applied_final and elapsed >= maxf(completion_time, final_time):
		visual = current["after"]
		screen._render_playback(visual)
		applied_final = true
	_update_collision_motion()
	queue_redraw()
	if elapsed >= duration:
		current = {}
		screen.board.presentation_offsets.clear()
		screen.board.queue_redraw()
		screen.skill_banner.dismiss()
		queue_redraw()
		if queue.is_empty() and frames.is_empty():
			visual = screen.state.clone()
			screen._render_playback(visual)
			screen._playback_finished()

func finish_all() -> void:
	# Deterministic test/explicit scene-teardown helper; never runs game rules.
	while not queue.is_empty() or not current.is_empty():
		advance(100.0)

func _draw() -> void:
	if current.is_empty():
		return
	_draw_collisions()
	_draw_departures()
	var info: Dictionary = current["info"]
	var before: BattleState = current["before"]
	var actor := before.unit_by_uid(int(info.get("uid", -1)))
	var skill := String(info.get("skill", ""))
	var color: Color = {"fire": Color("ff975a"), "water": Color("66cfff"), "electric": Color("ffe271"), "grass": Color("7ce291"), "rock": Color("d3b58b")}.get(SkillDB.element_of(skill), Color("b4ccf4"))
	var progress := clampf(elapsed / duration, 0.0, 1.0)
	if actor != null:
		var center := (Vector2(actor.cell) + Vector2.ONE * 0.5) * BoardView.TILE
		draw_arc(center, 28.0 + sin(progress * PI) * 4.0, 0, TAU, 32, color, 3.0)
		if info["kind"] == "move":
			var route := PackedVector2Array([center])
			for cell in info.get("path", []):
				route.append((Vector2(cell) + Vector2.ONE * 0.5) * BoardView.TILE)
			if route.size() > 1:
				draw_polyline(route, color, 3.0)
	if info["kind"] != "skill":
		return
	var pushed: Dictionary = current["meta"].get("obstacle_push", {})
	if not pushed.is_empty() and (pushed.get("moved", false) or pushed.get("filled", false)):
		var rock_from := (Vector2(pushed["from"]) + Vector2.ONE * 0.5) * BoardView.TILE
		var rock_to := (Vector2(pushed["to"]) + Vector2.ONE * 0.5) * BoardView.TILE
		draw_line(rock_from, rock_to, Color("d3b58b"), 3.0)
		if elapsed >= 0.4 and elapsed <= 0.7:
			var rock_pos := rock_from.lerp(rock_to, clampf((elapsed - 0.4) / 0.3, 0.0, 1.0))
			draw_rect(Rect2(rock_pos - Vector2(16, 16), Vector2(32, 32)), Color("a68f73"))
	var cells: Array = current["meta"].get("area_cells", []).duplicate()
	for event_step in current["events"]:
		var e: Dictionary = event_step["event"]
		if e["kind"] in ["damage", "zero", "heal", "status", "death", "effective", "resisted"] and not cells.has(e["cell"]):
			cells.append(e["cell"])
	if cells.is_empty():
		var ray: Array = current["meta"].get("ray_cells", [])
		if not ray.is_empty():
			cells = ray.duplicate() if skill == "flame_jet" else [ray.back()]
		elif info.has("target") and info["target"].has("cell"):
			cells.append(info["target"]["cell"])
	if cells.is_empty() and actor != null:
		cells.append(actor.cell)
	var def := SkillDB.get_def(skill)
	var declaration := bool(def.get("channel", false)) and not bool(info.get("release", false))
	var support := String(def.get("kind", "")) in ["self", "teleport"] or skill in ["herbal_heal", "double_cast", "leech_seed", "rain_call", "rain_dance", "tree_man", "tailwind", "wild_vines", "frozen_ground"]
	var flight := clampf((elapsed - 0.2) / 0.3, 0.0, 1.0)
	for cell in cells:
		if _collision_cell_active(cell):
			continue
		var target := (Vector2(cell) + Vector2.ONE * 0.5) * BoardView.TILE
		if declaration:
			draw_rect(Rect2(target - Vector2.ONE * 25, Vector2.ONE * 50), Color(color, 0.15 + progress * 0.1), false, 2.0)
			continue
		if support:
			draw_arc(target, 8.0 + progress * 25.0, 0, TAU, 24, Color(color, 1.0 - progress * 0.6), 3.0)
			if skill == "herbal_heal":
				draw_line(target - Vector2(6, 0), target + Vector2(6, 0), color, 3.0)
				draw_line(target - Vector2(0, 6), target + Vector2(0, 6), color, 3.0)
			continue
		if elapsed < 0.2:
			continue
		if skill in ["earth_shake", "tsunami"] and elapsed < 0.5:
			draw_arc(target, 5.0 + flight * 25.0, 0, TAU, 24, Color(color, 0.6), 2.0)
			continue
		if actor != null and elapsed < 0.5:
			if skill == "fire_burst":
				var centers: Array = info.get("cells", [])
				if not centers.is_empty() and cell != centers[0]:
					continue
			var start := (Vector2(actor.cell) + Vector2.ONE * 0.5) * BoardView.TILE
			if skill in ["lightning", "rock_slide", "earth_shake"]:
				start = target - Vector2(0, 60)
			var tip := start.lerp(target, flight)
			if SkillDB.element_of(skill) == "electric":
				var points := PackedVector2Array([start, start.lerp(tip, 0.33) + Vector2(5, -8), start.lerp(tip, 0.66) + Vector2(-5, 8), tip])
				draw_polyline(points, color, 3.0)
			elif SkillDB.element_of(skill) == "rock":
				draw_colored_polygon(PackedVector2Array([tip + Vector2(0, -7), tip + Vector2(7, 3), tip + Vector2(-5, 7)]), color)
			elif SkillDB.element_of(skill) == "grass":
				draw_arc(tip, 10, 0, TAU * flight, 20, color, 3.0)
			else:
				draw_line(tip.lerp(start, 0.15), tip, Color(color, 0.5), 5.0)
				draw_circle(tip, 6.0, color)
		else:
			var fade := clampf((duration - elapsed) / 0.5, 0.0, 1.0)
			draw_arc(target, 12.0 + (1.0 - fade) * 20.0, 0, TAU, 24, Color(color, fade), 2.0)
			draw_rect(Rect2(target - Vector2.ONE * 25, Vector2.ONE * 50), Color(color, fade * (0.12 + absf(sin(elapsed * 30.0)) * 0.16)))

func _collision_cell_active(cell: Vector2i) -> bool:
	for cue in collision_cues:
		var event: Dictionary = cue["event"]
		if elapsed >= float(cue["time"]) - 0.22 and cell in [event["cell"], event["start_cell"], event["blocker_cell"]]:
			return true
	return false

func _update_collision_motion() -> void:
	screen.board.presentation_offsets.clear()
	for cue in collision_cues:
		var age := elapsed - float(cue["time"])
		if age < -0.22 or age > 0.36:
			continue
		var event: Dictionary = cue["event"]
		var origin := (Vector2(event["cell"]) + Vector2.ONE * 0.5) * BoardView.TILE
		var start := (Vector2(event["start_cell"]) + Vector2.ONE * 0.5) * BoardView.TILE
		var direction := (Vector2(event["blocker_cell"]) - Vector2(event["cell"])).normalized()
		var desired := start.lerp(origin, smoothstep(0.0, 1.0, (age + 0.22) / 0.22)) if age < 0 else origin + direction * sin(clampf(age / 0.30, 0.0, 1.0) * PI) * 11.0
		var mover := visual.unit_by_uid(int(event["uid"]))
		if mover != null and mover.is_alive():
			var logical := (Vector2(mover.cell) + Vector2.ONE * 0.5) * BoardView.TILE
			screen.board.presentation_offsets[mover.uid] = desired - logical
		var blocker := visual.unit_by_uid(int(event.get("blocker_uid", -1)))
		if blocker != null and blocker.is_alive() and age >= 0:
			screen.board.presentation_offsets[blocker.uid] = direction * sin(age * 55.0) * 5.0 * (1.0 - age / 0.36)
	screen.board.queue_redraw()

func _draw_collisions() -> void:
	for cue in collision_cues:
		var age := elapsed - float(cue["time"])
		if age < -0.08 or age > 0.40:
			continue
		var event: Dictionary = cue["event"]
		var origin := (Vector2(event["cell"]) + Vector2.ONE * 0.5) * BoardView.TILE
		var destination := (Vector2(event["blocker_cell"]) + Vector2.ONE * 0.5) * BoardView.TILE
		var center := origin.lerp(destination, 0.5).clamp(Vector2(12, 12), Vector2(GridSpec.W, GridSpec.H) * BoardView.TILE - Vector2(12, 12))
		var fade := clampf(1.0 - maxf(0.0, age) / 0.40, 0.0, 1.0)
		var color := Color(1.0, 0.66, 0.22, fade)
		var spikes := PackedVector2Array()
		for index in range(16):
			var angle := index * TAU / 16.0
			spikes.append(center + Vector2(cos(angle), sin(angle)) * (19.0 if index % 2 == 0 else 8.0) * (1.0 + maxf(0.0, age)))
		draw_colored_polygon(spikes, color)
		draw_arc(center, 22.0 + maxf(0.0, age) * 35.0, 0, TAU, 24, color, 2.0)
		if GridSpec.is_inside(event["blocker_cell"]):
			draw_rect(Rect2(Vector2(event["blocker_cell"]) * BoardView.TILE + Vector2(5, 5), Vector2.ONE * (BoardView.TILE - 10)), color, false, 3.0)
		var caption := "受阻" if event.get("object_kind") == "edge" else "碰撞"
		var caption_origin := (center + Vector2(-22, 22)).clamp(Vector2.ZERO, Vector2(GridSpec.W, GridSpec.H) * BoardView.TILE - Vector2(44, 22))
		draw_rect(Rect2(caption_origin, Vector2(44, 22)), Color(0.15, 0.10, 0.04, fade))
		draw_string(UIKit.font(), caption_origin + Vector2(5, 17), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
		if event.get("object_kind") == "rock":
			var rocking := origin + (destination - origin).normalized() * sin(clampf(maxf(age, 0.0) / 0.30, 0.0, 1.0) * PI) * 11.0
			draw_rect(Rect2(rocking - Vector2(14, 14), Vector2(28, 28)), Color(0.68, 0.56, 0.40, fade))

func _draw_departures() -> void:
	for step in steps:
		var event: Dictionary = step["event"]
		if event["kind"] != "death" or elapsed < step["time"]:
			continue
		var age := clampf((elapsed - float(step["time"])) / 0.35, 0.0, 1.0)
		var unit: CombatUnit = current["before"].unit_by_uid(int(event["uid"]))
		if unit == null or age >= 1.0:
			continue
		var falling: bool = String(event["text"]) in ["坠落", "溺水", "落入熔岩"]
		var center := (Vector2(event["cell"]) + Vector2.ONE * 0.5) * BoardView.TILE + Vector2(0, age * 16.0 if falling else 0.0)
		var radius := 24.0 * (1.0 - age) if falling else 24.0
		draw_arc(center, maxf(1.0, radius), 0, TAU, 24, Color(1.0, 0.55, 0.4, 1.0 - age), 2.0)
		draw_string(UIKit.font(), center + Vector2(-10, 8), unit.glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(10, int(26.0 * (1.0 - age))) if falling else 26, Color(0.9, 0.8, 0.7, 1.0 - age))
