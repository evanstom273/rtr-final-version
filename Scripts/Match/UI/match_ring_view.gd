extends PanelContainer
class_name MatchRingView

const MARKER_SCENE := preload("res://Scenes/Match/UI/wrestler_ring_marker.tscn")
const ORDINARY_TRANSITION_SECONDS := 0.24
const AREA_TRANSITION_SECONDS := 0.42
const OVERLAP_OFFSETS := [
	Vector2.ZERO,
	Vector2(-20.0, -7.0),
	Vector2(20.0, 7.0),
	Vector2(0.0, -22.0),
	Vector2(0.0, 22.0),
]

@export var reduced_motion := false
@export var debug_overlay_enabled := false

var _snapshots: Dictionary = {}
var _anchors: Dictionary = {}
var _markers: Dictionary = {}
var _generation := 0
var _event_generation := 0
var _match_ended := false
var _event_tween: Tween
var _last_context: Dictionary = {}

@onready var _ring_canvas: MatchRingCanvas = %RingCanvas
@onready var _marker_layer: Control = %MarkerLayer
@onready var _context_label: Label = %ContextLabel
@onready var _special_label: Label = %SpecialLabel
@onready var _count_badge: PanelContainer = %CountBadge
@onready var _count_text: Label = %CountText


func _ready() -> void:
	ResponsiveUI.register_layout_target(self)
	_marker_layer.resized.connect(_layout_markers)
	_context_label.text = "RING VIEW"
	_special_label.text = ""
	set_process_unhandled_input(OS.is_debug_build())


func _exit_tree() -> void:
	ResponsiveUI.unregister_layout_target(self)
	_cancel_event_tween()
	for marker_value in _markers.values():
		var marker := marker_value as WrestlerRingMarker
		if is_instance_valid(marker):
			marker.settle()


func set_responsive_layout(mode: int, effective_size: Vector2) -> void:
	var portrait_phone := mode == ResponsiveUI.LayoutMode.PHONE and effective_size.y > effective_size.x
	match mode:
		ResponsiveUI.LayoutMode.PHONE:
			custom_minimum_size = Vector2(280.0, 175.0 if not portrait_phone else 150.0)
		ResponsiveUI.LayoutMode.TABLET:
			custom_minimum_size = Vector2(300.0, 220.0)
		_:
			custom_minimum_size = Vector2(340.0, 280.0)
	_marker_layer.scale = Vector2.ONE
	_layout_markers.call_deferred()


func set_participants(snapshots: Array) -> void:
	apply_state_snapshot(snapshots, {"reason": "participants", "immediate": true})


func apply_state_snapshot(snapshots: Array, context: Dictionary = {}) -> void:
	_generation += 1
	_last_context = context.duplicate(true)
	_ring_canvas.set_environment_objects(context.get("environment_objects", []))
	var active_ids: Array[String] = []
	for raw_snapshot in snapshots:
		if not raw_snapshot is Dictionary:
			continue
		var snapshot := (raw_snapshot as Dictionary).duplicate(true)
		var participant_id := str(snapshot.get("id", ""))
		if participant_id.is_empty():
			participant_id = "participant_%d" % active_ids.size()
			snapshot["id"] = participant_id
		active_ids.append(participant_id)
		_snapshots[participant_id] = snapshot
		_ensure_marker(participant_id)

	for existing_id in _markers.keys().duplicate():
		if str(existing_id) not in active_ids:
			var stale_marker := _markers[existing_id] as WrestlerRingMarker
			if is_instance_valid(stale_marker):
				stale_marker.queue_free()
			_markers.erase(existing_id)
			_snapshots.erase(existing_id)
			_anchors.erase(existing_id)

	_resolve_anchors(context)
	_apply_marker_snapshots()
	_layout_markers(bool(context.get("immediate", false)))


func present_event(event: Dictionary) -> void:
	if _match_ended and StringName(event.get("kind", &"")) != &"match_started":
		return
	var kind := StringName(event.get("kind", &""))
	_event_generation += 1
	var actor_id := str(event.get("actor_id", ""))
	var target_id := str(event.get("target_id", ""))
	var actor := _markers.get(actor_id) as WrestlerRingMarker
	var target := _markers.get(target_id) as WrestlerRingMarker
	match kind:
		&"match_started":
			_match_ended = false
			_special_label.text = "BELL"
			_flash_event_label()
		&"control_changed":
			if actor != null:
				actor.pulse(&"control")
		&"move_started":
			if actor != null:
				actor.pulse(&"signature" if bool(event.get("is_signature", false)) else (&"finisher" if bool(event.get("is_finisher", false)) else &"move"))
			_show_action_line(actor_id, target_id, Color(0.95, 0.78, 0.22, 0.85) if bool(event.get("is_finisher", false)) else Color(0.55, 0.78, 1.0, 0.8))
			_special_label.text = str(event.get("label", "MOVE"))
			_flash_event_label()
		&"move_resolved":
			var result := StringName(event.get("result", &"impact"))
			if result in [&"reversal", &"crash"]:
				if actor != null:
					actor.pulse(result)
			else:
				if target != null:
					target.pulse(&"impact")
			_ring_canvas.clear_action_cue()
		&"setup_resolved":
			if actor != null:
				actor.pulse(&"reversal" if bool(event.get("reversed", false)) else &"setup")
		&"pin_started":
			_ring_canvas.set_special_mode(&"pin")
			_special_label.text = "PIN"
			if actor != null:
				actor.pulse(&"pin")
		&"pin_ended":
			_ring_canvas.set_special_mode(&"")
			_special_label.text = ""
		&"submission_started":
			_ring_canvas.set_special_mode(&"submission")
			_special_label.text = "SUBMISSION"
			if actor != null:
				actor.pulse(&"signature" if bool(event.get("is_signature", false)) else &"move")
		&"submission_ended":
			_ring_canvas.set_special_mode(&"")
			_special_label.text = ""
		&"count_started", &"count_updated":
			_count_badge.visible = true
			_count_text.text = "COUNT %d / %d" % [int(event.get("count", 0)), int(event.get("limit", 10))]
			if kind == &"count_updated":
				_special_label.text = str(event.get("count", ""))
				_flash_event_label()
		&"count_reset":
			_count_badge.visible = false
		&"weapon_retrieved":
			_special_label.text = str(event.get("weapon", "WEAPON")).to_upper()
			_flash_event_label()
			if actor != null:
				actor.pulse(&"setup")
		&"weapon_dropped":
			_special_label.text = "%s DOWN" % str(event.get("weapon", "WEAPON")).to_upper()
			_flash_event_label()
			if actor != null:
				actor.pulse(&"setup")
		&"weapon_broken":
			_special_label.text = "%s BROKEN" % str(event.get("weapon", "WEAPON")).to_upper()
			_flash_event_label()
			if actor != null:
				actor.pulse(&"impact")
		&"weapon_attack", &"weapon_reversed":
			_special_label.text = "DQ RISK" if bool(event.get("illegal", false)) else str(event.get("weapon", "WEAPON")).to_upper()
			_flash_event_label()
			if actor != null:
				actor.pulse(&"impact")
		&"environment_setup":
			_special_label.text = str(event.get("weapon", "OBJECT")).to_upper() + " SET"
			_flash_event_label()
		&"table_broken":
			_special_label.text = "TABLE BREAK"
			_flash_event_label()
		&"thumbtacks_used":
			_special_label.text = "INTO THE TACKS"
			_flash_event_label()
		&"match_ended":
			set_match_ended(str(event.get("winner_id", actor_id)))
			var result_label := str(event.get("result", "")).to_upper()
			if not result_label.is_empty():
				_special_label.text = "MATCH OVER • %s" % result_label


func reset_match() -> void:
	_generation += 1
	_match_ended = false
	_anchors.clear()
	_snapshots.clear()
	_last_context.clear()
	_cancel_event_tween()
	_ring_canvas.clear_action_cue()
	_ring_canvas.set_special_mode(&"")
	_special_label.text = ""
	_count_badge.visible = false
	_context_label.text = "RING VIEW"
	for marker_value in _markers.values():
		var marker := marker_value as WrestlerRingMarker
		if is_instance_valid(marker):
			marker.queue_free()
	_markers.clear()


func set_match_ended(winner_id: String) -> void:
	_match_ended = true
	_cancel_event_tween()
	_ring_canvas.clear_action_cue()
	_ring_canvas.set_special_mode(&"")
	_special_label.text = "MATCH OVER"
	_count_badge.visible = false
	for participant_id in _markers:
		var marker := _markers[participant_id] as WrestlerRingMarker
		if not is_instance_valid(marker):
			continue
		marker.settle()
		if str(participant_id) == winner_id:
			marker.pulse(&"finisher")


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not event.is_action_pressed("ui_focus_next"):
		return
	debug_overlay_enabled = not debug_overlay_enabled
	_apply_marker_snapshots()
	get_viewport().set_input_as_handled()


func _ensure_marker(participant_id: String) -> void:
	if _markers.has(participant_id):
		return
	var marker := MARKER_SCENE.instantiate() as WrestlerRingMarker
	marker.name = "Marker_%s" % participant_id.validate_node_name()
	marker.reduced_motion = reduced_motion
	_marker_layer.add_child(marker)
	_markers[participant_id] = marker


func _resolve_anchors(context: Dictionary) -> void:
	var actor_id := str(context.get("actor_id", ""))
	var target_id := str(context.get("target_id", ""))
	var shared_interaction := bool(context.get("shared_interaction", false))
	for participant_id in _snapshots:
		var snapshot := _snapshots[participant_id] as Dictionary
		var partner_id := str(snapshot.get("target_id", ""))
		if partner_id.is_empty():
			partner_id = target_id if str(participant_id) == actor_id else actor_id
		var partner_snapshot := _snapshots.get(partner_id, {}) as Dictionary
		var resolver_context := context.duplicate(true)
		resolver_context["shared_interaction"] = shared_interaction and (str(participant_id) in [actor_id, target_id])
		resolver_context["partner_anchor"] = int(_anchors.get(partner_id, RingVisualPlacementResolver.RingAnchor.NONE))
		if not _anchors.has(participant_id) and int(snapshot.get("area", WrestlerResource.Area.IN_RING)) == WrestlerResource.Area.IN_RING:
			_anchors[participant_id] = (
				RingVisualPlacementResolver.RingAnchor.RING_WEST
				if bool(snapshot.get("is_player", false))
				else RingVisualPlacementResolver.RingAnchor.RING_EAST
			)
		else:
			_anchors[participant_id] = RingVisualPlacementResolver.resolve(
				snapshot,
				int(_anchors.get(participant_id, RingVisualPlacementResolver.RingAnchor.NONE)),
				partner_snapshot,
				resolver_context,
			)


func _apply_marker_snapshots() -> void:
	for participant_id in _snapshots:
		var snapshot := (_snapshots[participant_id] as Dictionary).duplicate(true)
		var partner_id := str(snapshot.get("target_id", ""))
		if partner_id.is_empty():
			partner_id = _first_other_id(str(participant_id))
		var self_position := RingVisualPlacementResolver.canvas_position(int(_anchors.get(participant_id, 0)), _marker_layer.size)
		var partner_position := RingVisualPlacementResolver.canvas_position(int(_anchors.get(partner_id, 0)), _marker_layer.size)
		var facing := partner_position - self_position
		if facing.length_squared() > 0.001:
			snapshot["facing_vector"] = facing.normalized()
		snapshot["debug_visible"] = debug_overlay_enabled and OS.is_debug_build()
		snapshot["debug_text"] = _debug_text(str(participant_id), snapshot)
		var marker := _markers[participant_id] as WrestlerRingMarker
		marker.reduced_motion = reduced_motion
		marker.apply_snapshot(snapshot)


func _layout_markers(force_immediate: bool = false) -> void:
	if not is_instance_valid(_marker_layer) or _marker_layer.size.x <= 1.0:
		return
	var grouped: Dictionary = {}
	for participant_id in _anchors:
		var anchor := int(_anchors[participant_id])
		if not grouped.has(anchor):
			grouped[anchor] = []
		(grouped[anchor] as Array).append(str(participant_id))
	for anchor in grouped:
		var ids := grouped[anchor] as Array
		ids.sort()
		for index in range(ids.size()):
			var participant_id := str(ids[index])
			var marker := _markers.get(participant_id) as WrestlerRingMarker
			if not is_instance_valid(marker):
				continue
			var centre := RingVisualPlacementResolver.canvas_position(int(anchor), _marker_layer.size)
			var offset: Vector2 = OVERLAP_OFFSETS[index % OVERLAP_OFFSETS.size()]
			var target: Vector2 = centre + offset - marker.size * 0.5
			var previous_area := int((_snapshots.get(participant_id, {}) as Dictionary).get("previous_area", -1))
			var current_area := int((_snapshots.get(participant_id, {}) as Dictionary).get("area", -1))
			var duration := AREA_TRANSITION_SECONDS if previous_area >= 0 and previous_area != current_area else ORDINARY_TRANSITION_SECONDS
			marker.move_to(target, duration, force_immediate or bool(_last_context.get("immediate", false)))


func _show_action_line(actor_id: String, target_id: String, color: Color) -> void:
	var actor := _markers.get(actor_id) as WrestlerRingMarker
	var target := _markers.get(target_id) as WrestlerRingMarker
	if not is_instance_valid(actor) or not is_instance_valid(target):
		return
	_ring_canvas.set_action_cue(actor.position + actor.size * 0.5, target.position + target.size * 0.5, color)


func _flash_event_label() -> void:
	_cancel_event_tween()
	_special_label.modulate = Color.WHITE
	var event_generation := _event_generation
	_event_tween = create_tween()
	_event_tween.tween_interval(0.65)
	_event_tween.tween_property(_special_label, "modulate:a", 0.0, 0.18)
	_event_tween.tween_callback(func() -> void:
		if event_generation == _event_generation and _ring_canvas.special_mode.is_empty():
			_special_label.text = ""
			_special_label.modulate = Color.WHITE
	)


func _cancel_event_tween() -> void:
	if _event_tween != null and _event_tween.is_valid():
		_event_tween.kill()
	_event_tween = null
	if is_instance_valid(_special_label):
		_special_label.modulate = Color.WHITE


func _first_other_id(participant_id: String) -> String:
	for other_id in _snapshots:
		if str(other_id) != participant_id:
			return str(other_id)
	return ""


func _debug_text(participant_id: String, snapshot: Dictionary) -> String:
	return "%s | %s\nP:%d O:%d A:%d M:%d | G:%d" % [
		participant_id,
		RingVisualPlacementResolver.anchor_name(int(_anchors.get(participant_id, 0))),
		int(snapshot.get("position", -1)),
		int(snapshot.get("orientation", -1)),
		int(snapshot.get("area", -1)),
		int(snapshot.get("motion_state", -1)),
		_generation,
	]
