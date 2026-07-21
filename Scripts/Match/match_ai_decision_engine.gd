extends RefCounted
class_name MatchAIDecisionEngine

const KIND_MOVE := &"move"
const KIND_SETUP := &"setup"
const KIND_PIN := &"pin"

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
var planned_setup_actions: Array[StringName] = []
var planned_followup_move_key: String = ""
var setup_cooldown_turns: int = 0
var recent_setup_actions: Array[StringName] = []
var target_focus_unavailable_turns: int = 0
var last_decision_diagnostics: Dictionary = {}
var _decision_rejections: Array[Dictionary] = []

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
	planned_setup_actions.clear()
	planned_followup_move_key = ""
	setup_cooldown_turns = 0
	recent_setup_actions.clear()
	target_focus_unavailable_turns = 0
	last_decision_diagnostics.clear()
	_decision_rejections.clear()
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


func has_executable_candidate(
	valid_moves: Array[MoveResource],
	valid_setups: Array[StringName],
	can_pin: bool,
) -> bool:
	# Intentionally non-mutating: the watchdog must be able to inspect flow
	# without consuming intent lifetimes, RNG values, or diagnostic counters.
	for move in valid_moves:
		if move != null:
			return true
	for action_id in valid_setups:
		if not action_id.is_empty():
			return true
	return can_pin


func choose_action(
	ai_state: MatchSideState,
	target_state: MatchSideState,
	valid_moves: Array[MoveResource],
	valid_setups: Array[StringName],
	match_time_seconds: int,
) -> Dictionary:
	total_turns += 1
	_decision_rejections.clear()
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
		_debug_setup_rejection(MatchSetupStateRules.TAUNT, "shared two-minute cooldown")
	for action_id in valid_setups:
		# Once a setup has produced legal offence, use that offence instead of
		# immediately undoing the state through climb-down/return/reset recovery.
		# Recovery remains available whenever the position has no legal move.
		if not valid_moves.is_empty() and MatchSetupStateRules.is_recovery(action_id):
			continue
		if action_id == MatchSetupStateRules.TAUNT and _reject_ai_taunt(
			ai_state,
			target_state,
			valid_moves,
			match_time_seconds,
			best_move_score,
		):
			continue
		var setup_plan := _best_setup_plan(ai_state, target_state, action_id, match_time_seconds)
		var score := _score_setup(ai_state, target_state, action_id, valid_moves, match_time_seconds, setup_plan)
		candidates.append({
			"kind": KIND_SETUP,
			"score": score,
			"move": null,
			"setup_action": action_id,
			"setup_path": setup_plan.get("actions", []),
			"planned_move": setup_plan.get("move"),
		})
	var pin_score := _score_pin(ai_state, target_state, match_time_seconds, best_move_score)
	if pin_score > -INF:
		candidates.append({"kind": KIND_PIN, "score": pin_score, "move": null, "setup_action": &""})
	if candidates.is_empty():
		fallback_actions += 1
		_abandon_setup_intent(ai_state)
		last_decision_diagnostics = {
			"turn": total_turns,
			"selected": {},
			"top_candidates": [],
			"rejections": _decision_rejections.duplicate(true),
		}
		return {}
	var matching_intent_moves := _matching_intent_moves(valid_moves)
	if not last_setup_intent.is_empty() and matching_intent_moves.is_empty():
		setup_intent_decisions_remaining -= 1
		if setup_intent_decisions_remaining <= 0:
			ai_state.setup_actions_without_followup += 1
			_abandon_setup_intent(ai_state)
	var selected: Dictionary
	var ready_special_move := _best_ready_special_move_candidate(candidates, ai_state)
	var ready_special_setup: Dictionary = {}
	if ready_special_move.is_empty():
		ready_special_setup = _best_ready_special_setup_candidate(candidates, ai_state)
	if not ready_special_move.is_empty():
		# A ready special is a state transition, not an ordinary weighted option.
		# If it is legal now, commit to it before pins, recovery, or routine offence.
		selected = ready_special_move
		selected["special_priority"] = true
	elif not ready_special_setup.is_empty():
		# No special is legal in the current state, so begin the shortest authored
		# setup route whose projected follow-up is the ready signature/finisher.
		_clear_setup_intent()
		selected = ready_special_setup
		selected["special_priority"] = true
	elif not planned_setup_actions.is_empty():
		selected = _candidate_for_setup_action(candidates, planned_setup_actions[0])
		if selected.is_empty():
			_abandon_setup_intent(ai_state)
	elif not matching_intent_moves.is_empty():
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
	if (
		StringName(selected.get("kind", &"")) == KIND_SETUP
		and StringName(selected.get("setup_action", &"")) != MatchSetupStateRules.CATCH_BREATH
		and _selected_setup_had_loop_penalty(ai_state, StringName(selected.get("setup_action", &"")))
	):
		ai_state.setup_loop_penalties += 1
	if StringName(selected.get("kind", &"")) == KIND_SETUP:
		var selected_path: Array = selected.get("setup_path", [])
		var selected_action := StringName(selected.get("setup_action", &""))
		if not planned_setup_actions.is_empty() and planned_setup_actions[0] == selected_action:
			planned_setup_actions.pop_front()
		elif planned_setup_actions.is_empty() and not selected_path.is_empty():
			planned_setup_actions.clear()
			for index in range(1, selected_path.size()):
				planned_setup_actions.append(StringName(selected_path[index]))
			planned_followup_move_key = _move_key(selected.get("planned_move") as MoveResource)
	var had_intent_opportunity := not matching_intent_moves.is_empty()
	var selected_move := selected.get("move") as MoveResource
	if had_intent_opportunity:
		if StringName(selected.get("kind", &"")) == KIND_MOVE and _intent_matches_move(last_setup_intent, selected_move):
			setup_intent_pending_attempt = true
		else:
			_abandon_setup_intent(ai_state)
	_record_choice(selected, ai_state)
	last_decision_diagnostics = {
		"turn": total_turns,
		"selected": _candidate_diagnostic(selected),
		"top_candidates": _top_candidate_diagnostics(candidates),
		"rejections": _decision_rejections.duplicate(true),
	}
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
	if (
		not last_setup_intent.is_empty()
		and last_setup_intent != action_id
		and planned_followup_move_key.is_empty()
	):
		if ai_state != null:
			_abandon_setup_intent(ai_state)
		else:
			_clear_setup_intent()
	last_setup_intent = action_id
	setup_intent_decisions_remaining = maxi(2, planned_setup_actions.size() + 1)
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


func note_mandatory_recovery(ai_state: MatchSideState) -> void:
	if ai_state != null:
		ai_state.mandatory_recovery_actions += 1
		ai_state.clear_setup_streak()
	_abandon_setup_intent(ai_state)


func has_credible_finish(
	ai_state: MatchSideState,
	target_state: MatchSideState,
	valid_moves: Array[MoveResource],
	can_pin: bool,
	match_time_seconds: int,
) -> bool:
	if ai_state == null or target_state == null:
		return false
	# Readiness must prevent urgent Catch Breath and optional object branches from
	# pre-empting the setup search for an earned signature or stocked finisher.
	if ai_state.signature_ready or ai_state.finisher_stock > 0:
		return true
	for move in valid_moves:
		if move == null:
			continue
		if move.is_finisher:
			return true
		if move.is_submission:
			var resolution := MoveTargetResolver.resolve(move, target_focus_body_part, target_state)
			var target_hp := MoveTargetResolver.target_hp(target_state, resolution)
			if (
				target_hp < 45.0
				or target_state.stamina_percent() < 30.0
				or target_state.fatigue >= 70.0
				or match_time_seconds >= 900
			):
				return true
	if not can_pin:
		return false
	return (
		ai_state.last_move_was_finisher
		or target_state.total_hp() <= 390.0
		or target_state.stamina_percent() < 30.0
		or target_state.fatigue >= 70.0
		or match_time_seconds >= 900
	)


func has_ready_special_continuation(
	ai_state: MatchSideState,
	target_state: MatchSideState,
	valid_moves: Array[MoveResource],
	valid_setups: Array[StringName],
	max_setup_steps: int = 2,
) -> bool:
	if ai_state == null or target_state == null:
		return false
	for move in valid_moves:
		if _ready_special_rank(ai_state, move) > 0:
			return true
	if valid_setups.is_empty():
		return false
	for path_data in MatchSetupStateRules.find_followup_paths(
		ai_state.all_assigned_moves(),
		ai_state.snapshot(),
		target_state.snapshot(),
		max_setup_steps,
	):
		var move := path_data.get("move") as MoveResource
		var path: Array = path_data.get("actions", [])
		if (
			move == null
			or path.is_empty()
			or not ai_state.can_use_move(move)
			or _ready_special_rank(ai_state, move) <= 0
		):
			continue
		if StringName(path[0]) in valid_setups:
			return true
	return false


func has_reachable_offensive_setup(
	ai_state: MatchSideState,
	target_state: MatchSideState,
	valid_setups: Array[StringName],
	max_setup_steps: int = 2,
) -> bool:
	if ai_state == null or target_state == null or valid_setups.is_empty():
		return false
	for path_data in MatchSetupStateRules.find_followup_paths(
		ai_state.all_assigned_moves(),
		ai_state.snapshot(),
		target_state.snapshot(),
		max_setup_steps,
	):
		var move := path_data.get("move") as MoveResource
		var path: Array = path_data.get("actions", [])
		if move == null or path.is_empty() or not ai_state.can_use_move(move):
			continue
		var first_action := StringName(path[0])
		if (
			first_action in valid_setups
			and not MatchSetupStateRules.is_recovery(first_action)
			and first_action not in [MatchSetupStateRules.TAUNT, MatchSetupStateRules.CATCH_BREATH]
		):
			return true
	return false


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
	var exhaustion_profile := MatchExhaustionModel.profile(
		ai_state,
		move,
		ai_state.is_signature_move(move),
		ai_state.current_area == WrestlerResource.Area.LADDER,
	)
	var demand := int(exhaustion_profile.get("demand", MatchExhaustionModel.Demand.STANDARD))
	var execution_profile := MatchInteractionModel.build_execution_profile(
		ai_state,
		move,
		MatchInteractionModel.get_interaction_type_for_move(move),
	)
	var execution_chance := float(execution_profile.get("ai_success_chance", 50.0))
	score += (execution_chance - 70.0) * 0.22
	score -= float(exhaustion_profile.get("execution_penalty", 0.0)) * 0.65
	score -= (float(exhaustion_profile.get("stamina_cost_multiplier", 1.0)) - 1.0) * 24.0
	var exhaustion := float(exhaustion_profile.get("combined_exhaustion", 0.0))
	if demand == MatchExhaustionModel.Demand.BASIC:
		score += exhaustion * 12.0
	elif demand == MatchExhaustionModel.Demand.EXPLOSIVE:
		score -= exhaustion * 30.0
	if move.move_impact >= 9:
		score += 20.0
	elif move.move_impact >= 7:
		score += 14.0
	elif move.move_impact >= 4:
		score += 8.0

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
	if target_state.stamina_percent() < 20.0:
		if move.is_submission or move.is_finisher:
			score += 18.0
	elif target_state.stamina_percent() < 40.0 and (move.is_submission or move.is_finisher):
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
	elif ai_state.is_signature_move(move):
		score += 45.0 if ai_state.finisher_stock < MatchSideState.MAX_FINISHER_STOCK else 8.0
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
	if move.is_finisher or move.is_submission or (
		MatchExhaustionModel.exhaustion_band(ai_state) == MatchExhaustionModel.ExhaustionBand.SPENT
		and MatchExhaustionModel.move_demand(move) == MatchExhaustionModel.Demand.BASIC
	):
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
	if target_state.stamina_percent() < 40.0:
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
		or target_state.stamina_percent() < 40.0
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
		if target_state.stamina_percent() < 40.0:
			bonus += 20.0
		if target_state.fatigue > 60.0:
			bonus += 20.0
	var fresh_target := target_state.stamina_percent() >= 80.0 and target_state.fatigue <= 20.0
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
	setup_plan: Dictionary = {},
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
	var projected := _project_states(ai_state, target_state, action_id)
	var future_moves := _moves_for_states(
		ai_state,
		projected.get("attacker", ai_state.snapshot()),
		projected.get("target", target_state.snapshot()),
		match_time_seconds,
	)
	var planned_move := setup_plan.get("move") as MoveResource
	if future_moves.is_empty() and planned_move != null:
		future_moves.append(planned_move)
	var future_finishers := _count_finishers(future_moves)
	var mandatory_recovery := _is_mandatory_recovery(action_id, valid_moves)
	if future_moves.is_empty() and not mandatory_recovery and action_id not in [MatchSetupStateRules.TAUNT, MatchSetupStateRules.CATCH_BREATH]:
		score -= 70.0
		ai_state.dead_end_setups_prevented += 1
		_debug_setup_rejection(action_id, "no valid move after projected positions")
	match action_id:
		MatchSetupStateRules.STAND_UP:
			score += 100.0 if target_state.current_position == WrestlerResource.Position.STANDING else 70.0
		MatchSetupStateRules.PICK_OPPONENT_UP:
			score += 45.0
			if future_moves.size() >= 4:
				score += 20.0
			if future_finishers > 0:
				score += 20.0
			if target_state.stamina_percent() < 40.0:
				score += 15.0
			if target_state.fatigue > 60.0:
				score += 15.0
			if _score_pin(ai_state, target_state, match_time_seconds, 0.0) >= 80.0:
				score -= 15.0
			if valid_moves.size() >= 3:
				score -= 10.0
			if player_crash_opportunity:
				score += 15.0
		MatchSetupStateRules.IRISH_WHIP:
			score += 45.0
			if not future_moves.is_empty():
				score += 25.0
			if _contains_impact(future_moves, 6):
				score += 15.0
			if _has_any_class(ai_state.wrestler, [WrestlerResource.WrestlerClass.POWERHOUSE, WrestlerResource.WrestlerClass.STRIKER]):
				score += 10.0
		MatchSetupStateRules.THROW_INTO_CORNER:
			score += 45.0
			if not future_moves.is_empty():
				score += 25.0
			if future_finishers > 0:
				score += 20.0
			if target_state.fatigue > 60.0:
				score += 10.0
		MatchSetupStateRules.START_RUNNING:
			score += 35.0
			if not future_moves.is_empty():
				score += 25.0
			if future_finishers > 0:
				score += 15.0
		MatchSetupStateRules.CLIMB_TOP_ROPE:
			score += 35.0
			if not future_moves.is_empty():
				score += 30.0
			if future_finishers > 0:
				score += 25.0
			if target_state.momentum > 70.0:
				score -= 15.0
		MatchSetupStateRules.PREPARE_SPRINGBOARD:
			score += 35.0
			if not future_moves.is_empty():
				score += 30.0
			if future_finishers > 0:
				score += 20.0
		MatchSetupStateRules.WAKE_OPPONENT:
			score += 50.0
			if not future_moves.is_empty():
				score += 35.0
			if future_finishers > 0:
				score += 45.0
			if not valid_moves.is_empty():
				score -= 25.0
		MatchSetupStateRules.RETURN_TO_RING, MatchSetupStateRules.CLIMB_DOWN:
			score += 20.0
			if valid_moves.is_empty():
				score += 60.0
			if MatchExhaustionModel.combined_exhaustion(ai_state) >= 0.70:
				score += 40.0
			if not valid_moves.is_empty():
				score -= 30.0
		MatchSetupStateRules.STOP_RUNNING, MatchSetupStateRules.LEAVE_CORNER, MatchSetupStateRules.REGAIN_FOOTING:
			score += 80.0 if valid_moves.is_empty() else 20.0
		MatchSetupStateRules.GRAPPLE_OPPONENT:
			if future_moves.size() >= 4:
				score += 10.0
			if _has_class(ai_state.wrestler, WrestlerResource.WrestlerClass.TECHNICIAN):
				score += 10.0
		MatchSetupStateRules.TAUNT:
			# A taunt should remain an occasional flavour/condition choice rather
			# than compete evenly with real offence.
			score -= 35.0
			if target_state.current_position == WrestlerResource.Position.GROUNDED:
				score += 30.0
			else:
				score -= 20.0
			if ai_state.stamina_percent() < 35.0:
				score += 15.0
			elif ai_state.stamina_percent() < 60.0:
				score += 8.0
			elif ai_state.stamina_percent() > 80.0:
				score -= 10.0
			if ai_state.momentum < 30.0:
				score += 8.0
			elif ai_state.momentum <= 70.0:
				score += 4.0
			elif ai_state.momentum > 85.0:
				score -= 10.0
			if ai_state.current_area == WrestlerResource.Area.APRON:
				score += 5.0
			elif ai_state.current_area == WrestlerResource.Area.TOP_ROPE:
				score += 8.0
			if ai_state.wrestler != null:
				score += clampf((ai_state.wrestler.charisma - 50.0) * 0.20, -10.0, 10.0)
				if ai_state.wrestler.wrestler_disposition == WrestlerResource.WrestlerDisposition.HEEL:
					score += 5.0
				if (
					ai_state.current_area in [WrestlerResource.Area.APRON, WrestlerResource.Area.TOP_ROPE]
					and _has_class(ai_state.wrestler, WrestlerResource.WrestlerClass.HIGH_FLYER)
				):
					score += 5.0
		MatchSetupStateRules.CATCH_BREATH:
			score -= 20.0
			if ai_state.stamina_percent() < 20.0:
				score += 65.0
			elif ai_state.stamina_percent() < 40.0:
				score += 42.0
			else:
				score += 12.0
			score += (1.0 - MatchExhaustionModel.stamina_recovery_multiplier(ai_state)) * -10.0
			if target_state.current_position == WrestlerResource.Position.GROUNDED:
				score += 12.0
			if future_finishers > 0 or _score_pin(ai_state, target_state, match_time_seconds, 0.0) >= 70.0:
				score -= 90.0
	var movement_setup := action_id in [
		MatchSetupStateRules.START_RUNNING,
		MatchSetupStateRules.CLIMB_TOP_ROPE,
		MatchSetupStateRules.PREPARE_SPRINGBOARD,
		MatchSetupStateRules.STEP_TO_ROPES,
		MatchSetupStateRules.SEND_OPPONENT_OUTSIDE,
		MatchSetupStateRules.CALL_OPPONENT_OUTSIDE,
		MatchSetupStateRules.TAKE_FIGHT_OUTSIDE,
		MatchSetupStateRules.FIGHT_UP_RAMP,
	]
	var high_value_followup := _has_high_value_followup(future_moves, target_state)
	var setup_exhaustion := MatchExhaustionModel.combined_exhaustion(ai_state)
	if movement_setup and setup_exhaustion >= 0.70:
		var movement_penalty := -45.0 * setup_exhaustion
		if setup_exhaustion >= 0.90:
			movement_penalty = -80.0
		if high_value_followup:
			movement_penalty *= 0.25
		score += movement_penalty
		_debug_setup_rejection(action_id, "movement while exhausted")
	elif mandatory_recovery and setup_exhaustion >= 0.80:
		score += 15.0
	elif mandatory_recovery and setup_exhaustion >= 0.60:
		score += 10.0
	if setup_exhaustion >= 0.70:
		score += 8.0 if mandatory_recovery else 0.0
	if ai_state.momentum < 20.0:
		score += 8.0
	if action_id != MatchSetupStateRules.CATCH_BREATH and ai_state.consecutive_setup_actions >= 1:
		score -= 40.0
	if action_id != MatchSetupStateRules.CATCH_BREATH and action_id in recent_setup_actions:
		score -= 60.0
	if action_id != MatchSetupStateRules.CATCH_BREATH and ai_state.consecutive_setup_actions >= 2 and not mandatory_recovery:
		score -= 75.0
	if action_id != MatchSetupStateRules.CATCH_BREATH and setup_cooldown_turns > 0 and not mandatory_recovery:
		score -= 100.0
	var escalation := MatchInteractionModel.build_late_match_profile(match_time_seconds)
	if movement_setup and not mandatory_recovery:
		score -= float(escalation.get("movement_setup_penalty", 0.0))
	if _has_class(ai_state.wrestler, WrestlerResource.WrestlerClass.POWERHOUSE) and action_id in [MatchSetupStateRules.IRISH_WHIP, MatchSetupStateRules.THROW_INTO_CORNER]:
		score += 10.0
	var targeting_threat := _incoming_targeting_context(ai_state, target_state)
	if not targeting_threat.is_empty():
		var threatened_part := int(targeting_threat.get("part", MoveResource.MoveTargetParts.NONE))
		var threatened_hp := float(targeting_threat.get("hp", 100.0))
		if action_id in [
			MatchSetupStateRules.IRISH_WHIP,
			MatchSetupStateRules.THROW_INTO_CORNER,
			MatchSetupStateRules.GRAPPLE_OPPONENT,
		]:
			score += 8.0
		if action_id in [
			MatchSetupStateRules.STOP_RUNNING,
			MatchSetupStateRules.LEAVE_CORNER,
			MatchSetupStateRules.REGAIN_FOOTING,
			MatchSetupStateRules.RETURN_TO_RING,
			MatchSetupStateRules.CLIMB_DOWN,
			MatchSetupStateRules.RESET_STANCE,
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
	if target_state.stamina_percent() < 20.0:
		score += 25.0
	elif target_state.stamina_percent() < 40.0:
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
	if MatchExhaustionModel.combined_exhaustion(ai_state) >= 0.70 and (target_state.body_hp < 70.0 or target_state.head_hp < 70.0):
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
		or target_state.stamina_percent() <= 30.0
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


func _ready_special_rank(ai_state: MatchSideState, move: MoveResource) -> int:
	if ai_state == null or move == null:
		return 0
	if ai_state.finisher_stock > 0 and ai_state.is_finisher_move(move):
		return 2
	if ai_state.signature_ready and ai_state.is_signature_move(move):
		return 1
	return 0


func _best_ready_special_move_candidate(
	candidates: Array[Dictionary],
	ai_state: MatchSideState,
) -> Dictionary:
	var best: Dictionary = {}
	var best_rank := 0
	for candidate in candidates:
		if StringName(candidate.get("kind", &"")) != KIND_MOVE:
			continue
		var move := candidate.get("move") as MoveResource
		var rank := _ready_special_rank(ai_state, move)
		if rank <= 0:
			continue
		if (
			best.is_empty()
			or rank > best_rank
			or (
				rank == best_rank
				and float(candidate.get("score", -INF)) > float(best.get("score", -INF))
			)
		):
			best = candidate
			best_rank = rank
	return best


func _best_ready_special_setup_candidate(
	candidates: Array[Dictionary],
	ai_state: MatchSideState,
) -> Dictionary:
	var best: Dictionary = {}
	var best_rank := 0
	var best_steps := 999
	for candidate in candidates:
		if StringName(candidate.get("kind", &"")) != KIND_SETUP:
			continue
		var planned_move := candidate.get("planned_move") as MoveResource
		var rank := _ready_special_rank(ai_state, planned_move)
		if rank <= 0:
			continue
		var path: Array = candidate.get("setup_path", [])
		var steps := path.size()
		if (
			best.is_empty()
			or rank > best_rank
			or (rank == best_rank and steps < best_steps)
			or (
				rank == best_rank
				and steps == best_steps
				and float(candidate.get("score", -INF)) > float(best.get("score", -INF))
			)
		):
			best = candidate
			best_rank = rank
			best_steps = steps
	return best


func _best_recovery_candidate(candidates: Array[Dictionary]) -> Dictionary:
	var priority := [
		MatchSetupStateRules.STAND_UP,
		MatchSetupStateRules.REGAIN_COMPOSURE,
		MatchSetupStateRules.PRESS_ADVANTAGE,
		MatchSetupStateRules.REGAIN_FOOTING,
		MatchSetupStateRules.LEAVE_CORNER,
		MatchSetupStateRules.LEAVE_ROPES,
		MatchSetupStateRules.RETURN_TO_RING,
		MatchSetupStateRules.RETURN_FROM_RAMP,
		MatchSetupStateRules.PULL_OPPONENT_FROM_CORNER,
		MatchSetupStateRules.PULL_OPPONENT_FROM_ROPES,
		MatchSetupStateRules.BRING_OPPONENT_INTO_RING,
		MatchSetupStateRules.CATCH_OPPONENT_RUNNING,
		MatchSetupStateRules.BRING_MATCH_BACK_TO_RING,
		MatchSetupStateRules.CLIMB_DOWN,
		MatchSetupStateRules.STOP_RUNNING,
		MatchSetupStateRules.RESET_STANCE,
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


func _candidate_for_setup_action(candidates: Array[Dictionary], action_id: StringName) -> Dictionary:
	var best: Dictionary = {}
	for candidate in candidates:
		if (
			StringName(candidate.get("kind", &"")) != KIND_SETUP
			or StringName(candidate.get("setup_action", &"")) != action_id
		):
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
			if action_id == MatchSetupStateRules.CATCH_BREATH:
				recent_setup_actions.append(&"")
				ai_state.clear_setup_streak()
			else:
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


func _project_states(attacker_state: MatchSideState, target_state: MatchSideState, action_id: StringName) -> Dictionary:
	return MatchSetupStateRules.project_action(action_id, attacker_state.snapshot(), target_state.snapshot())


func _best_setup_plan(
	ai_state: MatchSideState,
	target_state: MatchSideState,
	action_id: StringName,
	match_time_seconds: int,
) -> Dictionary:
	if ai_state == null or ai_state.wrestler == null:
		return {}
	var best: Dictionary = {}
	var best_score := -INF
	for path_data in MatchSetupStateRules.find_followup_paths(
		ai_state.all_assigned_moves(),
		ai_state.snapshot(),
		target_state.snapshot(),
		2,
	):
		var path: Array = path_data.get("actions", [])
		var move := path_data.get("move") as MoveResource
		if path.is_empty() or StringName(path[0]) != action_id or move == null:
			continue
		if not ai_state.can_use_move(move):
			continue
		var score := float(move.move_impact) * 10.0 - float(path.size() - 1) * 12.0
		if ai_state.finisher_stock > 0 and ai_state.is_finisher_move(move):
			score += 160.0
		elif ai_state.signature_ready and ai_state.is_signature_move(move):
			score += 140.0
		elif move.is_finisher:
			score += 35.0
		if move.is_submission:
			score += 8.0
		if score > best_score:
			best_score = score
			best = path_data
	return best


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
		_debug_setup_rejection(MatchSetupStateRules.TAUNT, "no current move; preserve recovery/setup flow")
		return true
	for move in valid_moves:
		if move != null and move.is_finisher:
			_debug_setup_rejection(MatchSetupStateRules.TAUNT, "available finisher")
			return true
	if _score_pin(ai_state, target_state, match_time_seconds, best_move_score) >= 45.0:
		_debug_setup_rejection(MatchSetupStateRules.TAUNT, "credible pin available")
		return true
	var interruption_chance := MatchInteractionModel.response_success_chance(
		ai_state,
		target_state,
		null,
		match_time_seconds,
		MatchSetupStateRules.TAUNT,
	)
	if target_state.current_position == WrestlerResource.Position.STANDING and interruption_chance >= 45.0:
		ai_state.ai_taunts_rejected_risk += 1
		_debug_setup_rejection(MatchSetupStateRules.TAUNT, "standing opponent interruption risk %.1f" % interruption_chance)
		return true
	return false


func _taunt_positions_are_stable(ai_state: MatchSideState, target_state: MatchSideState) -> bool:
	return (
		ai_state != null
		and target_state != null
		and ai_state.current_position in [
			WrestlerResource.Position.STANDING,
			WrestlerResource.Position.PERCHED,
		]
		and ai_state.current_area in [WrestlerResource.Area.IN_RING, WrestlerResource.Area.APRON, WrestlerResource.Area.TOP_ROPE, WrestlerResource.Area.OUTSIDE, WrestlerResource.Area.RAMP]
		and target_state.current_position in [
			WrestlerResource.Position.STANDING,
			WrestlerResource.Position.GROUNDED,
		]
	)


func _is_mandatory_recovery(action_id: StringName, valid_moves: Array[MoveResource]) -> bool:
	if action_id in [
		MatchSetupStateRules.STAND_UP,
		MatchSetupStateRules.REGAIN_FOOTING,
		MatchSetupStateRules.REGAIN_COMPOSURE,
		MatchSetupStateRules.PRESS_ADVANTAGE,
		MatchSetupStateRules.RESET_STANCE,
	]:
		return true
	if MatchSetupStateRules.is_recovery(action_id):
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
	planned_setup_actions.clear()
	planned_followup_move_key = ""


func _abandon_setup_intent(ai_state: MatchSideState) -> void:
	if last_setup_intent.is_empty() and not setup_intent_pending_attempt:
		return
	if ai_state != null:
		ai_state.setup_intents_abandoned += 1
	_clear_setup_intent()


func _selected_setup_had_loop_penalty(ai_state: MatchSideState, action_id: StringName) -> bool:
	if ai_state == null or action_id.is_empty() or action_id == MatchSetupStateRules.CATCH_BREATH:
		return false
	var mandatory := MatchSetupStateRules.is_recovery(action_id)
	return (
		ai_state.consecutive_setup_actions >= 1
		or action_id in recent_setup_actions
		or (ai_state.consecutive_setup_actions >= 2 and not mandatory)
		or (setup_cooldown_turns > 0 and not mandatory)
	)


func _candidate_diagnostic(candidate: Dictionary) -> Dictionary:
	var move := candidate.get("move") as MoveResource
	return {
		"kind": String(candidate.get("kind", &"")),
		"score": float(candidate.get("score", 0.0)),
		"move": move.move_name if move != null else "",
		"setup_action": String(candidate.get("setup_action", &"")),
	}


func _top_candidate_diagnostics(candidates: Array[Dictionary]) -> Array[Dictionary]:
	var ordered := candidates.duplicate(true)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("score", 0.0)) > float(b.get("score", 0.0)))
	var result: Array[Dictionary] = []
	for index in range(mini(5, ordered.size())):
		result.append(_candidate_diagnostic(ordered[index]))
	return result


func _debug_setup_rejection(action_id: StringName, reason: String) -> void:
	_decision_rejections.append({"setup_action": String(action_id), "reason": reason})


func _moves_for_states(
	ai_state: MatchSideState,
	attacker_state: Dictionary,
	target_state: Dictionary,
	match_time_seconds: int,
) -> Array[MoveResource]:
	var moves: Array[MoveResource] = []
	if ai_state.wrestler == null:
		return moves
	for move in ai_state.all_assigned_moves():
		if move == null:
			continue
		if not _position_matches(move.required_attacker_position, int(attacker_state.get("position", WrestlerResource.Position.NONE))):
			continue
		if not _position_matches(move.required_target_position, int(target_state.get("position", WrestlerResource.Position.NONE))):
			continue
		if not _orientation_matches(move.required_attacker_orientation, int(attacker_state.get("orientation", WrestlerResource.Orientation.NONE))):
			continue
		if not _orientation_matches(move.required_target_orientation, int(target_state.get("orientation", WrestlerResource.Orientation.NONE))):
			continue
		if not MatchAreaRules.move_areas_match(
			move,
			int(attacker_state.get("area", WrestlerResource.Area.IN_RING)),
			int(target_state.get("area", WrestlerResource.Area.IN_RING)),
		):
			continue
		if (
			not MatchSetupStateRules.motion_matches(move.required_attacker_motion_state, int(attacker_state.get("motion_state", WrestlerResource.MotionState.STATIONARY)))
			or not MatchSetupStateRules.motion_matches(move.required_target_motion_state, int(target_state.get("motion_state", WrestlerResource.MotionState.STATIONARY)))
		):
			continue
		if not ai_state.can_use_move(move):
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
	if move == null:
		return false
	if not planned_followup_move_key.is_empty():
		return _move_key(move) == planned_followup_move_key
	match intent:
		MatchSetupStateRules.IRISH_WHIP:
			return move.required_target_motion_state == WrestlerResource.MotionState.ROPE_REBOUND or (move.required_target_area_mode == MoveResource.AreaRequirementMode.SPECIFIC and move.required_target_area == WrestlerResource.Area.ROPES)
		MatchSetupStateRules.THROW_INTO_CORNER:
			return move.required_target_area_mode == MoveResource.AreaRequirementMode.SPECIFIC and move.required_target_area == WrestlerResource.Area.CORNER
		MatchSetupStateRules.START_RUNNING:
			return move.move_type == MoveResource.MoveType.RUNNING
		MatchSetupStateRules.CLIMB_TOP_ROPE:
			return move.move_type == MoveResource.MoveType.AERIAL or (move.required_attacker_area_mode == MoveResource.AreaRequirementMode.SPECIFIC and move.required_attacker_area == WrestlerResource.Area.TOP_ROPE)
		MatchSetupStateRules.WAKE_OPPONENT:
			return move.move_type == MoveResource.MoveType.AERIAL and move.required_target_position == WrestlerResource.Position.STANDING
		MatchSetupStateRules.PREPARE_SPRINGBOARD:
			return move.move_type == MoveResource.MoveType.SPRINGBOARD
		MatchSetupStateRules.PICK_OPPONENT_UP, MatchSetupStateRules.GRAPPLE_OPPONENT:
			return move.move_type in [MoveResource.MoveType.GRAPPLE, MoveResource.MoveType.SUBMISSION]
	return not MatchSetupStateRules.is_recovery(intent) and intent != MatchSetupStateRules.TAUNT


func _setup_creates_intent(action_id: StringName) -> bool:
	return not MatchSetupStateRules.is_recovery(action_id) and action_id != MatchSetupStateRules.TAUNT


func _move_key(move: MoveResource) -> String:
	if move == null:
		return ""
	return move.resource_path if not move.resource_path.is_empty() else move.move_name


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
		MoveResource.MoveType.AERIAL,
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


func _orientation_matches(required: int, actual: int) -> bool:
	return required == WrestlerResource.Orientation.NONE or required == actual


func _is_high_risk(move: MoveResource) -> bool:
	return MatchInteractionModel.is_high_risk_move(move)
