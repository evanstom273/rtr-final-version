extends SceneTree

const MAX_REACHABLE_STATES := 6000

var _failures: int = 0


func _initialize() -> void:
	var moves: Array[MoveResource] = []
	_collect_moves("res://Moves", moves)
	_check(moves.size() == 656, "complete Moves folder contains 656 resources")
	_check(not MoveResource.MoveType.has("THROW"), "MoveType has no Throw category")
	_check(not MoveResource.MoveType.has("SLAM"), "MoveType has no Slam category")
	_audit_resource_states(moves)
	_audit_area_rules()
	_audit_setup_projection()
	_audit_two_step_paths(moves)
	_audit_ai_setup_chain(moves)
	_audit_catalogue_reachability(moves)
	if _failures == 0:
		print("CATALOGUE_STATE_REGRESSION: PASS")
	else:
		push_error("CATALOGUE_STATE_REGRESSION: %d failure(s)" % _failures)
	quit(_failures)


func _audit_resource_states(moves: Array[MoveResource]) -> void:
	var valid_count := 0
	var supported_cross_area := 0
	for move in moves:
		var valid := (
			move.required_attacker_position >= WrestlerResource.Position.NONE
			and move.required_attacker_position <= WrestlerResource.Position.PERCHED
			and move.required_target_position >= WrestlerResource.Position.NONE
			and move.required_target_position <= WrestlerResource.Position.PERCHED
			and move.required_attacker_orientation >= WrestlerResource.Orientation.NONE
			and move.required_attacker_orientation <= WrestlerResource.Orientation.FACE_DOWN
			and move.required_target_orientation >= WrestlerResource.Orientation.NONE
			and move.required_target_orientation <= WrestlerResource.Orientation.FACE_DOWN
			and move.required_attacker_motion_state >= WrestlerResource.MotionState.STATIONARY
			and move.required_attacker_motion_state <= WrestlerResource.MotionState.STAGGERING
			and move.required_target_motion_state >= WrestlerResource.MotionState.STATIONARY
			and move.required_target_motion_state <= WrestlerResource.MotionState.STAGGERING
			and move.resulting_attacker_position >= WrestlerResource.Position.NONE
			and move.resulting_attacker_position <= WrestlerResource.Position.PERCHED
			and move.resulting_target_position >= WrestlerResource.Position.NONE
			and move.resulting_target_position <= WrestlerResource.Position.PERCHED
			and move.resulting_attacker_orientation >= WrestlerResource.Orientation.NONE
			and move.resulting_attacker_orientation <= WrestlerResource.Orientation.FACE_DOWN
			and move.resulting_target_orientation >= WrestlerResource.Orientation.NONE
			and move.resulting_target_orientation <= WrestlerResource.Orientation.FACE_DOWN
		)
		if (
			move.required_attacker_area_mode == MoveResource.AreaRequirementMode.SPECIFIC
			and move.required_target_area_mode == MoveResource.AreaRequirementMode.SPECIFIC
			and move.required_attacker_area != move.required_target_area
		):
			valid = valid and MatchAreaRules.is_supported_directional_pair(move.required_attacker_area, move.required_target_area)
			if valid:
				supported_cross_area += 1
		if valid:
			valid_count += 1
	_check(valid_count == moves.size(), "all resources use valid and supported match states")
	_check(supported_cross_area == 178, "all 178 authored cross-area moves use the compatibility matrix")


func _audit_area_rules() -> void:
	_check(MatchAreaRules.is_shared_flat_area(WrestlerResource.Area.IN_RING), "ring is shared-flat")
	_check(MatchAreaRules.is_shared_flat_area(WrestlerResource.Area.OUTSIDE), "outside is shared-flat")
	_check(MatchAreaRules.is_shared_flat_area(WrestlerResource.Area.RAMP), "ramp is shared-flat")
	_check(not MatchAreaRules.is_shared_flat_area(WrestlerResource.Area.APRON), "apron is not shared-flat")
	_check(MatchAreaRules.is_supported_directional_pair(WrestlerResource.Area.TOP_ROPE, WrestlerResource.Area.OUTSIDE), "top-rope to outside is supported")
	_check(not MatchAreaRules.is_supported_directional_pair(WrestlerResource.Area.OUTSIDE, WrestlerResource.Area.TOP_ROPE), "cross-area compatibility remains directional")


func _audit_setup_projection() -> void:
	var outside_actor := _state(WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.OUTSIDE, WrestlerResource.MotionState.STATIONARY)
	var outside_target := outside_actor.duplicate(true)
	var whip := MatchSetupStateRules.project_action(MatchSetupStateRules.IRISH_WHIP, outside_actor, outside_target)
	_check(bool(whip.valid), "Irish whip is valid in a shared outside area")
	_check(int(whip.target.area) == WrestlerResource.Area.OUTSIDE, "Irish whip preserves the shared flat area")
	_check(int(whip.target.motion_state) == WrestlerResource.MotionState.ROPE_REBOUND, "Irish whip applies rope-rebound motion")
	var run := MatchSetupStateRules.project_action(MatchSetupStateRules.START_RUNNING, outside_actor, outside_target)
	_check(int(run.attacker.area) == WrestlerResource.Area.OUTSIDE, "Start Running preserves outside area")
	var grounded_actor := _state(WrestlerResource.Position.GROUNDED, WrestlerResource.Orientation.FACE_UP, WrestlerResource.Area.OUTSIDE, WrestlerResource.MotionState.STATIONARY)
	var stand := MatchSetupStateRules.project_action(MatchSetupStateRules.STAND_UP, grounded_actor, outside_target)
	_check(int(stand.attacker.area) == WrestlerResource.Area.OUTSIDE, "Stand Up preserves area")
	var staggered_target := _state(WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.IN_RING, WrestlerResource.MotionState.STAGGERING)
	var ring_actor := _state(WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.IN_RING, WrestlerResource.MotionState.STATIONARY)
	var recovery_actions := MatchSetupStateRules.get_candidate_actions(ring_actor, staggered_target)
	_check(MatchSetupStateRules.PRESS_ADVANTAGE not in recovery_actions, "staggering target remains a direct authored attack opportunity")
	var rising_target := _state(WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.IN_RING, WrestlerResource.MotionState.RISING)
	var rising_actions := MatchSetupStateRules.get_candidate_actions(ring_actor, rising_target)
	_check(MatchSetupStateRules.PRESS_ADVANTAGE in rising_actions, "rising target exposes the explicit close-in recovery action")
	var recovered := MatchSetupStateRules.project_action(MatchSetupStateRules.PRESS_ADVANTAGE, ring_actor, rising_target)
	_check(int(recovered.target.motion_state) == WrestlerResource.MotionState.STATIONARY, "transient recovery clears only the target motion")
	var outside_taunts := MatchSetupStateRules.get_candidate_actions(outside_actor, outside_target)
	_check(MatchSetupStateRules.TAUNT in outside_taunts, "taunts are legal outside the ring")
	var in_ring_target := _state(WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.IN_RING, WrestlerResource.MotionState.STATIONARY)
	var call_actions := MatchSetupStateRules.get_candidate_actions(outside_actor, in_ring_target)
	_check(MatchSetupStateRules.CALL_OPPONENT_OUTSIDE in call_actions, "an outside wrestler can call an in-ring opponent outside")
	var called_out := MatchSetupStateRules.project_action(MatchSetupStateRules.CALL_OPPONENT_OUTSIDE, outside_actor, in_ring_target)
	_check(int(called_out.attacker.area) == WrestlerResource.Area.OUTSIDE and int(called_out.target.area) == WrestlerResource.Area.OUTSIDE, "calling the opponent outside preserves the caller and moves only the target")


func _audit_two_step_paths(moves: Array[MoveResource]) -> void:
	var neutral := _state(WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.IN_RING, WrestlerResource.MotionState.STATIONARY)
	var outside_dive := _find_move(moves, WrestlerResource.Area.TOP_ROPE, WrestlerResource.Area.OUTSIDE, WrestlerResource.Position.STANDING)
	var rope_springboard := _find_move(moves, WrestlerResource.Area.ROPES, WrestlerResource.Area.OUTSIDE, WrestlerResource.Position.STANDING)
	var apron_attack := _find_move(moves, WrestlerResource.Area.APRON, WrestlerResource.Area.APRON, WrestlerResource.Position.STANDING)
	var seated_corner := _find_move(moves, WrestlerResource.Area.IN_RING, WrestlerResource.Area.CORNER, WrestlerResource.Position.SEATED)
	_check(outside_dive != null, "catalogue has a top-rope outside representative")
	_check(rope_springboard != null, "catalogue has a ropes-to-outside representative")
	_check(apron_attack != null, "catalogue has an apron-to-apron representative")
	_check(seated_corner != null, "catalogue has a seated-corner representative")
	if outside_dive != null:
		_check(_has_path([outside_dive], neutral, neutral, [MatchSetupStateRules.SEND_OPPONENT_OUTSIDE, MatchSetupStateRules.CLIMB_TOP_ROPE]), "outside dive has send-outside then climb path")
	if rope_springboard != null:
		_check(_has_path([rope_springboard], neutral, neutral, [MatchSetupStateRules.SEND_OPPONENT_OUTSIDE, MatchSetupStateRules.STEP_TO_ROPES]), "outside springboard has send-outside then ropes path")
	if apron_attack != null:
		var expected_first := MatchSetupStateRules.PLACE_OPPONENT_ON_APRON_FRONT if apron_attack.required_target_orientation == WrestlerResource.Orientation.FRONT else MatchSetupStateRules.PLACE_OPPONENT_ON_APRON_BACK
		_check(_has_path([apron_attack], neutral, neutral, [expected_first, MatchSetupStateRules.PREPARE_SPRINGBOARD]), "apron attack has opponent-placement then apron path")
	if seated_corner != null:
		_check(_has_path([seated_corner], neutral, neutral, [MatchSetupStateRules.THROW_INTO_CORNER, MatchSetupStateRules.SEAT_OPPONENT_IN_CORNER]), "seated corner move has corner then seat path")


func _audit_ai_setup_chain(moves: Array[MoveResource]) -> void:
	var outside_dive := _find_move(moves, WrestlerResource.Area.TOP_ROPE, WrestlerResource.Area.OUTSIDE, WrestlerResource.Position.STANDING)
	if outside_dive == null:
		return
	var ai_wrestler := WrestlerResource.new()
	var target_wrestler := WrestlerResource.new()
	var one_move_set: Array[MoveResource] = [outside_dive]
	ai_wrestler.move_set = one_move_set
	var ai_state := MatchSideState.new()
	var target_state := MatchSideState.new()
	ai_state.initialize(ai_wrestler)
	target_state.initialize(target_wrestler)
	var engine := MatchAIDecisionEngine.new()
	engine.set_seed(424242)
	var first := engine.choose_action(
		ai_state,
		target_state,
		[],
		[MatchSetupStateRules.SEND_OPPONENT_OUTSIDE],
		0,
	)
	_check(StringName(first.get("setup_action", &"")) == MatchSetupStateRules.SEND_OPPONENT_OUTSIDE, "AI starts the outside-dive setup chain")
	_apply_projection_to_states(ai_state, target_state, MatchSetupStateRules.SEND_OPPONENT_OUTSIDE)
	engine.note_setup_executed(MatchSetupStateRules.SEND_OPPONENT_OUTSIDE, ai_state)
	var second := engine.choose_action(
		ai_state,
		target_state,
		[],
		[MatchSetupStateRules.CLIMB_TOP_ROPE],
		30,
	)
	_check(StringName(second.get("setup_action", &"")) == MatchSetupStateRules.CLIMB_TOP_ROPE, "AI follows the plan instead of treating its second setup as a loop")
	_apply_projection_to_states(ai_state, target_state, MatchSetupStateRules.CLIMB_TOP_ROPE)
	engine.note_setup_executed(MatchSetupStateRules.CLIMB_TOP_ROPE, ai_state)
	var final_move: Array[MoveResource] = [outside_dive]
	var third := engine.choose_action(ai_state, target_state, final_move, [], 60)
	_check(third.get("move") == outside_dive, "AI commits to the planned outside dive")

	var outside_snapshot := _state(WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.OUTSIDE, WrestlerResource.MotionState.STATIONARY)
	var outside_move: MoveResource
	for candidate in moves:
		if MatchSetupStateRules.move_matches_snapshots(candidate, outside_snapshot, outside_snapshot):
			outside_move = candidate
			break
	_check(outside_move != null, "catalogue has an outside-vs-outside AI representative")
	if outside_move != null:
		var caller := MatchSideState.new()
		var called_target := MatchSideState.new()
		var caller_wrestler := WrestlerResource.new()
		caller_wrestler.move_set = [outside_move]
		caller.initialize(caller_wrestler)
		called_target.initialize(WrestlerResource.new())
		caller.set_match_state(WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.OUTSIDE, WrestlerResource.MotionState.STATIONARY)
		called_target.set_match_state(WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.IN_RING, WrestlerResource.MotionState.STATIONARY)
		var call_engine := MatchAIDecisionEngine.new()
		call_engine.set_seed(242424)
		var call_decision := call_engine.choose_action(
			caller,
			called_target,
			[],
			[MatchSetupStateRules.CALL_OPPONENT_OUTSIDE],
			0,
		)
		_check(StringName(call_decision.get("setup_action", &"")) == MatchSetupStateRules.CALL_OPPONENT_OUTSIDE, "AI uses Call Opponent Outside when it creates its exact follow-up")


func _apply_projection_to_states(ai_state: MatchSideState, target_state: MatchSideState, action_id: StringName) -> void:
	var projection := MatchSetupStateRules.project_action(action_id, ai_state.snapshot(), target_state.snapshot())
	var actor: Dictionary = projection.attacker
	var target: Dictionary = projection.target
	ai_state.set_match_state(int(actor.position), int(actor.orientation), int(actor.area), int(actor.motion_state))
	target_state.set_match_state(int(target.position), int(target.orientation), int(target.area), int(target.motion_state))


func _audit_catalogue_reachability(moves: Array[MoveResource]) -> void:
	var opening := _state(WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.IN_RING, WrestlerResource.MotionState.STATIONARY)
	var queue: Array[Dictionary] = [{"attacker": opening, "target": opening.duplicate(true)}]
	var visited := {_pair_key(opening, opening): true}
	var reachable_moves := {}
	var cursor := 0
	while cursor < queue.size() and queue.size() < MAX_REACHABLE_STATES:
		var node := queue[cursor]
		cursor += 1
		var attacker: Dictionary = node.attacker
		var target: Dictionary = node.target
		_add_reachable_pair(queue, visited, target, attacker)
		for action_id in MatchSetupStateRules.get_candidate_actions(attacker, target):
			if action_id == MatchSetupStateRules.TAUNT:
				continue
			var projection := MatchSetupStateRules.project_action(action_id, attacker, target)
			if bool(projection.valid):
				_add_reachable_pair(queue, visited, projection.attacker, projection.target)
		for move in moves:
			if not MatchSetupStateRules.move_matches_snapshots(move, attacker, target):
				continue
			reachable_moves[_move_key(move)] = true
			_add_reachable_pair(queue, visited, _move_result(attacker, move, true), _move_result(target, move, false))
	_check(queue.size() < MAX_REACHABLE_STATES, "state reachability graph remains bounded")
	_check(reachable_moves.size() == moves.size(), "%d/%d catalogue moves are reachable through state results and setup transitions" % [reachable_moves.size(), moves.size()])


func _move_result(current: Dictionary, move: MoveResource, attacker_result: bool) -> Dictionary:
	var result := current.duplicate(true)
	var position := move.resulting_attacker_position if attacker_result else move.resulting_target_position
	var orientation := move.resulting_attacker_orientation if attacker_result else move.resulting_target_orientation
	if position != WrestlerResource.Position.NONE:
		result.position = position
	if orientation != WrestlerResource.Orientation.NONE:
		result.orientation = orientation
	result.area = move.resolved_attacker_area(int(current.area)) if attacker_result else move.resolved_target_area(int(current.area))
	result.motion_state = move.resulting_attacker_motion_state if attacker_result else move.resulting_target_motion_state
	return result


func _add_reachable_pair(queue: Array[Dictionary], visited: Dictionary, attacker: Dictionary, target: Dictionary) -> void:
	var key := _pair_key(attacker, target)
	if visited.has(key):
		return
	visited[key] = true
	queue.append({"attacker": attacker.duplicate(true), "target": target.duplicate(true)})


func _has_path(moves: Array[MoveResource], attacker: Dictionary, target: Dictionary, expected: Array[StringName]) -> bool:
	for path_data in MatchSetupStateRules.find_followup_paths(moves, attacker, target, 2):
		var actions: Array = path_data.actions
		if actions.size() != expected.size():
			continue
		var matches := true
		for index in range(expected.size()):
			if StringName(actions[index]) != expected[index]:
				matches = false
				break
		if matches:
			return true
	return false


func _find_move(moves: Array[MoveResource], attacker_area: int, target_area: int, target_position: int) -> MoveResource:
	for move in moves:
		if (
			move.required_attacker_area_mode == MoveResource.AreaRequirementMode.SPECIFIC
			and move.required_attacker_area == attacker_area
			and move.required_target_area_mode == MoveResource.AreaRequirementMode.SPECIFIC
			and move.required_target_area == target_area
			and move.required_target_position == target_position
		):
			return move
	return null


func _state(position: int, orientation: int, area: int, motion: int) -> Dictionary:
	return {"position": position, "orientation": orientation, "area": area, "motion_state": motion}


func _pair_key(attacker: Dictionary, target: Dictionary) -> String:
	return "%d:%d:%d:%d|%d:%d:%d:%d" % [
		int(attacker.position), int(attacker.orientation), int(attacker.area), int(attacker.motion_state),
		int(target.position), int(target.orientation), int(target.area), int(target.motion_state),
	]


func _move_key(move: MoveResource) -> String:
	return move.resource_path if not move.resource_path.is_empty() else move.move_name


func _collect_moves(directory_path: String, moves: Array[MoveResource]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child_path := directory_path.path_join(entry)
			if directory.current_is_dir():
				_collect_moves(child_path, moves)
			elif entry.get_extension().to_lower() == "tres":
				var loaded := ResourceLoader.load(child_path, "", ResourceLoader.CACHE_MODE_IGNORE)
				if loaded is MoveResource:
					moves.append(loaded as MoveResource)
				else:
					_check(false, "%s loads as MoveResource" % child_path)
		entry = directory.get_next()
	directory.list_dir_end()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
		return
	_failures += 1
	push_error("FAIL: %s" % label)
