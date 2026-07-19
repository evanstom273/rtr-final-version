extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	var attacker := WrestlerResource.new()
	var target := WrestlerResource.new()
	var move := MoveResource.new()

	_check(move.areas_match(WrestlerResource.Area.IN_RING, WrestlerResource.Area.IN_RING), "default ANY/SAME area requirements")
	_check(not move.areas_match(WrestlerResource.Area.IN_RING, WrestlerResource.Area.ROPES), "SAME_AS_OTHER rejects different areas")
	move.required_attacker_area_mode = MoveResource.AreaRequirementMode.SHARED_FLAT_AREA
	_check(move.areas_match(WrestlerResource.Area.IN_RING, WrestlerResource.Area.IN_RING), "shared-flat requirements accept the ring")
	_check(move.areas_match(WrestlerResource.Area.OUTSIDE, WrestlerResource.Area.OUTSIDE), "shared-flat requirements accept ringside")
	_check(move.areas_match(WrestlerResource.Area.RAMP, WrestlerResource.Area.RAMP), "shared-flat requirements accept the ramp")
	_check(not move.areas_match(WrestlerResource.Area.APRON, WrestlerResource.Area.APRON), "shared-flat requirements reject the apron")
	_check(not move.areas_match(WrestlerResource.Area.TOP_ROPE, WrestlerResource.Area.TOP_ROPE), "shared-flat requirements reject the top rope")
	move.required_attacker_area_mode = MoveResource.AreaRequirementMode.ANY
	move.required_target_area_mode = MoveResource.AreaRequirementMode.SPECIFIC
	move.required_target_area = WrestlerResource.Area.ROPES
	_check(move.areas_match(WrestlerResource.Area.IN_RING, WrestlerResource.Area.ROPES), "SPECIFIC target area")

	move.resulting_attacker_area_mode = MoveResource.AreaResultMode.UNCHANGED
	_check(move.resolved_attacker_area(WrestlerResource.Area.APRON) == WrestlerResource.Area.APRON, "UNCHANGED attacker area result")
	move.resulting_attacker_area_mode = MoveResource.AreaResultMode.SPECIFIC
	move.resulting_attacker_area = WrestlerResource.Area.IN_RING
	_check(move.resolved_attacker_area(WrestlerResource.Area.APRON) == WrestlerResource.Area.IN_RING, "SPECIFIC attacker area result")

	attacker.position = WrestlerResource.Position.STANDING
	attacker.orientation = WrestlerResource.Orientation.FRONT
	attacker.area = WrestlerResource.Area.IN_RING
	attacker.motion_state = WrestlerResource.MotionState.STATIONARY
	target.position = WrestlerResource.Position.STANDING
	target.orientation = WrestlerResource.Orientation.FRONT
	target.area = WrestlerResource.Area.IN_RING
	target.motion_state = WrestlerResource.MotionState.STATIONARY
	var standing_actions := SetupActionsMenu.get_valid_actions(attacker, target)
	_check(SetupActionsMenu.START_RUNNING in standing_actions, "standing wrestler can start running")
	_check(SetupActionsMenu.IRISH_WHIP in standing_actions, "standing opponent can be Irish whipped")

	attacker.area = WrestlerResource.Area.APRON
	var apron_actions := SetupActionsMenu.get_valid_actions(attacker, target)
	_check(SetupActionsMenu.RETURN_TO_RING in apron_actions, "apron state has return recovery")
	attacker.area = WrestlerResource.Area.TOP_ROPE
	attacker.position = WrestlerResource.Position.PERCHED
	var top_rope_actions := SetupActionsMenu.get_valid_actions(attacker, target)
	_check(SetupActionsMenu.CLIMB_DOWN in top_rope_actions, "top-rope perched state has climb-down recovery")

	move.move_type = MoveResource.MoveType.STRIKE
	_check(MatchInteractionModel.get_interaction_type_for_move(move) == MatchInteractionModel.InteractionType.TIMING_STRIKE, "strike type uses timing interaction")
	move.move_type = MoveResource.MoveType.AERIAL
	_check(MatchInteractionModel.get_interaction_type_for_move(move) == MatchInteractionModel.InteractionType.TIMING_AERIAL, "aerial type uses timing interaction")
	move.move_type = MoveResource.MoveType.SUBMISSION
	_check(MatchInteractionModel.get_interaction_type_for_move(move) == MatchInteractionModel.InteractionType.SUBMISSION_LOCK_IN, "submission type uses lock-in interaction")
	_audit_standing_front_strikes()
	_audit_move_catalogue_v2()

	if _failures == 0:
		print("SCHEMA_BRIDGE_REGRESSION: PASS")
	else:
		push_error("SCHEMA_BRIDGE_REGRESSION: %d failure(s)" % _failures)
	quit(_failures)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
		return
	_failures += 1
	push_error("FAIL: %s" % label)


func _audit_standing_front_strikes() -> void:
	var paths: Array[String] = []
	_collect_tres_paths("res://Moves/Strikes/Standing_Front", paths)
	_check(paths.size() == 60, "standing-front strike batch contains 60 resources")
	var weak_count := 0
	var medium_count := 0
	var heavy_count := 0
	var choose_leg_count := 0
	var valid_contract_count := 0
	for path in paths:
		var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if not loaded is MoveResource:
			_check(false, "%s loads as MoveResource" % path)
			continue
		var batch_move := loaded as MoveResource
		match batch_move.strike_weight:
			MoveResource.StrikeWeight.STRIKE_WEAK:
				weak_count += 1
				_check(batch_move.move_impact == 2, "%s weak impact is 2" % batch_move.move_name)
			MoveResource.StrikeWeight.STRIKE_MEDIUM:
				medium_count += 1
				_check(batch_move.move_impact == 5, "%s medium impact is 5" % batch_move.move_name)
			MoveResource.StrikeWeight.STRIKE_HEAVY:
				heavy_count += 1
				_check(batch_move.move_impact == 8, "%s heavy impact is 8" % batch_move.move_name)
		if batch_move.targeting_mode == MoveResource.TargetingMode.CHOOSE_LEG:
			choose_leg_count += 1
			_check(
				batch_move.default_side_target == MoveResource.MoveTargetParts.LEFT_LEG
				and MoveResource.MoveTargetParts.LEFT_LEG in batch_move.move_target_parts
				and MoveResource.MoveTargetParts.RIGHT_LEG in batch_move.move_target_parts,
				"%s has coherent selectable-leg targeting" % batch_move.move_name,
			)
		var contract_valid := (
			batch_move.move_type == MoveResource.MoveType.STRIKE
			and batch_move.is_strike
			and not batch_move.is_submission
			and not batch_move.is_finisher
			and batch_move.required_attacker_position == WrestlerResource.Position.STANDING
			and batch_move.required_attacker_orientation == WrestlerResource.Orientation.FRONT
			and batch_move.required_attacker_area_mode == MoveResource.AreaRequirementMode.ANY
			and batch_move.required_attacker_motion_state == WrestlerResource.MotionState.STATIONARY
			and batch_move.required_target_position == WrestlerResource.Position.STANDING
			and batch_move.required_target_orientation == WrestlerResource.Orientation.FRONT
			and batch_move.required_target_area_mode == MoveResource.AreaRequirementMode.SAME_AS_OTHER
			and batch_move.required_target_motion_state == WrestlerResource.MotionState.STATIONARY
			and batch_move.resulting_attacker_area_mode == MoveResource.AreaResultMode.UNCHANGED
			and batch_move.resulting_target_area_mode == MoveResource.AreaResultMode.UNCHANGED
			and MatchInteractionModel.get_interaction_type_for_move(batch_move) == MatchInteractionModel.InteractionType.TIMING_STRIKE
		)
		if contract_valid:
			valid_contract_count += 1
	_check(weak_count == 20, "standing-front batch has 20 weak strikes")
	_check(medium_count == 20, "standing-front batch has 20 medium strikes")
	_check(heavy_count == 20, "standing-front batch has 20 heavy strikes")
	_check(choose_leg_count == 5, "standing-front batch has five selectable-leg strikes")
	_check(valid_contract_count == 60, "all standing-front strikes satisfy the shared state contract")


func _audit_move_catalogue_v2() -> void:
	var paths: Array[String] = []
	for category in ["Aerial", "Grapple", "Pinning_Move", "Running", "Springboard", "Submission"]:
		_collect_tres_paths("res://Moves".path_join(category), paths)
	_check(paths.size() == 596, "move catalogue v2 contains 596 non-strike resources")
	var type_counts := {}
	var shared_flat_count := 0
	var pinning_combination_count := 0
	var flash_pin_count := 0
	var finisher_count := 0
	var submission_count := 0
	var strike_flag_count := 0
	var valid_contract_count := 0
	for path in paths:
		var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if not loaded is MoveResource:
			_check(false, "%s loads as MoveResource" % path)
			continue
		var batch_move := loaded as MoveResource
		type_counts[batch_move.move_type] = int(type_counts.get(batch_move.move_type, 0)) + 1
		if (
			batch_move.required_attacker_area_mode == MoveResource.AreaRequirementMode.SHARED_FLAT_AREA
			or batch_move.required_target_area_mode == MoveResource.AreaRequirementMode.SHARED_FLAT_AREA
		):
			shared_flat_count += 1
			_check(batch_move.areas_match(WrestlerResource.Area.IN_RING, WrestlerResource.Area.IN_RING), "%s works in a shared ring area" % batch_move.move_name)
			_check(not batch_move.areas_match(WrestlerResource.Area.APRON, WrestlerResource.Area.APRON), "%s cannot become an apron grapple" % batch_move.move_name)
		if batch_move.is_pinning_combination:
			pinning_combination_count += 1
		if batch_move.is_flash_pin:
			flash_pin_count += 1
		if batch_move.is_finisher:
			finisher_count += 1
		if batch_move.is_submission:
			submission_count += 1
		if batch_move.is_strike:
			strike_flag_count += 1
		var contract_valid := (
			not batch_move.move_name.strip_edges().is_empty()
			and not batch_move.move_target_parts.is_empty()
			and batch_move.move_impact >= 1
			and batch_move.move_impact <= 10
			and batch_move.move_type in [
				MoveResource.MoveType.AERIAL,
				MoveResource.MoveType.GRAPPLE,
				MoveResource.MoveType.PINNING_MOVE,
				MoveResource.MoveType.RUNNING,
				MoveResource.MoveType.SPRINGBOARD,
				MoveResource.MoveType.SUBMISSION,
			]
		)
		if contract_valid:
			valid_contract_count += 1
	_check(int(type_counts.get(MoveResource.MoveType.AERIAL, 0)) == 62, "catalogue has 62 aerial moves")
	_check(int(type_counts.get(MoveResource.MoveType.GRAPPLE, 0)) == 246, "catalogue has 246 grapple moves")
	_check(int(type_counts.get(MoveResource.MoveType.PINNING_MOVE, 0)) == 40, "catalogue has 40 pinning moves")
	_check(int(type_counts.get(MoveResource.MoveType.RUNNING, 0)) == 113, "catalogue has 113 running moves")
	_check(int(type_counts.get(MoveResource.MoveType.SPRINGBOARD, 0)) == 55, "catalogue has 55 springboard moves")
	_check(int(type_counts.get(MoveResource.MoveType.SUBMISSION, 0)) == 80, "catalogue has 80 submission moves")
	_check(shared_flat_count == 385, "385 moves use shared-flat area requirements")
	_check(pinning_combination_count == 59, "59 moves preserve pinning-combination behaviour")
	_check(flash_pin_count == 40, "40 pure pinning moves retain flash-pin behaviour")
	_check(finisher_count == 58, "catalogue contains 58 finishers")
	_check(submission_count == 80, "all 80 submissions retain their submission flag")
	_check(strike_flag_count == 80, "80 non-standing-strike moves retain strike interaction flags")
	_check(valid_contract_count == 596, "all catalogue v2 resources satisfy the revised data contract")


func _collect_tres_paths(directory_path: String, results: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child_path := directory_path.path_join(entry)
			if directory.current_is_dir():
				_collect_tres_paths(child_path, results)
			elif entry.get_extension().to_lower() == "tres":
				results.append(child_path)
		entry = directory.get_next()
	directory.list_dir_end()
