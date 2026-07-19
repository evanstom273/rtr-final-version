extends Node

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://Scenes/Match/simple_match_ui.tscn") as PackedScene
	_check(packed != null, "main match scene loads")
	if packed == null:
		_finish()
		return
	var match_ui := packed.instantiate() as SimpleMatchUI
	_check(match_ui != null, "main match scene instantiates")
	if match_ui == null:
		_finish()
		return
	get_tree().root.add_child(match_ui)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not match_ui._match_initialized, "initial setup opens before a match is initialized")
	_check(match_ui._match_setup_popup.visible, "initial setup popup is visible")
	_check(match_ui._roster.size() >= 2, "at least two wrestlers load through ResourceLoader")
	if match_ui._roster.size() < 2:
		match_ui.queue_free()
		_finish()
		return

	var popup := match_ui._match_setup_popup as MatchSetupPopup
	popup._rng.seed = 937451
	var roster_scroll := popup._player_list.get_v_scroll_bar()
	roster_scroll.value = 0.0
	var touch_down := InputEventScreenTouch.new()
	touch_down.index = 0
	touch_down.pressed = true
	touch_down.position = Vector2(40.0, 80.0)
	popup._on_roster_list_gui_input(touch_down, popup._player_list)
	var finger_drag := InputEventScreenDrag.new()
	finger_drag.index = 0
	finger_drag.position = Vector2(40.0, 20.0)
	finger_drag.relative = Vector2(0.0, -60.0)
	popup._on_roster_list_gui_input(finger_drag, popup._player_list)
	_check(
		roster_scroll.value > 0.0 or roster_scroll.max_value <= roster_scroll.page,
		"roster ItemLists respond to vertical finger drags",
	)
	var touch_up := InputEventScreenTouch.new()
	touch_up.index = 0
	touch_up.pressed = false
	touch_up.position = Vector2(40.0, 20.0)
	popup._on_roster_list_gui_input(touch_up, popup._player_list)
	var random_pair := popup._choose_random_pair(false, false)
	_check(not random_pair.is_empty(), "random matchup exists for unfiltered roster")
	if not random_pair.is_empty():
		_check(
			not popup._same_wrestler(random_pair.player, random_pair.opponent),
			"random matchup never duplicates a wrestler",
		)
	popup._on_random_match_pressed()
	_check(
		popup.visible and not popup._launch_pending and not match_ui._match_initialized,
		"random matchup previews selections without launching",
	)
	popup._on_start_pressed()
	_check(match_ui._match_initialized and not popup.visible, "Start accepts the previewed matchup exactly once")
	_check(
		not match_ui.match_log_entries.is_empty()
		and str(match_ui.match_log_entries[0]).contains("bell rings"),
		"opening bell is logged before the first scheduled continuation",
	)
	match_ui._turn_generation += 1
	match_ui._scheduled_ai_generation = -1
	match_ui._scheduled_neutral_generation = -1
	match_ui._match_initialized = false
	popup.open_setup(match_ui._roster, match_ui.player_wrestler, match_ui.ai_wrestler, false)

	popup._player_locked = true
	popup._selected_player = match_ui._roster[0]
	var locked_pair := popup._choose_random_pair(true, false)
	_check(
		not locked_pair.is_empty() and popup._same_wrestler(locked_pair.player, match_ui._roster[0]),
		"Player lock preserves the selected wrestler",
	)
	popup._player_locked = false
	popup._player_filtered_indices.clear()
	popup._player_filtered_indices.append(0)
	popup._opponent_filtered_indices.clear()
	popup._opponent_filtered_indices.append(1)
	popup._recent_wrestler_paths = PackedStringArray([
		match_ui._roster[0].resource_path,
		match_ui._roster[1].resource_path,
	])
	var recent_pair := popup._choose_random_pair(false, false)
	_check(not recent_pair.is_empty(), "recent-history avoidance relaxes when necessary")
	popup._player_filtered_indices.clear()
	var empty_pair := popup._choose_random_pair(false, false)
	_check(empty_pair.is_empty(), "empty filtered pool cannot launch a random matchup")
	popup._player_filtered_indices.append(0)
	popup._opponent_filtered_indices.clear()
	popup._opponent_filtered_indices.append(1)
	popup._recent_wrestler_paths.clear()

	var setup_scene := load("res://Scenes/Match/match_setup_popup.tscn") as PackedScene
	var guarded_popup := setup_scene.instantiate() as MatchSetupPopup
	get_tree().root.add_child(guarded_popup)
	await get_tree().process_frame
	var launch_count := [0]
	guarded_popup.match_requested.connect(func(
		_player: WrestlerResource,
		_opponent: WrestlerResource,
		_metadata: Dictionary,
	) -> void:
		launch_count[0] = int(launch_count[0]) + 1
	)
	guarded_popup.open_setup(match_ui._roster, match_ui._roster[0], match_ui._roster[1], false)
	guarded_popup._on_start_pressed()
	guarded_popup._on_start_pressed()
	_check(int(launch_count[0]) == 1 and guarded_popup._launch_pending, "rapid Start presses emit exactly one launch")
	guarded_popup.reject_launch("Regression rejection")
	_check(not guarded_popup._launch_pending, "rejected launch re-enables setup")
	guarded_popup.queue_free()

	match_ui.player_wrestler = match_ui._roster[0]
	match_ui.ai_wrestler = match_ui._roster[1]
	match_ui.player_side_state.initialize(match_ui.player_wrestler)
	match_ui.ai_side_state.initialize(match_ui.ai_wrestler)
	match_ui._match_setup_metadata = {
		"match_setup": "Random Both",
		"player_locked": false,
		"ai_locked": false,
		"player_randomly_selected": true,
		"ai_randomly_selected": true,
	}
	var report := match_ui._build_match_report()
	_check(str(report.get("match_setup", "")) == "Random Both", "report contains setup method")
	_check(bool(report.get("player_randomly_selected", false)), "report contains Player random flag")
	_check(str(report.get("export_text", "")).contains("Match setup: Random Both"), "text export contains setup metadata")

	var recovery_matrix: Array[Dictionary] = [
		{"position": WrestlerResource.Position.GROUNDED, "area": WrestlerResource.Area.IN_RING, "motion": WrestlerResource.MotionState.STATIONARY, "action": SetupActionsMenu.STAND_UP},
		{"position": WrestlerResource.Position.STANDING, "area": WrestlerResource.Area.IN_RING, "motion": WrestlerResource.MotionState.RUNNING, "action": SetupActionsMenu.STOP_RUNNING},
		{"position": WrestlerResource.Position.STANDING, "area": WrestlerResource.Area.ROPES, "motion": WrestlerResource.MotionState.ROPE_REBOUND, "action": SetupActionsMenu.REGAIN_FOOTING},
		{"position": WrestlerResource.Position.STANDING, "area": WrestlerResource.Area.CORNER, "motion": WrestlerResource.MotionState.STATIONARY, "action": SetupActionsMenu.LEAVE_CORNER},
		{"position": WrestlerResource.Position.PERCHED, "area": WrestlerResource.Area.TOP_ROPE, "motion": WrestlerResource.MotionState.STATIONARY, "action": SetupActionsMenu.CLIMB_DOWN},
		{"position": WrestlerResource.Position.STANDING, "area": WrestlerResource.Area.APRON, "motion": WrestlerResource.MotionState.STATIONARY, "action": SetupActionsMenu.RETURN_TO_RING},
	]
	for recovery_case in recovery_matrix:
		match_ui.player_side_state.set_match_state(
			int(recovery_case.position),
			WrestlerResource.Orientation.FRONT,
			int(recovery_case.area),
			int(recovery_case.motion),
		)
		var recoveries := match_ui.get_valid_setup_actions(SimpleMatchUI.Side.PLAYER)
		_check(
			StringName(recovery_case.action) in recoveries,
			"State %s has an authored recovery" % str(recovery_case),
		)
	match_ui._set_neutral_ring_stance(match_ui.player_side_state)
	match_ui._set_neutral_ring_stance(match_ui.ai_side_state)
	match_ui._match_initialized = true
	match_ui._set_controller(SimpleMatchUI.ControlState.AI_CONTROL)
	var scheduled_generation := match_ui._scheduled_ai_generation
	match_ui._schedule_current_turn()
	_check(
		scheduled_generation == match_ui._scheduled_ai_generation
		and scheduled_generation == match_ui._turn_generation,
		"AI scheduling is deduplicated per generation",
	)
	var snapshot := match_ui.get_match_flow_snapshot("regression")
	_check(snapshot.has("interaction_request") and snapshot.has("scheduled_ai_generation"), "flow snapshot contains continuation diagnostics")

	match_ui._turn_generation += 1
	match_ui._match_initialized = false
	match_ui.queue_free()
	await get_tree().process_frame
	_finish()


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS | ", description)
	else:
		_failures.append(description)
		push_error("FAIL | %s" % description)


func _finish() -> void:
	if _failures.is_empty():
		print("MATCH FLOW REGRESSION: PASS")
		get_tree().quit(0)
	else:
		print("MATCH FLOW REGRESSION: %d FAILURE(S)" % _failures.size())
		get_tree().quit(1)
