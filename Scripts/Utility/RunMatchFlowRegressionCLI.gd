extends Node

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var flow_packed := load("res://Scenes/Match/exhibition_flow.tscn") as PackedScene
	_check(flow_packed != null, "exhibition flow scene loads")
	if flow_packed == null:
		_finish()
		return
	var flow := flow_packed.instantiate() as ExhibitionFlowController
	_check(flow != null, "exhibition flow scene instantiates")
	if flow == null:
		_finish()
		return
	get_tree().root.add_child(flow)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(flow._setup_screen != null and flow._setup_screen.visible, "initial setup screen is visible before a match is initialized")
	_check(flow._roster.size() >= 2, "at least two wrestlers load through ResourceLoader")
	if flow._roster.size() < 2:
		flow.queue_free()
		_finish()
		return

	var popup := flow._setup_screen as MatchSetupPopup
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
	await get_tree().process_frame
	_check(
		flow._setup_screen != null
		and flow._setup_screen.visible
		and not popup._launch_pending
		and flow._match_screen == null,
		"random matchup previews selections without launching",
	)
	popup._on_start_pressed()
	await get_tree().process_frame
	var match_ui := flow._match_screen as SimpleMatchUI
	_check(match_ui != null and match_ui._match_initialized, "Start accepts the previewed matchup exactly once")
	if match_ui == null:
		flow.queue_free()
		_finish()
		return
	_check(
		not match_ui.match_log_entries.is_empty()
		and str(match_ui.match_log_entries[0]).contains("bell rings"),
		"opening bell is logged before the first scheduled continuation",
	)
	match_ui._turn_generation += 1
	match_ui._scheduled_ai_generation = -1
	match_ui._scheduled_neutral_generation = -1
	match_ui._match_initialized = false
	var setup_screen_scene := load("res://Scenes/Match/exhibition_setup.tscn") as PackedScene
	_check(setup_screen_scene != null, "exhibition setup scene loads independently")
	if setup_screen_scene == null:
		_finish()
		return
	popup = setup_screen_scene.instantiate() as MatchSetupPopup
	get_tree().root.add_child(popup)
	await get_tree().process_frame
	popup.open_setup(flow._roster, null, null, false)

	var match_scene := load("res://Scenes/Match/simple_match_ui.tscn") as PackedScene
	_check(match_scene != null, "active match scene loads")
	if match_scene == null:
		_finish()
		return
	var isolated_match_ui := match_scene.instantiate() as SimpleMatchUI
	_check(isolated_match_ui != null, "active match scene instantiates")
	if isolated_match_ui == null:
		_finish()
		return
	get_tree().root.add_child(isolated_match_ui)
	await get_tree().process_frame
	await get_tree().process_frame
	match_ui = isolated_match_ui

	popup._player_locked = true
	popup._selected_player = flow._roster[0]
	var locked_pair := popup._choose_random_pair(true, false)
	_check(
		not locked_pair.is_empty() and popup._same_wrestler(locked_pair.player, flow._roster[0]),
		"Player lock preserves the selected wrestler",
	)
	popup._player_locked = false
	popup._player_filtered_indices.clear()
	popup._player_filtered_indices.append(0)
	popup._opponent_filtered_indices.clear()
	popup._opponent_filtered_indices.append(1)
	popup._recent_wrestler_paths = PackedStringArray([
		flow._roster[0].resource_path,
		flow._roster[1].resource_path,
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
	guarded_popup.open_setup(flow._roster, null, null, false)
	guarded_popup._assign_to_team(flow._roster[0], true)
	guarded_popup._assign_to_team(flow._roster[1], false)
	guarded_popup._on_start_pressed()
	guarded_popup._on_start_pressed()
	_check(int(launch_count[0]) == 1 and guarded_popup._launch_pending, "rapid Start presses emit exactly one launch")
	guarded_popup.reject_launch("Regression rejection")
	_check(not guarded_popup._launch_pending, "rejected launch re-enables setup")
	guarded_popup.queue_free()

	match_ui.player_wrestler = flow._roster[0]
	match_ui.ai_wrestler = flow._roster[1]
	match_ui.player_side_state.initialize(match_ui.player_wrestler)
	match_ui.ai_side_state.initialize(match_ui.ai_wrestler)
	match_ui.current_controller = SimpleMatchUI.ControlState.PLAYER_CONTROL
	match_ui.match_ended = false
	match_ui.is_resolving_action = false
	match_ui.player_side_state.set_match_state(
		WrestlerResource.Position.STANDING,
		WrestlerResource.Orientation.FRONT,
		WrestlerResource.Area.OUTSIDE,
		WrestlerResource.MotionState.STATIONARY,
	)
	match_ui.ai_side_state.set_match_state(
		WrestlerResource.Position.GROUNDED,
		WrestlerResource.Orientation.FACE_UP,
		WrestlerResource.Area.OUTSIDE,
		WrestlerResource.MotionState.STATIONARY,
	)
	_check(not match_ui._can_pin(SimpleMatchUI.Side.PLAYER), "manual pins are illegal outside")
	_check(
		not match_ui._pin_area_is_legal(SimpleMatchUI.Side.PLAYER, SimpleMatchUI.Side.AI),
		"embedded pins are illegal outside",
	)
	_check(
		not match_ui._submission_area_is_legal(SimpleMatchUI.Side.PLAYER, SimpleMatchUI.Side.AI),
		"submissions are illegal outside",
	)
	match_ui.player_side_state.set_match_state(
		WrestlerResource.Position.STANDING,
		WrestlerResource.Orientation.FRONT,
		WrestlerResource.Area.APRON,
		WrestlerResource.MotionState.STATIONARY,
	)
	match_ui.ai_side_state.set_match_state(
		WrestlerResource.Position.STANDING,
		WrestlerResource.Orientation.FRONT,
		WrestlerResource.Area.IN_RING,
		WrestlerResource.MotionState.STATIONARY,
	)
	match_ui._clear_active_referee_count(false)
	_check(
		not match_ui._side_is_outside(SimpleMatchUI.Side.PLAYER),
		"stepping to the apron does not trigger a count-out",
	)
	_check(
		not match_ui._submission_area_is_legal(SimpleMatchUI.Side.PLAYER, SimpleMatchUI.Side.AI),
		"the count-out-safe apron still does not allow submissions",
	)
	match_ui._settle_referee_count("regression apron setup")
	_check(not match_ui._referee_count_active, "apron springboard setup leaves the referee count inactive")
	var springboard_result := MoveResource.new()
	springboard_result.move_type = MoveResource.MoveType.SPRINGBOARD
	springboard_result.resulting_attacker_position = WrestlerResource.Position.GROUNDED
	springboard_result.resulting_attacker_orientation = WrestlerResource.Orientation.FACE_UP
	springboard_result.resulting_attacker_area_mode = MoveResource.AreaResultMode.SPECIFIC
	springboard_result.resulting_attacker_area = WrestlerResource.Area.IN_RING
	springboard_result.resulting_target_position = WrestlerResource.Position.GROUNDED
	springboard_result.resulting_target_orientation = WrestlerResource.Orientation.FACE_UP
	springboard_result.resulting_target_area_mode = MoveResource.AreaResultMode.SPECIFIC
	springboard_result.resulting_target_area = WrestlerResource.Area.IN_RING
	match_ui.apply_positions(
		SimpleMatchUI.Side.PLAYER,
		SimpleMatchUI.Side.AI,
		springboard_result,
		SimpleMatchUI.ActionResult.CLEAN_SUCCESS,
	)
	match_ui._settle_referee_count("regression apron springboard")
	_check(
		match_ui.player_side_state.current_area == WrestlerResource.Area.IN_RING
		and match_ui.ai_side_state.current_area == WrestlerResource.Area.IN_RING,
		"apron springboard applies its authored in-ring landing",
	)
	_check(
		not match_ui._referee_count_active and match_ui._referee_count_value == 0,
		"apron springboard remains count-out safe through its in-ring landing",
	)
	match_ui._match_setup_metadata = {
		"match_setup": "Random Both",
		"player_locked": false,
		"ai_locked": false,
		"player_randomly_selected": true,
		"ai_randomly_selected": true,
	}
	match_ui.player_side_state.tactical_setup_actions = 2
	match_ui.player_side_state.recovery_setup_actions = 1
	match_ui.player_side_state.contested_setup_attempts = 1
	match_ui.player_side_state.contested_setup_losses = 1
	match_ui.ai_side_state.contested_setup_defensive_interruptions = 1
	match_ui.player_side_state.last_submission_target = MoveResource.MoveTargetParts.LEFT_LEG
	match_ui.player_side_state.last_submission_target_hp_at_lock_in = 82.0
	match_ui.player_side_state.last_submission_target_hp_at_resolution = 71.0
	match_ui.ai_side_state.left_leg_hp = 42.0
	match_ui.player_side_state.head_hp = 55.0
	var report := match_ui._build_match_report()
	_check(str(report.get("match_setup", "")) == "Random Both", "report contains setup method")
	_check(bool(report.get("player_randomly_selected", false)), "report contains Player random flag")
	_check(str(report.get("export_text", "")).contains("Match setup: Random Both"), "text export contains setup metadata")
	_check(str(report.get("export_text", "")).contains("MATCH SUMMARY"), "text export contains Match Summary section")
	_check(str(report.get("export_text", "")).contains("KEY STATS"), "text export contains Key Stats section")
	_check(str(report.get("export_text", "")).contains("DEBUG METRICS"), "text export contains Debug Metrics section")
	var player_report: Dictionary = report.get("player", {})
	var ai_report: Dictionary = report.get("ai", {})
	_check(str(player_report.get("execution_mode", "")) == "automatic_reversal_only", "Player offence has no execution check")
	_check(str(ai_report.get("execution_mode", "")) == "automatic_reversal_only", "AI offence has no execution check")
	_check(int(player_report.get("contested_setup_wins", -1)) == 0, "initiating setup wins are not credited to a defender")
	_check(int(ai_report.get("contested_setup_defensive_interruptions", 0)) == 1, "defensive setup interruption is reported separately")
	_check(str(player_report.get("target_most_damaged_part", "")) == "Left Leg", "report reads target damage from the opponent")
	_check(str(player_report.get("own_most_damaged_part", "")) == "Head", "report labels the wrestler's own damage separately")
	_check(float(player_report.get("last_submission_target_hp_at_lock_in", -1.0)) == 82.0, "report records submission lock-in HP")
	_check(float(player_report.get("last_submission_target_hp_at_resolution", -1.0)) == 71.0, "report records submission resolution HP")
	_check(str(report.get("export_text", "")).contains("Execution: Automatic"), "AI execution mode is explicit in text export")
	_check(str(report.get("export_text", "")).contains("2 tactical | 1 recoveries"), "text export contains setup-action breakdown")

	match_ui.player_side_state.momentum = 0.0
	match_ui.ai_side_state.momentum = 0.0
	match_ui._apply_successful_move_momentum(match_ui.player_side_state)
	_check(match_ui.player_side_state.momentum == 10.0, "Player landed move gains exactly ten momentum")
	_check(match_ui.ai_side_state.momentum == 0.0, "landed move does not drain defender momentum")
	match_ui._apply_successful_move_momentum(match_ui.ai_side_state)
	_check(match_ui.ai_side_state.momentum == 10.0, "AI landed move gains exactly ten momentum")
	match_ui.player_side_state.momentum = 50.0
	match_ui.ai_side_state.momentum = 50.0
	match_ui._apply_reversal_momentum(match_ui.player_side_state, match_ui.ai_side_state)
	_check(match_ui.player_side_state.momentum == 45.0, "Player attacker loses five momentum when reversed")
	_check(match_ui.ai_side_state.momentum == 55.0, "AI defender gains five momentum for a reversal")
	match_ui._apply_reversal_momentum(match_ui.ai_side_state, match_ui.player_side_state)
	_check(match_ui.ai_side_state.momentum == 50.0, "AI attacker loses five momentum when reversed")
	_check(match_ui.player_side_state.momentum == 50.0, "Player defender gains five momentum for a reversal")
	match_ui.player_side_state.momentum = 40.0
	match_ui.ai_side_state.momentum = 40.0
	match_ui._apply_setup_interruption_momentum(match_ui.ai_side_state)
	_check(match_ui.player_side_state.momentum == 40.0, "interrupted Player setup does not lose move momentum")
	_check(match_ui.ai_side_state.momentum == 45.0, "AI gains five momentum for interrupting a Player setup")
	match_ui.player_side_state.momentum = 40.0
	match_ui.ai_side_state.momentum = 40.0
	match_ui._apply_setup_interruption_momentum(match_ui.player_side_state)
	_check(match_ui.ai_side_state.momentum == 40.0, "interrupted AI setup does not lose move momentum")
	_check(match_ui.player_side_state.momentum == 45.0, "Player gains five momentum for interrupting an AI setup")
	match_ui.player_side_state.momentum = 20.0
	match_ui.player_side_state.pending_taunt_momentum_bonus = 0.0
	match_ui._apply_successful_taunt(match_ui.player_side_state)
	_check(match_ui.player_side_state.momentum == 30.0, "successful taunt uses the standard ten-momentum gain")
	_check(match_ui.player_side_state.pending_taunt_momentum_bonus == 0.0, "taunts do not grant delayed bonus momentum")
	if (
		not match_ui.ai_side_state.wrestler.signature_moves.is_empty()
		and not match_ui.ai_side_state.wrestler.finisher_moves.is_empty()
		and not match_ui.ai_side_state.wrestler.move_set.is_empty()
	):
		var priority_engine := MatchAIDecisionEngine.new()
		priority_engine.set_seed(7719)
		var regular_move := match_ui.ai_side_state.wrestler.move_set[0]
		var signature_move := match_ui.ai_side_state.wrestler.signature_moves[0]
		var finisher_move := match_ui.ai_side_state.wrestler.finisher_moves[0]
		match_ui.ai_side_state.signature_ready = true
		match_ui.ai_side_state.finisher_stock = 0
		var signature_choices: Array[MoveResource] = []
		signature_choices.append(regular_move)
		signature_choices.append(signature_move)
		var signature_decision := priority_engine.choose_action(
			match_ui.ai_side_state,
			match_ui.player_side_state,
			signature_choices,
			[],
			1200,
		)
		_check(
			signature_decision.get("move") == signature_move
			and bool(signature_decision.get("special_priority", false)),
			"AI always selects an immediately valid ready signature",
		)
		match_ui.ai_side_state.finisher_stock = 1
		var finisher_choices: Array[MoveResource] = []
		finisher_choices.append(signature_move)
		finisher_choices.append(finisher_move)
		var finisher_decision := priority_engine.choose_action(
			match_ui.ai_side_state,
			match_ui.player_side_state,
			finisher_choices,
			[],
			1200,
		)
		_check(
			finisher_decision.get("move") == finisher_move
			and bool(finisher_decision.get("special_priority", false)),
			"AI prioritizes an immediately valid stocked finisher over a signature",
		)
		var short_setup := {
			"kind": MatchAIDecisionEngine.KIND_SETUP,
			"score": 80.0,
			"setup_action": SetupActionsMenu.CLIMB_TOP_ROPE,
			"setup_path": [SetupActionsMenu.CLIMB_TOP_ROPE],
			"planned_move": signature_move,
		}
		var long_setup := {
			"kind": MatchAIDecisionEngine.KIND_SETUP,
			"score": 120.0,
			"setup_action": SetupActionsMenu.PICK_OPPONENT_UP,
			"setup_path": [SetupActionsMenu.PICK_OPPONENT_UP, SetupActionsMenu.CLIMB_TOP_ROPE],
			"planned_move": signature_move,
		}
		match_ui.ai_side_state.finisher_stock = 0
		var setup_priority := priority_engine._best_ready_special_setup_candidate(
			[long_setup, short_setup],
			match_ui.ai_side_state,
		)
		_check(
			StringName(setup_priority.get("setup_action", &"")) == SetupActionsMenu.CLIMB_TOP_ROPE,
			"AI uses the shortest valid setup path toward a ready signature",
		)
		_check(
			priority_engine.has_credible_finish(
				match_ui.ai_side_state,
				match_ui.player_side_state,
				[],
				false,
				1200,
			),
			"ready signature prevents Catch Breath from pre-empting its setup search",
		)
		match_ui.ai_side_state.signature_ready = false
		match_ui.ai_side_state.finisher_stock = 0
	var hemi_resource := load("res://Wrestlers/ufc/Oceania/Heel/Male/hemi_koro.tres") as WrestlerResource
	if hemi_resource != null and not hemi_resource.signature_moves.is_empty():
		var hemi_state := MatchSideState.new()
		hemi_state.initialize(hemi_resource)
		hemi_state.signature_ready = true
		hemi_state.current_position = WrestlerResource.Position.PERCHED
		hemi_state.current_orientation = WrestlerResource.Orientation.FRONT
		hemi_state.current_area = WrestlerResource.Area.TOP_ROPE
		hemi_state.current_motion_state = WrestlerResource.MotionState.STATIONARY
		var grounded_target := MatchSideState.new()
		grounded_target.initialize(match_ui.player_side_state.wrestler)
		grounded_target.current_position = WrestlerResource.Position.GROUNDED
		grounded_target.current_orientation = WrestlerResource.Orientation.FACE_DOWN
		grounded_target.current_area = WrestlerResource.Area.IN_RING
		grounded_target.current_motion_state = WrestlerResource.MotionState.STATIONARY
		var top_rope_actions: Array[StringName] = [
			SetupActionsMenu.WAKE_OPPONENT,
			SetupActionsMenu.CLIMB_DOWN,
		]
		var loop_engine := MatchAIDecisionEngine.new()
		loop_engine.set_seed(7720)
		_check(
			loop_engine.has_ready_special_continuation(
				hemi_state,
				grounded_target,
				[],
				top_rope_actions,
			),
			"grounded target retains Hemi Koro's wake-opponent signature continuation",
		)
		_check(
			loop_engine.has_reachable_offensive_setup(
				hemi_state,
				grounded_target,
				top_rope_actions,
			),
			"top-rope offence is not mistaken for mandatory climb-down recovery",
		)
		var loop_decision := loop_engine.choose_action(
			hemi_state,
			grounded_target,
			[],
			top_rope_actions,
			920,
		)
		_check(
			StringName(loop_decision.get("setup_action", &"")) == SetupActionsMenu.WAKE_OPPONENT,
			"ready diving signature wakes the grounded opponent instead of looping climb-down",
		)
	var neutral_momentum_move := MoveResource.new()
	neutral_momentum_move.move_impact = 4
	match_ui.player_side_state.momentum = 30.0
	match_ui.ai_side_state.momentum = 40.0
	match_ui.apply_stamina_fatigue_momentum(
		SimpleMatchUI.Side.PLAYER,
		SimpleMatchUI.Side.AI,
		neutral_momentum_move,
		SimpleMatchUI.ActionResult.CONTESTED_STRUGGLE,
	)
	_check(match_ui.player_side_state.momentum == 30.0, "contested exchanges grant no extra attacker momentum")
	_check(match_ui.ai_side_state.momentum == 40.0, "contested exchanges grant no extra defender momentum")
	var reversal_fixture := MoveResource.new()
	reversal_fixture.move_name = "Regression Reversal"
	var light_ai_reversal := match_ui._build_ai_reversal_breakthrough_request(
		{
			"ai_success_chance": 10.0,
			"one_way": true,
			"marker_speed": 1.25,
			"time_limit": 2.0,
		},
		reversal_fixture,
	)
	var strong_ai_reversal := match_ui._build_ai_reversal_breakthrough_request(
		{
			"ai_success_chance": 60.0,
			"one_way": true,
			"marker_speed": 1.25,
			"time_limit": 2.0,
		},
		reversal_fixture,
	)
	_check(
		is_equal_approx(float(light_ai_reversal.get("gold_zone_scale", 0.0)), 1.0 / 8.0),
		"AI reversal breakthrough uses the same one-eighth bar scale as Player reversals",
	)
	_check(
		float(light_ai_reversal.get("player_breakthrough_window", 0.0))
		> float(strong_ai_reversal.get("player_breakthrough_window", 0.0)),
		"stronger AI reversal pressure visibly narrows the Player breakthrough target",
	)
	_check(
		float(light_ai_reversal.get("player_breakthrough_window", 100.0)) <= 4.0
		and float(strong_ai_reversal.get("player_breakthrough_window", 0.0)) >= 3.0,
		"Player-offence breakthrough targets remain inside the tuned 3-to-4-percent range",
	)
	_check(
		bool(light_ai_reversal.get("one_way", false))
		and bool(light_ai_reversal.get("binary_only", false)),
		"AI reversal breakthrough remains a binary one-shot meter",
	)
	_check(
		is_equal_approx(float(light_ai_reversal.get("marker_speed", 0.0)), 1.6),
		"Player-offence reversal sweeper uses the quicker speed",
	)
	_check(
		is_zero_approx(float(light_ai_reversal.get("edge_forgiveness_pixels", -1.0)))
		and is_zero_approx(float(light_ai_reversal.get("touch_edge_forgiveness_pixels", -1.0))),
		"Player-offence reversal target has no desktop or touch edge forgiveness",
	)
	var defensive_reversal_profile := MatchInteractionModel.build_reversal_profile(
		match_ui.ai_side_state,
		match_ui.player_side_state,
		reversal_fixture,
		&"",
		true,
	)
	_check(
		is_zero_approx(float(defensive_reversal_profile.get("edge_forgiveness_pixels", -1.0)))
		and is_zero_approx(float(defensive_reversal_profile.get("touch_edge_forgiveness_pixels", -1.0))),
		"Player-defence reversal target has no desktop or touch edge forgiveness",
	)
	_check(
		float(defensive_reversal_profile.get("success_window", 0.0))
		* float(defensive_reversal_profile.get("gold_zone_scale", 0.0)) >= 3.0,
		"Player-defence reversal target never renders below three percent",
	)
	var setup_breakthrough := match_ui._build_ai_setup_reversal_breakthrough_request(
		{"ai_success_chance": 35.0, "one_way": true},
		SetupActionsMenu.IRISH_WHIP,
	)
	_check(
		str(setup_breakthrough.get("title", "")).to_upper().contains("IRISH WHIP")
		and str(setup_breakthrough.get("button_text", "")) == "COMPLETE SETUP",
		"Player contested setups use the visible AI-reversal breakthrough presentation",
	)
	_check(
		is_zero_approx(float(setup_breakthrough.get("edge_forgiveness_pixels", -1.0)))
		and float(setup_breakthrough.get("player_breakthrough_window", 0.0)) >= 3.0,
		"setup breakthrough uses the same exact visible target bounds as Player offence",
	)
	var hold_scene := load("res://Scenes/Match/hold_release_interaction.tscn") as PackedScene
	var hold_meter := hold_scene.instantiate() as HoldReleaseInteraction
	get_tree().root.add_child(hold_meter)
	await get_tree().process_frame
	var hold_results: Array[Array] = []
	hold_meter.result_selected.connect(func(
		request_id: int,
		result: int,
		timed_out: bool,
		release_value: float,
	) -> void:
		hold_results.append([request_id, result, timed_out, release_value])
	)
	hold_meter.open_interaction({
		"request_id": 701,
		"success_window": 12.0,
		"zone_center": 0.5,
		"fill_duration": 2.7,
		"time_limit": 3.0,
		"pin_count_mode": true,
	})
	hold_meter._holding = true
	hold_meter._value = 0.5
	hold_meter._release_hold()
	_check(
		not hold_results.is_empty()
		and int(hold_results[-1][1]) == MatchInteractionModel.InputResult.SUCCESS,
		"hold-release kickout succeeds when released inside the rendered gold zone",
	)
	hold_meter.open_interaction({
		"request_id": 702,
		"success_window": 12.0,
		"zone_center": 0.5,
		"fill_duration": 2.7,
		"time_limit": 3.0,
		"pin_count_mode": true,
	})
	hold_meter._holding = true
	hold_meter._value = 0.1
	hold_meter._release_hold()
	_check(
		not hold_meter._resolved
		and not hold_meter._hold_button.disabled
		and is_zero_approx(hold_meter._value),
		"release outside gold resets the fill and permits another attempt before three",
	)
	hold_meter._holding = true
	hold_meter._value = 0.5
	hold_meter._release_hold()
	_check(
		int(hold_results[-1][1]) == MatchInteractionModel.InputResult.SUCCESS,
		"a retry inside gold still kicks out during the same referee count",
	)
	hold_meter.open_interaction({
		"request_id": 703,
		"success_window": 12.0,
		"zone_center": 0.5,
		"fill_duration": 2.7,
		"time_limit": 3.0,
		"pin_count_mode": true,
	})
	hold_meter._elapsed = 2.99
	hold_meter._process(0.02)
	_check(
		hold_meter.last_count_reached == 3
		and int(hold_results[-1][1]) == MatchInteractionModel.InputResult.FAIL,
		"hold-release pin fails when the three-real-second count completes",
	)
	hold_meter.queue_free()

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
