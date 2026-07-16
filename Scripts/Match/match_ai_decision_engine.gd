extends RefCounted
class_name MatchAIDecisionEngine

const KIND_MOVE := &"move"
const KIND_SETUP := &"setup"
const KIND_PIN := &"pin"

const FINISHER_MINIMUM_TIME := 600
const FINISHER_MOMENTUM := 60.0

var last_setup_intent: StringName = &""
var target_focus_body_part: int = MoveResource.MoveTargetParts.NONE
var last_successful_move_type: int = MoveResource.MoveType.NONE
var last_successful_move_impact: int = 0
var last_successful_move: MoveResource
var last_landed_finisher: bool = false
var player_crash_opportunity: bool = false
var reversal_pin_opportunity: bool = false
var big_move_followup_opportunity: bool = false
var setup_intent_decisions_remaining: int = 0
var setup_intent_pending_attempt: bool = false
var setup_cooldown_turns: int = 0
var recent_setup_actions: Array[StringName] = []
var target_focus_unavailable_turns: int = 0

var total_turns: int = 0
var move_actions_chosen: int = 0
var setup_actions_chosen: int = 0
var pin_actions_chosen: int = 0
var fallback_actions: int = 0
var no_valid_moves: int = 0
var no_valid_setups: int = 0
var total_chosen_score: float = 0.0

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func reset() -> void:
	last_setup_intent = &""
	target_focus_body_part = MoveResource.MoveTargetParts.NONE
	last_successful_move_type = MoveResource.MoveType.NONE
	last_successful_move_impact = 0
	last_successful_move = null
	last_landed_finisher = false
	player_crash_opportunity = false
	reversal_pin_opportunity = false
	big_move_followup_opportunity = false
	setup_intent_decisions_remaining = 0
	setup_intent_pending_attempt = false
	setup_cooldown_turns = 0
	recent_setup_actions.clear()
	target_focus_unavailable_turns = 0
	total_turns = 0
	move_actions_chosen = 0
	setup_actions_chosen = 0
	pin_actions_chosen = 0
	fallback_actions = 0
	no_valid_moves = 0
	no_valid_setups = 0
	total_chosen_score = 0.0


func set_seed(value: int) -> void:
	_rng.seed = value


func choose_action(
	ai_state: MatchSideState,
	target_state: MatchSideState,
	valid_moves: Array[MoveResource],
	valid_setups: Array[StringName],
	match_time_seconds: int,
) -> Dictionary:
	total_turns += 1
	if setup_cooldown_turns > 0:
		setup_cooldown_turns -= 1
	if valid_moves.is_empty():
		no_valid_moves += 1
	if valid_setups.is_empty():
		no_valid_setups += 1
	var candidates: Array[Dictionary] = []
	var best_move_score := -INF
	_update_target_focus(ai_state, target_state, valid_moves)
	for move in valid_moves:
		var target_resolution := MoveTargetResolver.resolve(move, target_focus_body_part, target_state)
		var score := _score_move(ai_state, target_state, move, match_time_seconds, target_resolution)
		best_move_score = maxf(best_move_score, score)
		candidates.append({
			"kind": KIND_MOVE,
			"score": score,
			"move": move,
			"setup_action": &"",
			"target_part": int(target_resolution.get("story_part", MoveResource.MoveTargetParts.BODY)),
			"target_resolution": target_resolution,
		})
	if (
		_taunt_positions_are_stable(ai_state, target_state)
		and match_time_seconds < ai_state.taunt_cooldown_until_seconds
	):
		ai_state.ai_taunts_rejected_cooldown += 1
		_debug_setup_rejection(SetupActionsMenu.TAUNT, "shared two-minute cooldown")
	for action_id in valid_setups:
		if action_id == SetupActionsMenu.TAUNT and _reject_ai_taunt(
			ai_state,
			target_state,
			valid_moves,
			match_time_seconds,
			best_move_score,
		):
			continue
		var score := _score_setup(ai_state, target_state, action_id, valid_moves, match_time_seconds)
		candidates.append({"kind": KIND_SETUP, "score": score, "move": null, "setup_action": action_id})
	var pin_score := _score_pin(ai_state, target_state, match_time_seconds, best_move_score)
	if pin_score > -INF:
		candidates.append({"kind": KIND_PIN, "score": pin_score, "move": null, "setup_action": &""})
	if candidates.is_empty():
		fallback_actions += 1
		_abandon_setup_intent(ai_state)
		return {}
	var matching_intent_moves := _matching_intent_moves(valid_moves)
	if not last_setup_intent.is_empty() and matching_intent_moves.is_empty():
		setup_intent_decisions_remaining -= 1
		if setup_intent_decisions_remaining <= 0:
			ai_state.setup_actions_without_followup += 1
			_abandon_setup_intent(ai_state)
	var selected: Dictionary
	if not matching_intent_moves.is_empty():
		# A successful setup gets one guaranteed chance to pay off. Weighted
		# randomness previously allowed a recovery or another setup to beat this
		# follow-up, producing top-rope/running/apron loops without an attack.
		selected = _best_intent_move_candidate(candidates, last_setup_intent)
	elif ai_state.consecutive_setup_actions >= 3:
		if not valid_moves.is_empty():
			selected = _best_move_candidate(candidates)
			selected["forced_fallback"] = true
			selected["fallback_log"] = &"commit"
		else:
			selected = _best_recovery_candidate(candidates)
			selected["forced_fallback"] = true
			selected["fallback_log"] = &"reset"
			# The counter is decremented at the beginning of a decision, so two
			# represents one complete following turn of setup suppression.
			setup_cooldown_turns = 2
		ai_state.forced_fallback_actions += 1
		_abandon_setup_intent(ai_state)
	else:
		selected = _choose_weighted_top_candidate(candidates)
	if selected.is_empty():
		fallback_actions += 1
		return {}
	var had_intent_opportunity := not matching_intent_moves.is_empty()
	var selected_move := selected.get("move") as MoveResource
	if had_intent_opportunity:
		if StringName(selected.get("kind", &"")) == KIND_MOVE and _intent_matches_move(last_setup_intent, selected_move):
			setup_intent_pending_attempt = true
		else:
			_abandon_setup_intent(ai_state)
	_record_choice(selected, ai_state)
	player_crash_opportunity = false
	reversal_pin_opportunity = false
	big_move_followup_opportunity = false
	return selected


func note_setup_executed(action_id: StringName, ai_state: MatchSideState = null) -> void:
	if action_id.is_empty():
		if ai_state != null:
			_abandon_setup_intent(ai_state)
		else:
			last_setup_intent = &""
		return
	if not _setup_creates_intent(action_id):
		_clear_setup_intent()
		return
	if not last_setup_intent.is_empty() and last_setup_intent != action_id:
		if ai_state != null:
			_abandon_setup_intent(ai_state)
		else:
			_clear_setup_intent()
	last_setup_intent = action_id
	setup_intent_decisions_remaining = 2
	setup_intent_pending_attempt = false
	if ai_state != null:
		ai_state.setup_intents_created += 1


func note_move_result(
	move: MoveResource,
	landed: bool,
	clean_success: bool,
	target_state: MatchSideState,
	ai_state: MatchSideState,
	target_resolution: Dictionary = {},
) -> void:
	if move == null:
		_abandon_setup_intent(ai_state)
		return
	if landed:
		last_successful_move_type = move.move_type
		last_successful_move_impact = move.move_impact
		last_successful_move = move
		last_landed_finisher = clean_success and move.is_finisher
		big_move_followup_opportunity = clean_success and move.move_impact >= 8
		var landed_target := int(target_resolution.get("story_part", _weakest_targeted_part(target_state, move)))
		if target_focus_body_part == MoveResource.MoveTargetParts.NONE:
			target_focus_body_part = landed_target
			ai_state.set_target_focus(landed_target, "Landed offence")
		if setup_intent_pending_attempt and not last_setup_intent.is_empty() and _intent_matches_move(last_setup_intent, move):
			ai_state.successful_setup_followups += 1
			ai_state.setup_intents_completed += 1
	else:
		last_successful_move = null
		last_landed_finisher = false
	if setup_intent_pending_attempt and (not landed or not _intent_matches_move(last_setup_intent, move)):
		ai_state.setup_intents_abandoned += 1
	_clear_setup_intent()


func note_forced_fallback(ai_state: MatchSideState) -> void:
	fallback_actions += 1
	setup_cooldown_turns = 2
	if ai_state != null:
		ai_state.forced_fallback_actions += 1
		ai_state.clear_setup_streak()
		_abandon_setup_intent(ai_state)
	else:
		_clear_setup_intent()


func note_player_high_risk_crash() -> void:
	player_crash_opportunity = true


func note_reversal_control() -> void:
	reversal_pin_opportunity = true


func debug_summary(ai_state: MatchSideState) -> String:
	var average_score := total_chosen_score / float(maxi(1, move_actions_chosen + setup_actions_chosen + pin_actions_chosen))
	return (
		"AI SUMMARY | turns=%d moves=%d setups=%d pins=%d submissions=%d finishers=%d fallbacks=%d "
		+ "avg_score=%.1f no_moves=%d no_setups=%d"
	) % [
		total_turns,
		move_actions_chosen,
		setup_actions_chosen,
		pin_actions_chosen,
		ai_state.submission_attempts,
		ai_state.finisher_attempts,
		fallback_actions,
		average_score,
		no_valid_moves,
		no_valid_setups,
	]


func _score_move(
	ai_state: MatchSideState,
	target_state: MatchSideState,
	move: MoveResource,
	match_time_seconds: int,
	target_resolution: Dictionary = {},
) -> float:
	var score := 50.0
	var high_risk := _is_high_risk(move)
	var damaged_leg_hp := minf(ai_state.left_leg_hp, ai_state.right_leg_hp)
	if high_risk:
		if damaged_leg_hp < 40.0:
			score -= 15.0
		elif damaged_leg_hp < 60.0:
			score -= 8.0
		if target_state.momentum >= ai_state.momentum + 20.0:
			score -= 6.0
	var response_chance := MatchInteractionModel.response_success_chance(
		ai_state,
		target_state,
		move,
		match_time_seconds,
		&"",
		target_resolution,
	)
	score -= response_chance * 0.08
	if move.move_impact >= 9:
		score += 20.0
	elif move.move_impact >= 7:
		score += 14.0
	elif move.move_impact >= 4:
		score += 8.0

	if ai_state.stamina < 30.0:
		if move.move_impact >= 7 or high_risk:
			score -= 18.0
		else:
			score += 8.0
	elif ai_state.stamina < 60.0:
		if move.move_impact >= 7 or high_risk:
			score -= 8.0
		else:
			score += 4.0
	if ai_state.stamina <= 0.0:
		if high_risk:
			score -= 25.0
		elif move.move_impact <= 6:
			score += 20.0

	if ai_state.fatigue >= 70.0:
		if high_risk:
			score -= 18.0
		if move.is_finisher:
			score -= 8.0
	elif ai_state.fatigue >= 40.0 and high_risk:
		score -= 8.0

	if target_resolution.is_empty():
		target_resolution = MoveTargetResolver.resolve(move, target_focus_body_part, target_state)
	var resolved_target_hp := MoveTargetResolver.target_hp(target_state, target_resolution)
	score += _damaged_resolved_target_bonus(resolved_target_hp)
	var resolved_parts: Array = target_resolution.get("parts", [])
	if _weakest_part(target_state) in resolved_parts:
		var weakest_hp := target_state.get_part_hp(_weakest_part(target_state))
		if weakest_hp < 25.0:
			score += 40.0
		elif weakest_hp < 50.0:
			score += 25.0
		else:
			score += 15.0
	if target_focus_body_part != MoveResource.MoveTargetParts.NONE and target_focus_body_part in resolved_parts:
		score += 25.0 if move.is_submission else 8.0

	if target_state.fatigue >= 80.0:
		if move.move_impact >= 7:
			score += 15.0
		if move.is_submission:
			score += 15.0
	elif target_state.fatigue >= 60.0:
		if move.move_impact >= 7:
			score += 10.0
		if move.is_submission:
			score += 8.0
	if target_state.stamina < 20.0:
		if move.is_submission or move.is_finisher:
			score += 18.0
	elif target_state.stamina < 40.0 and (move.is_submission or move.is_finisher):
		score += 10.0

	if ai_state.momentum >= 70.0:
		if move.is_finisher:
			score += 35.0
		if move.move_impact >= 7:
			score += 12.0
	elif ai_state.momentum >= 40.0:
		if move.move_impact >= 7:
			score += 8.0
		if move.is_submission:
			score += 6.0
	elif ai_state.momentum < 20.0:
		if high_risk:
			score -= 10.0
		else:
			score += 8.0

	if _is_class_compatible(ai_state.wrestler, move):
		score += 10.0
	if ai_state.last_attempted_move_matches(move):
		score -= 20.0
	var recent_eight := ai_state.recent_move_count(move, 8)
	if recent_eight >= 3:
		score -= 25.0
	elif ai_state.recent_move_count(move, 5) >= 2:
		score -= 12.0

	if high_risk:
		score -= 2.0 if _has_class(ai_state.wrestler, WrestlerResource.WrestlerClass.HIGH_FLYER) else 8.0
		if target_state.fatigue >= 70.0 or target_state.head_hp < 40.0 or target_state.body_hp < 40.0:
			score += 10.0
		if ai_state.momentum >= 70.0:
			score += 8.0
		if move.is_finisher:
			score += 15.0
		if target_state.momentum > 80.0:
			score -= 20.0

	if move.is_finisher:
		score += _finisher_bonus(ai_state, target_state, move, match_time_seconds, target_resolution)
	if move.is_submission:
		score += _submission_bonus(ai_state, target_state, move, match_time_seconds, target_resolution)
	score += _class_personality_move_bonus(ai_state.wrestler, move)
	if ai_state.consecutive_setup_actions >= 2:
		score += 80.0
	if not last_setup_intent.is_empty() and _intent_matches_move(last_setup_intent, move):
		score += 60.0
		if move.is_finisher:
			score += 30.0
		var intent_target_hp := resolved_target_hp
		if intent_target_hp < 25.0:
			score += 25.0
		elif intent_target_hp < 45.0:
			score += 18.0
		elif intent_target_hp < 70.0:
			score += 10.0
	if player_crash_opportunity:
		if move.required_target_position == WrestlerResource.Position.GROUNDED:
			score += 20.0
		if move.is_submission:
			score += 15.0
		score += 10.0
	if reversal_pin_opportunity:
		score += 14.0 if move.move_impact >= 6 else 8.0
	if big_move_followup_opportunity:
		if move.is_submission:
			score += 14.0
		elif move.move_impact >= 6:
			score += 10.0
	var escalation := MatchInteractionModel.build_late_match_profile(match_time_seconds)
	if move.is_finisher or move.is_submission or (ai_state.stamina <= 0.0 and move.move_impact <= 6):
		score += float(escalation.get("ai_finish_bonus", 0.0))
	return score


func _finisher_bonus(
	ai_state: MatchSideState,
	target_state: MatchSideState,
	move: MoveResource,
	match_time_seconds: int,
	target_resolution: Dictionary = {},
) -> float:
	var bonus := 70.0
	if target_state.fatigue >= 60.0:
		bonus += 20.0
	if target_state.stamina < 40.0:
		bonus += 20.0
	if target_state.body_hp < 50.0 or target_state.head_hp < 50.0:
		bonus += 20.0
	if match_time_seconds >= 900:
		bonus += 25.0
	elif match_time_seconds >= 600:
		bonus += 15.0
	if target_resolution.is_empty():
		target_resolution = MoveTargetResolver.resolve(move, target_focus_body_part, target_state)
	if MoveTargetResolver.target_hp(target_state, target_resolution) < 70.0:
		bonus += 20.0
	if ai_state.stamina < 15.0:
		bonus -= 25.0
	if ai_state.fatigue > 80.0:
		bonus -= 15.0
	if ai_state.recent_move_count(move, 3) > 0:
		bonus -= 20.0
	return bonus


func _submission_bonus(
	ai_state: MatchSideState,
	target_state: MatchSideState,
	move: MoveResource,
	match_time_seconds: int,
	target_resolution: Dictionary = {},
) -> float:
	if target_resolution.is_empty():
		target_resolution = MoveTargetResolver.resolve(move, target_focus_body_part, target_state)
	var target_hp := MoveTargetResolver.target_hp(target_state, target_resolution)
	var bonus := 0.0
	var has_context := (
		target_hp < 70.0
		or target_state.stamina < 40.0
		or target_state.fatigue > 60.0
		or ai_state.momentum > 50.0
		or move.is_finisher
		or match_time_seconds >= 480
	)
	if not has_context:
		bonus -= 35.0
	if target_hp >= 80.0:
		bonus -= 30.0
	elif target_hp >= 60.0:
		bonus -= 15.0
	if target_hp < 25.0:
		bonus += 35.0
	elif target_hp < 45.0:
		bonus += 20.0
	elif target_hp < 70.0:
		bonus += 10.0
	var resolved_parts: Array = target_resolution.get("parts", [])
	if _weakest_part(target_state) in resolved_parts:
		bonus += 35.0
	if move.is_finisher:
		bonus += 45.0
		if target_hp < 60.0:
			bonus += 20.0
		if target_state.stamina < 40.0:
			bonus += 20.0
		if target_state.fatigue > 60.0:
			bonus += 20.0
	var fresh_target := target_state.stamina >= 80.0 and target_state.fatigue <= 20.0
	if fresh_target:
		bonus -= 30.0 if not move.is_finisher else 12.0
	if not move.is_finisher and target_hp > 25.0:
		if match_time_seconds < 300:
			bonus -= 55.0
		elif match_time_seconds < 600:
			bonus -= 25.0
	elif match_time_seconds >= 900:
		bonus += 15.0
	return bonus


func _score_setup(
	ai_state: MatchSideState,
	target_state: MatchSideState,
	action_id: StringName,
	valid_moves: Array[MoveResource],
	match_time_seconds: int,
) -> float:
	var score := 40.0
	if MatchInteractionModel.is_contested_setup(action_id):
		var response_chance := MatchInteractionModel.response_success_chance(
			ai_state,
			target_state,
			null,
			match_time_seconds,
			action_id,
		)
		score -= response_chance * 0.08
	var projected := _project_positions(ai_state.current_position, target_state.current_position, action_id)
	var future_moves := _moves_for_positions(
		ai_state,
		int(projected.get("attacker", ai_state.current_position)),
		int(projected.get("target", target_state.current_position)),
		match_time_seconds,
	)
	var future_finishers := _count_finishers(future_moves)
	var mandatory_recovery := _is_mandatory_recovery(action_id, valid_moves)
	if future_moves.is_empty() and not mandatory_recovery:
		score -= 70.0
		ai_state.dead_end_setups_prevented += 1
		_debug_setup_rejection(action_id, "no valid move after projected positions")
	match action_id:
		SetupActionsMenu.STAND_UP:
			score += 100.0 if target_state.current_position == WrestlerResource.Position.STANDING else 70.0
		SetupActionsMenu.PICK_OPPONENT_UP:
			score += 45.0
			if future_moves.size() >= 4:
				score += 20.0
			if future_finishers > 0:
				score += 20.0
			if target_state.stamina < 40.0:
				score += 15.0
			if target_state.fatigue > 60.0:
				score += 15.0
			if _score_pin(ai_state, target_state, match_time_seconds, 0.0) >= 80.0:
				score -= 15.0
			if valid_moves.size() >= 3:
				score -= 10.0
			if player_crash_opportunity:
				score += 15.0
		SetupActionsMenu.IRISH_WHIP:
			score += 45.0
			if not future_moves.is_empty():
				score += 25.0
			if _contains_impact(future_moves, 6):
				score += 15.0
			if _has_any_class(ai_state.wrestler, [WrestlerResource.WrestlerClass.POWERHOUSE, WrestlerResource.WrestlerClass.STRIKER]):
				score += 10.0
			if ai_state.stamina < 30.0:
				score -= 10.0
		SetupActionsMenu.THROW_INTO_CORNER:
			score += 45.0
			if not future_moves.is_empty():
				score += 25.0
			if future_finishers > 0:
				score += 20.0
			if target_state.fatigue > 60.0:
				score += 10.0
			if ai_state.stamina < 30.0:
				score -= 10.0
		SetupActionsMenu.START_RUNNING:
			score += 35.0
			if not future_moves.is_empty():
				score += 25.0
			if future_finishers > 0:
				score += 15.0
			if ai_state.stamina < 30.0:
				score -= 15.0
			if ai_state.fatigue > 70.0:
				score -= 20.0
		SetupActionsMenu.CLIMB_TOP_ROPE:
			score += 35.0
			if not future_moves.is_empty():
				score += 30.0
			if future_finishers > 0:
				score += 25.0
			if ai_state.stamina < 30.0:
				score -= 20.0
			if ai_state.fatigue > 70.0:
				score -= 25.0
			if target_state.momentum > 70.0:
				score -= 15.0
		SetupActionsMenu.PREPARE_SPRINGBOARD:
			score += 35.0
			if not future_moves.is_empty():
				score += 30.0
			if future_finishers > 0:
				score += 20.0
			if ai_state.stamina < 30.0:
				score -= 20.0
			if ai_state.fatigue > 70.0:
				score -= 20.0
		SetupActionsMenu.WAKE_OPPONENT:
			score += 50.0
			if not future_moves.is_empty():
				score += 35.0
			if future_finishers > 0:
				score += 45.0
			if not valid_moves.is_empty():
				score -= 25.0
		SetupActionsMenu.RETURN_TO_RING, SetupActionsMenu.CLIMB_DOWN:
			score += 20.0
			if valid_moves.is_empty():
				score += 60.0
			if ai_state.stamina < 20.0:
				score += 40.0
			if ai_state.fatigue > 75.0:
				score += 30.0
			if not valid_moves.is_empty():
				score -= 30.0
		SetupActionsMenu.STOP_RUNNING, SetupActionsMenu.LEAVE_CORNER, SetupActionsMenu.REGAIN_FOOTING:
			score += 80.0 if valid_moves.is_empty() else 20.0
		SetupActionsMenu.GRAPPLE_OPPONENT:
			if future_moves.size() >= 4:
				score += 10.0
			if _has_class(ai_state.wrestler, WrestlerResource.WrestlerClass.TECHNICIAN):
				score += 10.0
		SetupActionsMenu.TAUNT:
			# A taunt should remain an occasional flavour/condition choice rather
			# than compete evenly with real offence.
			score -= 35.0
			if target_state.current_position == WrestlerResource.Position.GROUNDED:
				score += 30.0
			else:
				score -= 20.0
			if ai_state.stamina < 35.0:
				score += 15.0
			elif ai_state.stamina < 60.0:
				score += 8.0
			elif ai_state.stamina > 80.0:
				score -= 10.0
			if ai_state.momentum < 30.0:
				score += 8.0
			elif ai_state.momentum <= 70.0:
				score += 4.0
			elif ai_state.momentum > 85.0:
				score -= 10.0
			if ai_state.current_position == WrestlerResource.Position.APRON:
				score += 5.0
			elif ai_state.current_position == WrestlerResource.Position.TOP_ROPE:
				score += 8.0
			if ai_state.wrestler != null:
				score += clampf((ai_state.wrestler.charisma - 50.0) * 0.20, -10.0, 10.0)
				if ai_state.wrestler.wrestler_disposition == WrestlerResource.WrestlerDisposition.HEEL:
					score += 5.0
				if (
					ai_state.current_position in [WrestlerResource.Position.APRON, WrestlerResource.Position.TOP_ROPE]
					and _has_class(ai_state.wrestler, WrestlerResource.WrestlerClass.HIGH_FLYER)
				):
					score += 5.0
	var movement_setup := action_id in [
		SetupActionsMenu.START_RUNNING,
		SetupActionsMenu.CLIMB_TOP_ROPE,
		SetupActionsMenu.PREPARE_SPRINGBOARD,
	]
	var high_value_followup := _has_high_value_followup(future_moves, target_state)
	if movement_setup and ai_state.stamina < 20.0:
		var movement_penalty := -45.0
		if ai_state.stamina <= 0.0:
			movement_penalty = -80.0
		if high_value_followup:
			movement_penalty *= 0.25
		score += movement_penalty
		_debug_setup_rejection(action_id, "movement while exhausted")
	elif mandatory_recovery and ai_state.stamina < 20.0:
		score += 15.0
	elif mandatory_recovery and ai_state.stamina < 30.0:
		score += 10.0
	if ai_state.fatigue >= 70.0:
		score += 8.0
	if ai_state.momentum < 20.0:
		score += 8.0
	if ai_state.consecutive_setup_actions >= 1:
		score -= 40.0
		ai_state.setup_loop_penalties += 1
	if action_id in recent_setup_actions:
		score -= 60.0
		ai_state.setup_loop_penalties += 1
	if ai_state.consecutive_setup_actions >= 2 and not mandatory_recovery:
		score -= 75.0
		ai_state.setup_loop_penalties += 1
	if setup_cooldown_turns > 0 and not mandatory_recovery:
		score -= 100.0
	var escalation := MatchInteractionModel.build_late_match_profile(match_time_seconds)
	if movement_setup and not mandatory_recovery:
		score -= float(escalation.get("movement_setup_penalty", 0.0))
	if _has_class(ai_state.wrestler, WrestlerResource.WrestlerClass.POWERHOUSE) and action_id in [SetupActionsMenu.IRISH_WHIP, SetupActionsMenu.THROW_INTO_CORNER]:
		score += 10.0
	var targeting_threat := _incoming_targeting_context(ai_state, target_state)
	if not targeting_threat.is_empty():
		var threatened_part := int(targeting_threat.get("part", MoveResource.MoveTargetParts.NONE))
		var threatened_hp := float(targeting_threat.get("hp", 100.0))
		if action_id in [
			SetupActionsMenu.IRISH_WHIP,
			SetupActionsMenu.THROW_INTO_CORNER,
			SetupActionsMenu.GRAPPLE_OPPONENT,
		]:
			score += 8.0
		if action_id in [
			SetupActionsMenu.STOP_RUNNING,
			SetupActionsMenu.LEAVE_CORNER,
			SetupActionsMenu.REGAIN_FOOTING,
			SetupActionsMenu.RETURN_TO_RING,
			SetupActionsMenu.CLIMB_DOWN,
			SetupActionsMenu.RESET_STANCE,
		]:
			score += 10.0
		if movement_setup and threatened_part in [
			MoveResource.MoveTargetParts.LEFT_LEG,
			MoveResource.MoveTargetParts.RIGHT_LEG,
		]:
			score -= 18.0 if threatened_hp < 40.0 else 10.0
	return score


func _score_pin(
	ai_state: MatchSideState,
	target_state: MatchSideState,
	match_time_seconds: int,
	best_move_score: float,
) -> float:
	if ai_state.current_position != WrestlerResource.Position.STANDING or target_state.current_position != WrestlerResource.Position.GROUNDED:
		return -INF
	var flash_pin := reversal_pin_opportunity or _is_flash_pin_move(last_successful_move)
	var squash_pin := _is_squash_finish(ai_state, target_state)
	var protected_early_pin := not flash_pin and not squash_pin and not last_landed_finisher
	var untouched_early_target := (
		ai_state.damage_dealt <= 0.0
		and target_state.head_hp > 90.0
		and target_state.body_hp > 90.0
		and target_state.fatigue < 25.0
		and match_time_seconds < 300
		and protected_early_pin
	)
	var score := 0.0
	if untouched_early_target:
		# The cover remains legal and selectable, but is tactically terrible.
		score -= 40.0
	if last_successful_move_impact >= 6:
		score += 25.0
	if last_landed_finisher:
		score += 45.0
	if flash_pin:
		score += 65.0
	if squash_pin:
		score += 65.0
	if target_state.body_hp < 50.0:
		score += 20.0
	if target_state.head_hp < 50.0:
		score += 20.0
	if target_state.fatigue >= 80.0:
		score += 25.0
	elif target_state.fatigue >= 60.0:
		score += 15.0
	if target_state.stamina < 20.0:
		score += 25.0
	elif target_state.stamina < 40.0:
		score += 15.0
	if match_time_seconds >= 900:
		score += 20.0
	elif match_time_seconds < 300:
		score -= 20.0
	elif match_time_seconds < 600:
		score -= 10.0
	if ai_state.damage_dealt < 10.0 and protected_early_pin:
		score -= 50.0
	if match_time_seconds < 300 and protected_early_pin:
		score -= 90.0
	elif match_time_seconds < 600 and protected_early_pin:
		score -= 25.0
	if protected_early_pin and target_state.fatigue < 30.0 and target_state.body_hp > 75.0 and target_state.head_hp > 75.0:
		score -= 25.0
	if ai_state.momentum < 30.0:
		score -= 20.0
	if best_move_score > 75.0:
		score -= 15.0
	if player_crash_opportunity:
		score += 20.0
	if reversal_pin_opportunity:
		score += 45.0
	if big_move_followup_opportunity:
		score += 25.0
	if ai_state.stamina < 20.0 and (target_state.body_hp < 70.0 or target_state.head_hp < 70.0):
		score += 10.0
	var escalation := MatchInteractionModel.build_late_match_profile(match_time_seconds)
	score += float(escalation.get("ai_finish_bonus", 0.0))
	return score


func _is_flash_pin_move(move: MoveResource) -> bool:
	if move == null:
		return false
	if move.is_flash_pin:
		return true
	var normalized_name := move.move_name.to_lower().replace("’", "'")
	for term in [
		"roll-up",
		"roll up",
		"schoolboy",
		"backslide",
		"o'connor",
		"oconnor",
		"small package",
		"cradle",
		"victory roll",
		"sunset flip",
		"rolling crucifix",
		"surprise pin",
	]:
		if normalized_name.contains(term):
			return not (
				normalized_name.contains("bomb")
				or normalized_name.contains("piledriver")
				or normalized_name.contains("powerbomb")
			)
	return false


func _is_squash_finish(ai_state: MatchSideState, target_state: MatchSideState) -> bool:
	if last_landed_finisher:
		return true
	var dominant_momentum := ai_state.momentum >= 80.0 and target_state.momentum <= 20.0
	var little_return_offence := target_state.moves_landed <= 1 and target_state.damage_dealt < 20.0
	var established_offence := ai_state.moves_landed >= 3
	var defender_worn_down := (
		target_state.fatigue >= 55.0
		or target_state.fatigue >= ai_state.fatigue + 20.0
		or target_state.stamina <= 30.0
	)
	return (
		dominant_momentum
		and little_return_offence
		and established_offence
		and defender_worn_down
		and last_successful_move_impact >= 8
	)


func _matching_intent_moves(valid_moves: Array[MoveResource]) -> Array[MoveResource]:
	var matches: Array[MoveResource] = []
	if last_setup_intent.is_empty():
		return matches
	for move in valid_moves:
		if _intent_matches_move(last_setup_intent, move):
			matches.append(move)
	return matches


func _best_move_candidate(candidates: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	for candidate in candidates:
		if StringName(candidate.get("kind", &"")) != KIND_MOVE:
			continue
		if best.is_empty() or float(candidate.get("score", -INF)) > float(best.get("score", -INF)):
			best = candidate
	return best


func _best_recovery_candidate(candidates: Array[Dictionary]) -> Dictionary:
	var priority := [
		SetupActionsMenu.STAND_UP,
		SetupActionsMenu.REGAIN_FOOTING,
		SetupActionsMenu.LEAVE_CORNER,
		SetupActionsMenu.RETURN_TO_RING,
		SetupActionsMenu.CLIMB_DOWN,
		SetupActionsMenu.STOP_RUNNING,
		SetupActionsMenu.RESET_STANCE,
	]
	for wanted_action in priority:
		for candidate in candidates:
			if (
				StringName(candidate.get("kind", &"")) == KIND_SETUP
				and StringName(candidate.get("setup_action", &"")) == wanted_action
			):
				return candidate
	var best: Dictionary = {}
	for candidate in candidates:
		if StringName(candidate.get("kind", &"")) != KIND_SETUP:
			continue
		if best.is_empty() or float(candidate.get("score", -INF)) > float(best.get("score", -INF)):
			best = candidate
	return best if not best.is_empty() else candidates[0]


func _best_intent_move_candidate(candidates: Array[Dictionary], intent: StringName) -> Dictionary:
	var best: Dictionary = {}
	for candidate in candidates:
		if StringName(candidate.get("kind", &"")) != KIND_MOVE:
			continue
		var move := candidate.get("move") as MoveResource
		if move == null or not _intent_matches_move(intent, move):
			continue
		if best.is_empty() or float(candidate.get("score", -INF)) > float(best.get("score", -INF)):
			best = candidate
	return best


func _choose_weighted_top_candidate(candidates: Array[Dictionary]) -> Dictionary:
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return float(left.get("score", 0.0)) > float(right.get("score", 0.0))
	)
	var top: Array[Dictionary] = []
	for index in range(mini(5, candidates.size())):
		top.append(candidates[index])
	var lowest_score := float(top.back().get("score", 0.0))
	var weights: Array[float] = []
	var total := 0.0
	for candidate in top:
		var weight := maxf(1.0, float(candidate.get("score", 0.0)) - lowest_score + 10.0)
		weights.append(weight)
		total += weight
	var roll := _rng.randf() * total
	for index in top.size():
		roll -= weights[index]
		if roll <= 0.0:
			return top[index]
	return top[0]


func _record_choice(candidate: Dictionary, ai_state: MatchSideState) -> void:
	var kind: StringName = candidate.get("kind", &"")
	total_chosen_score += float(candidate.get("score", 0.0))
	match kind:
		KIND_MOVE:
			move_actions_chosen += 1
			recent_setup_actions.append(&"")
			if ai_state.consecutive_setup_actions > 0 and not setup_intent_pending_attempt:
				ai_state.setup_actions_without_followup += 1
			ai_state.clear_setup_streak()
		KIND_SETUP:
			setup_actions_chosen += 1
			var action_id: StringName = candidate.get("setup_action", &"")
			recent_setup_actions.append(action_id)
			ai_state.note_setup_streak()
		KIND_PIN:
			pin_actions_chosen += 1
			last_landed_finisher = false
			recent_setup_actions.append(&"")
			if ai_state.consecutive_setup_actions > 0:
				ai_state.setup_actions_without_followup += 1
			ai_state.clear_setup_streak()
	while recent_setup_actions.size() > 3:
		recent_setup_actions.pop_front()


func _project_positions(attacker_position: int, target_position: int, action_id: StringName) -> Dictionary:
	var projected_attacker := attacker_position
	var projected_target := target_position
	match action_id:
		SetupActionsMenu.STAND_UP, SetupActionsMenu.STOP_RUNNING, SetupActionsMenu.LEAVE_CORNER, SetupActionsMenu.REGAIN_FOOTING, SetupActionsMenu.CLIMB_DOWN, SetupActionsMenu.RETURN_TO_RING:
			projected_attacker = WrestlerResource.Position.STANDING
		SetupActionsMenu.START_RUNNING:
			projected_attacker = WrestlerResource.Position.RUNNING
		SetupActionsMenu.CLIMB_TOP_ROPE:
			projected_attacker = WrestlerResource.Position.TOP_ROPE
		SetupActionsMenu.PREPARE_SPRINGBOARD:
			projected_attacker = WrestlerResource.Position.APRON
		SetupActionsMenu.PICK_OPPONENT_UP, SetupActionsMenu.WAKE_OPPONENT:
			projected_target = WrestlerResource.Position.STANDING
		SetupActionsMenu.IRISH_WHIP:
			projected_target = WrestlerResource.Position.ROPE_REBOUND
		SetupActionsMenu.THROW_INTO_CORNER:
			projected_target = WrestlerResource.Position.IN_CORNER
	return {"attacker": projected_attacker, "target": projected_target}


func _reject_ai_taunt(
	ai_state: MatchSideState,
	target_state: MatchSideState,
	valid_moves: Array[MoveResource],
	match_time_seconds: int,
	best_move_score: float,
) -> bool:
	if match_time_seconds < ai_state.taunt_cooldown_until_seconds:
		return true
	if valid_moves.is_empty():
		_debug_setup_rejection(SetupActionsMenu.TAUNT, "no current move; preserve recovery/setup flow")
		return true
	for move in valid_moves:
		if move != null and move.is_finisher:
			_debug_setup_rejection(SetupActionsMenu.TAUNT, "available finisher")
			return true
	if _score_pin(ai_state, target_state, match_time_seconds, best_move_score) >= 45.0:
		_debug_setup_rejection(SetupActionsMenu.TAUNT, "credible pin available")
		return true
	var interruption_chance := MatchInteractionModel.response_success_chance(
		ai_state,
		target_state,
		null,
		match_time_seconds,
		SetupActionsMenu.TAUNT,
	)
	if target_state.current_position == WrestlerResource.Position.STANDING and interruption_chance >= 45.0:
		ai_state.ai_taunts_rejected_risk += 1
		_debug_setup_rejection(SetupActionsMenu.TAUNT, "standing opponent interruption risk %.1f" % interruption_chance)
		return true
	return false


func _taunt_positions_are_stable(ai_state: MatchSideState, target_state: MatchSideState) -> bool:
	return (
		ai_state != null
		and target_state != null
		and ai_state.current_position in [
			WrestlerResource.Position.STANDING,
			WrestlerResource.Position.APRON,
			WrestlerResource.Position.TOP_ROPE,
		]
		and target_state.current_position in [
			WrestlerResource.Position.STANDING,
			WrestlerResource.Position.GROUNDED,
		]
	)


func _is_mandatory_recovery(action_id: StringName, valid_moves: Array[MoveResource]) -> bool:
	if action_id in [
		SetupActionsMenu.STAND_UP,
		SetupActionsMenu.REGAIN_FOOTING,
		SetupActionsMenu.LEAVE_CORNER,
		SetupActionsMenu.RESET_STANCE,
	]:
		return true
	if action_id in [
		SetupActionsMenu.RETURN_TO_RING,
		SetupActionsMenu.CLIMB_DOWN,
		SetupActionsMenu.STOP_RUNNING,
	]:
		return valid_moves.is_empty()
	return false


func _has_high_value_followup(moves: Array[MoveResource], target_state: MatchSideState) -> bool:
	for move in moves:
		if move.is_finisher:
			return true
		if move.move_impact >= 6 and target_state.lowest_target_hp(move.move_target_parts) < 45.0:
			return true
	return false


func _clear_setup_intent() -> void:
	last_setup_intent = &""
	setup_intent_decisions_remaining = 0
	setup_intent_pending_attempt = false


func _abandon_setup_intent(ai_state: MatchSideState) -> void:
	if last_setup_intent.is_empty() and not setup_intent_pending_attempt:
		return
	if ai_state != null:
		ai_state.setup_intents_abandoned += 1
	_clear_setup_intent()


func _debug_setup_rejection(action_id: StringName, reason: String) -> void:
	if OS.is_debug_build():
		print("AI setup rejected/penalized: %s (%s)" % [String(action_id), reason])


func _moves_for_positions(
	ai_state: MatchSideState,
	attacker_position: int,
	target_position: int,
	match_time_seconds: int,
) -> Array[MoveResource]:
	var moves: Array[MoveResource] = []
	if ai_state.wrestler == null:
		return moves
	for move in ai_state.wrestler.move_set:
		if move == null:
			continue
		if not _position_matches(move.required_attacker_position, attacker_position):
			continue
		if not _position_matches(move.required_target_position, target_position):
			continue
		if move.is_finisher and (ai_state.momentum < FINISHER_MOMENTUM or match_time_seconds < FINISHER_MINIMUM_TIME):
			continue
		moves.append(move)
	return moves


func _update_target_focus(
	ai_state: MatchSideState,
	target_state: MatchSideState,
	valid_moves: Array[MoveResource],
) -> void:
	var available_parts: Array[int] = []
	for move in valid_moves:
		if move == null:
			continue
		for part in [
			MoveResource.MoveTargetParts.HEAD,
			MoveResource.MoveTargetParts.BODY,
			MoveResource.MoveTargetParts.LEFT_ARM,
			MoveResource.MoveTargetParts.RIGHT_ARM,
			MoveResource.MoveTargetParts.LEFT_LEG,
			MoveResource.MoveTargetParts.RIGHT_LEG,
		]:
			if MoveTargetResolver.focus_applies_to_move(move, part) and part not in available_parts:
				available_parts.append(part)
	if available_parts.is_empty():
		target_focus_unavailable_turns += 1
		if target_focus_unavailable_turns >= 2:
			target_focus_body_part = MoveResource.MoveTargetParts.NONE
			ai_state.set_target_focus(MoveResource.MoveTargetParts.NONE, "No compatible move")
		return
	var current_available := target_focus_body_part in available_parts
	if current_available:
		target_focus_unavailable_turns = 0
	else:
		target_focus_unavailable_turns += 1
	var preferred := int(available_parts[0])
	var preferred_score := INF
	for part in available_parts:
		var score := target_state.get_part_hp(part)
		if ai_state.wrestler != null:
			if _has_class(ai_state.wrestler, WrestlerResource.WrestlerClass.POWERHOUSE) and part in [
				MoveResource.MoveTargetParts.HEAD,
				MoveResource.MoveTargetParts.BODY,
			]:
				score -= 6.0
			if _has_class(ai_state.wrestler, WrestlerResource.WrestlerClass.TECHNICIAN) and part in [
				MoveResource.MoveTargetParts.LEFT_ARM,
				MoveResource.MoveTargetParts.RIGHT_ARM,
				MoveResource.MoveTargetParts.LEFT_LEG,
				MoveResource.MoveTargetParts.RIGHT_LEG,
			]:
				score -= 6.0
			if _has_class(ai_state.wrestler, WrestlerResource.WrestlerClass.STRIKER):
				if part == MoveResource.MoveTargetParts.HEAD:
					score -= 6.0
				elif MoveTargetResolver.is_limb_focus(part):
					score -= 3.0
			if _has_class(ai_state.wrestler, WrestlerResource.WrestlerClass.HIGH_FLYER):
				score += 3.0
		if score < preferred_score:
			preferred_score = score
			preferred = part
	var should_switch := not current_available and target_focus_unavailable_turns >= 2
	if target_focus_body_part == MoveResource.MoveTargetParts.NONE:
		should_switch = true
	elif current_available:
		var current_hp := target_state.get_part_hp(target_focus_body_part)
		should_switch = target_state.get_part_hp(preferred) <= current_hp - 15.0
	if should_switch:
		target_focus_body_part = preferred
		target_focus_unavailable_turns = 0
		ai_state.set_target_focus(preferred, "Weak compatible limb")


func _damaged_resolved_target_bonus(target_hp: float) -> float:
	if target_hp < 25.0:
		return 24.0
	if target_hp < 45.0:
		return 15.0
	if target_hp < 70.0:
		return 8.0
	return 0.0


func _damaged_part_bonus(target_state: MatchSideState, move: MoveResource) -> float:
	var bonus := 0.0
	var parts: Array = move.move_target_parts
	if parts.is_empty():
		parts = [MoveResource.MoveTargetParts.BODY]
	for part in parts:
		var hp := target_state.get_part_hp(int(part))
		if hp < 25.0:
			bonus += 24.0
		elif hp < 45.0:
			bonus += 15.0
		elif hp < 70.0:
			bonus += 8.0
	return minf(30.0, bonus)


func _weakest_part(state: MatchSideState) -> int:
	var parts := [
		MoveResource.MoveTargetParts.HEAD,
		MoveResource.MoveTargetParts.BODY,
		MoveResource.MoveTargetParts.LEFT_ARM,
		MoveResource.MoveTargetParts.RIGHT_ARM,
		MoveResource.MoveTargetParts.LEFT_LEG,
		MoveResource.MoveTargetParts.RIGHT_LEG,
	]
	var weakest := int(parts[0])
	for part in parts:
		if state.get_part_hp(int(part)) < state.get_part_hp(weakest):
			weakest = int(part)
	return weakest


func _incoming_targeting_context(
	ai_state: MatchSideState,
	opponent_state: MatchSideState,
) -> Dictionary:
	if ai_state == null or opponent_state == null:
		return {}
	var part := opponent_state.most_targeted_part()
	if part == MoveResource.MoveTargetParts.NONE:
		return {}
	var total_attacks := int(opponent_state.target_attack_counts.get(part, 0))
	var recent_attacks := opponent_state.recent_target_part_count(part, 5)
	var hp := ai_state.get_part_hp(part)
	if total_attacks < 3 or recent_attacks < 2 or hp > 60.0:
		return {}
	return {
		"part": part,
		"hp": hp,
		"total_attacks": total_attacks,
		"recent_attacks": recent_attacks,
	}


func _weakest_targeted_part(state: MatchSideState, move: MoveResource) -> int:
	if move.move_target_parts.is_empty():
		return MoveResource.MoveTargetParts.BODY
	var weakest := int(move.move_target_parts[0])
	for part in move.move_target_parts:
		if state.get_part_hp(int(part)) < state.get_part_hp(weakest):
			weakest = int(part)
	return weakest


func _move_targets_part(move: MoveResource, part: int) -> bool:
	if move.move_target_parts.is_empty():
		return part == MoveResource.MoveTargetParts.BODY
	return part in move.move_target_parts


func _intent_matches_move(intent: StringName, move: MoveResource) -> bool:
	match intent:
		SetupActionsMenu.IRISH_WHIP:
			return move.move_type == MoveResource.MoveType.ROPE_REBOUND
		SetupActionsMenu.THROW_INTO_CORNER:
			return move.move_type == MoveResource.MoveType.CORNER
		SetupActionsMenu.START_RUNNING:
			return move.move_type == MoveResource.MoveType.RUNNING
		SetupActionsMenu.CLIMB_TOP_ROPE:
			return move.move_type in [MoveResource.MoveType.DIVING_STANDING, MoveResource.MoveType.DIVING_GROUNDED]
		SetupActionsMenu.WAKE_OPPONENT:
			return move.move_type == MoveResource.MoveType.DIVING_STANDING
		SetupActionsMenu.PREPARE_SPRINGBOARD:
			return move.move_type == MoveResource.MoveType.SPRINGBOARD
		SetupActionsMenu.PICK_OPPONENT_UP, SetupActionsMenu.GRAPPLE_OPPONENT:
			return move.move_type in [MoveResource.MoveType.STANDING_FRONT, MoveResource.MoveType.STANDING_BEHIND]
	return false


func _setup_creates_intent(action_id: StringName) -> bool:
	return action_id in [
		SetupActionsMenu.PICK_OPPONENT_UP,
		SetupActionsMenu.GRAPPLE_OPPONENT,
		SetupActionsMenu.IRISH_WHIP,
		SetupActionsMenu.THROW_INTO_CORNER,
		SetupActionsMenu.START_RUNNING,
		SetupActionsMenu.CLIMB_TOP_ROPE,
		SetupActionsMenu.PREPARE_SPRINGBOARD,
		SetupActionsMenu.WAKE_OPPONENT,
	]


func _class_personality_move_bonus(wrestler: WrestlerResource, move: MoveResource) -> float:
	if wrestler == null:
		return 0.0
	var bonus := 0.0
	if _has_class(wrestler, WrestlerResource.WrestlerClass.POWERHOUSE):
		if move.move_impact >= 6:
			bonus += 10.0
		if _is_high_risk(move) and not _is_class_compatible(wrestler, move):
			bonus -= 10.0
	if _has_class(wrestler, WrestlerResource.WrestlerClass.TECHNICIAN):
		if move.is_submission:
			bonus += 12.0
		if _is_high_risk(move):
			bonus -= 8.0
	if _has_class(wrestler, WrestlerResource.WrestlerClass.HIGH_FLYER) and move.move_type in [
		MoveResource.MoveType.RUNNING,
		MoveResource.MoveType.SPRINGBOARD,
		MoveResource.MoveType.DIVING_STANDING,
		MoveResource.MoveType.DIVING_GROUNDED,
	]:
		bonus += 15.0
	if _has_class(wrestler, WrestlerResource.WrestlerClass.STRIKER):
		if move.is_strike:
			bonus += 12.0
			if move.move_type == MoveResource.MoveType.RUNNING:
				bonus += 8.0
		if _move_targets_part(move, MoveResource.MoveTargetParts.HEAD) or _targets_limb(move):
			bonus += 5.0
	return bonus


func _targets_limb(move: MoveResource) -> bool:
	for part in move.move_target_parts:
		if part in [
			MoveResource.MoveTargetParts.LEFT_ARM,
			MoveResource.MoveTargetParts.RIGHT_ARM,
			MoveResource.MoveTargetParts.LEFT_LEG,
			MoveResource.MoveTargetParts.RIGHT_LEG,
		]:
			return true
	return false


func _is_class_compatible(wrestler: WrestlerResource, move: MoveResource) -> bool:
	if wrestler == null:
		return false
	for wrestler_class in wrestler.wrestler_class:
		if wrestler_class in move.class_preferrence:
			return true
	return false


func _has_class(wrestler: WrestlerResource, wrestler_class: int) -> bool:
	return wrestler != null and wrestler_class in wrestler.wrestler_class


func _has_any_class(wrestler: WrestlerResource, classes: Array) -> bool:
	if wrestler == null:
		return false
	for wrestler_class in classes:
		if wrestler_class in wrestler.wrestler_class:
			return true
	return false


func _contains_impact(moves: Array[MoveResource], minimum_impact: int) -> bool:
	for move in moves:
		if move.move_impact >= minimum_impact:
			return true
	return false


func _count_finishers(moves: Array[MoveResource]) -> int:
	var count := 0
	for move in moves:
		if move.is_finisher:
			count += 1
	return count


func _position_matches(required: int, actual: int) -> bool:
	return required == WrestlerResource.Position.NONE or required == actual


func _is_high_risk(move: MoveResource) -> bool:
	return MatchInteractionModel.is_high_risk_move(move)
