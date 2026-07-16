extends RefCounted
class_name MatchSideState

var wrestler: WrestlerResource
var current_position: int = WrestlerResource.Position.STANDING
var head_hp: float = 100.0
var body_hp: float = 100.0
var left_arm_hp: float = 100.0
var right_arm_hp: float = 100.0
var left_leg_hp: float = 100.0
var right_leg_hp: float = 100.0
var stamina: float = 100.0
var fatigue: float = 0.0
var momentum: float = 0.0
var last_position: int = WrestlerResource.Position.STANDING
var last_action_result: int = 0
var recent_moves_used: Array[String] = []
var recent_move_types: Array[int] = []
var recent_setup_patterns: Array[StringName] = []
var pending_setup_action: StringName = &""
var last_move_taken: MoveResource
var last_move_landed: MoveResource
var last_move_was_finisher: bool = false
var last_move_was_high_risk: bool = false
var move_attempts: int = 0
var moves_landed: int = 0
var finisher_attempts: int = 0
var finishers_landed: int = 0
var reversals: int = 0
var setup_actions: int = 0
var pin_attempts: int = 0
var kickouts: int = 0
var submission_attempts: int = 0
var submission_escapes: int = 0
var damage_dealt: float = 0.0
var damage_taken: float = 0.0
var move_names_used: Array[String] = []
var move_use_counts: Dictionary = {}
var total_move_impact_attempted: int = 0
var successful_setup_followups: int = 0
var execution_attempts: int = 0
var execution_successes: int = 0
var response_attempts: int = 0
var response_successes: int = 0
var botches_scrambles: int = 0
var high_risk_crashes: int = 0
var submission_wins: int = 0
var submission_struggle_wins: int = 0
var submission_struggle_losses: int = 0
var submission_struggle_seconds: float = 0.0
var contested_setup_attempts: int = 0
var contested_setup_wins: int = 0
var contested_setup_losses: int = 0
var contested_setup_draws: int = 0
var taunts_attempted: int = 0
var taunts_succeeded: int = 0
var taunts_interrupted: int = 0
var taunt_stamina_recovered: float = 0.0
var taunt_momentum_gained: float = 0.0
var taunt_bonus_momentum_granted: float = 0.0
var taunt_bonus_momentum_consumed: float = 0.0
var pending_taunt_momentum_bonus: float = 0.0
var taunt_cooldown_until_seconds: int = 0
var ai_taunts_rejected_cooldown: int = 0
var ai_taunts_rejected_risk: int = 0
var control_meter_attempts: int = 0
var control_meter_successes: int = 0
var timing_circle_attempts: int = 0
var timing_circle_successes: int = 0
var kickout_meter_attempts: int = 0
var kickout_meter_successes: int = 0
var kickout_meter_near_misses: int = 0
var kickout_meter_timeouts: int = 0
var reversal_opportunities: int = 0
var high_risk_attempts: int = 0
var repetition_penalties_applied: int = 0
var low_stamina_penalties_applied: int = 0
var execution_profile_total: float = 0.0
var execution_profile_samples: int = 0
var response_profile_total: float = 0.0
var response_profile_samples: int = 0
var finish_pressure_total: float = 0.0
var finish_pressure_samples: int = 0
var clean_successes: int = 0
var laboured_successes: int = 0
var near_misses: int = 0
var near_miss_conversions: int = 0
var contested_struggles: int = 0
var neutral_resets: int = 0
var consecutive_neutral_resets: int = 0
var maximum_consecutive_neutral_resets: int = 0
var consecutive_setup_actions: int = 0
var maximum_consecutive_setup_actions: int = 0
var setup_actions_without_followup: int = 0
var setup_intents_created: int = 0
var setup_intents_completed: int = 0
var setup_intents_abandoned: int = 0
var setup_loop_penalties: int = 0
var dead_end_setups_prevented: int = 0
var forced_fallback_actions: int = 0
var late_escalation_total: float = 0.0
var late_escalation_samples: int = 0
var target_focus_body_part: int = MoveResource.MoveTargetParts.NONE
var target_focus_reason: String = "Auto"
var target_focus_age: int = 0
var target_focus_start_hp: float = 100.0
var target_focus_damage_progress: float = 0.0
var target_attack_counts: Dictionary = {}
var target_damage_dealt: Dictionary = {}
var target_focus_usage_counts: Dictionary = {}
var body_part_thresholds_crossed: Dictionary = {}
var repeated_target_milestones: Dictionary = {}
var last_submission_target: int = MoveResource.MoveTargetParts.NONE
var last_finisher_target: int = MoveResource.MoveTargetParts.NONE
var last_body_commentary_time: int = -100000
var pending_body_commentary: Dictionary = {}
var recent_target_parts: Array[int] = []


func initialize(value: WrestlerResource) -> void:
	wrestler = value
	current_position = WrestlerResource.Position.STANDING
	last_position = current_position
	head_hp = 100.0
	body_hp = 100.0
	left_arm_hp = 100.0
	right_arm_hp = 100.0
	left_leg_hp = 100.0
	right_leg_hp = 100.0
	stamina = 100.0
	fatigue = 0.0
	momentum = 0.0
	last_action_result = 0
	recent_moves_used.clear()
	recent_move_types.clear()
	recent_setup_patterns.clear()
	pending_setup_action = &""
	last_move_taken = null
	last_move_landed = null
	last_move_was_finisher = false
	last_move_was_high_risk = false
	move_attempts = 0
	moves_landed = 0
	finisher_attempts = 0
	finishers_landed = 0
	reversals = 0
	setup_actions = 0
	pin_attempts = 0
	kickouts = 0
	submission_attempts = 0
	submission_escapes = 0
	damage_dealt = 0.0
	damage_taken = 0.0
	move_names_used.clear()
	move_use_counts.clear()
	total_move_impact_attempted = 0
	successful_setup_followups = 0
	execution_attempts = 0
	execution_successes = 0
	response_attempts = 0
	response_successes = 0
	botches_scrambles = 0
	high_risk_crashes = 0
	submission_wins = 0
	submission_struggle_wins = 0
	submission_struggle_losses = 0
	submission_struggle_seconds = 0.0
	contested_setup_attempts = 0
	contested_setup_wins = 0
	contested_setup_losses = 0
	contested_setup_draws = 0
	taunts_attempted = 0
	taunts_succeeded = 0
	taunts_interrupted = 0
	taunt_stamina_recovered = 0.0
	taunt_momentum_gained = 0.0
	taunt_bonus_momentum_granted = 0.0
	taunt_bonus_momentum_consumed = 0.0
	pending_taunt_momentum_bonus = 0.0
	taunt_cooldown_until_seconds = 0
	ai_taunts_rejected_cooldown = 0
	ai_taunts_rejected_risk = 0
	control_meter_attempts = 0
	control_meter_successes = 0
	timing_circle_attempts = 0
	timing_circle_successes = 0
	kickout_meter_attempts = 0
	kickout_meter_successes = 0
	kickout_meter_near_misses = 0
	kickout_meter_timeouts = 0
	reversal_opportunities = 0
	high_risk_attempts = 0
	repetition_penalties_applied = 0
	low_stamina_penalties_applied = 0
	execution_profile_total = 0.0
	execution_profile_samples = 0
	response_profile_total = 0.0
	response_profile_samples = 0
	finish_pressure_total = 0.0
	finish_pressure_samples = 0
	clean_successes = 0
	laboured_successes = 0
	near_misses = 0
	near_miss_conversions = 0
	contested_struggles = 0
	neutral_resets = 0
	consecutive_neutral_resets = 0
	maximum_consecutive_neutral_resets = 0
	consecutive_setup_actions = 0
	maximum_consecutive_setup_actions = 0
	setup_actions_without_followup = 0
	setup_intents_created = 0
	setup_intents_completed = 0
	setup_intents_abandoned = 0
	setup_loop_penalties = 0
	dead_end_setups_prevented = 0
	forced_fallback_actions = 0
	late_escalation_total = 0.0
	late_escalation_samples = 0
	target_focus_body_part = MoveResource.MoveTargetParts.NONE
	target_focus_reason = "Auto"
	target_focus_age = 0
	target_focus_start_hp = 100.0
	target_focus_damage_progress = 0.0
	target_attack_counts.clear()
	target_damage_dealt.clear()
	target_focus_usage_counts.clear()
	body_part_thresholds_crossed.clear()
	repeated_target_milestones.clear()
	last_submission_target = MoveResource.MoveTargetParts.NONE
	last_finisher_target = MoveResource.MoveTargetParts.NONE
	last_body_commentary_time = -100000
	pending_body_commentary.clear()
	recent_target_parts.clear()
	sync_to_resource()


func set_position(value: int) -> void:
	last_position = current_position
	current_position = value
	if wrestler != null:
		wrestler.position = value as WrestlerResource.Position


func get_part_hp(part: int) -> float:
	match part:
		MoveResource.MoveTargetParts.HEAD:
			return head_hp
		MoveResource.MoveTargetParts.BODY:
			return body_hp
		MoveResource.MoveTargetParts.LEFT_ARM:
			return left_arm_hp
		MoveResource.MoveTargetParts.RIGHT_ARM:
			return right_arm_hp
		MoveResource.MoveTargetParts.LEFT_LEG:
			return left_leg_hp
		MoveResource.MoveTargetParts.RIGHT_LEG:
			return right_leg_hp
	return body_hp


func damage_part(part: int, amount: float) -> void:
	var damage := maxf(0.0, amount)
	match part:
		MoveResource.MoveTargetParts.HEAD:
			head_hp = clampf(head_hp - damage, 0.0, 100.0)
		MoveResource.MoveTargetParts.BODY:
			body_hp = clampf(body_hp - damage, 0.0, 100.0)
		MoveResource.MoveTargetParts.LEFT_ARM:
			left_arm_hp = clampf(left_arm_hp - damage, 0.0, 100.0)
		MoveResource.MoveTargetParts.RIGHT_ARM:
			right_arm_hp = clampf(right_arm_hp - damage, 0.0, 100.0)
		MoveResource.MoveTargetParts.LEFT_LEG:
			left_leg_hp = clampf(left_leg_hp - damage, 0.0, 100.0)
		MoveResource.MoveTargetParts.RIGHT_LEG:
			right_leg_hp = clampf(right_leg_hp - damage, 0.0, 100.0)
		_:
			body_hp = clampf(body_hp - damage, 0.0, 100.0)
	sync_to_resource()


func set_target_focus(part: int, reason: String = "Auto") -> void:
	var normalized := part if part in [
		MoveResource.MoveTargetParts.HEAD,
		MoveResource.MoveTargetParts.BODY,
		MoveResource.MoveTargetParts.LEFT_ARM,
		MoveResource.MoveTargetParts.RIGHT_ARM,
		MoveResource.MoveTargetParts.LEFT_LEG,
		MoveResource.MoveTargetParts.RIGHT_LEG,
	] else MoveResource.MoveTargetParts.NONE
	if target_focus_body_part != normalized:
		target_focus_body_part = normalized
		target_focus_age = 0
		target_focus_start_hp = get_part_hp(normalized) if normalized != MoveResource.MoveTargetParts.NONE else 100.0
		target_focus_damage_progress = 0.0
	target_focus_reason = reason


func record_target_resolution(
	part: int,
	damage: float,
	landed: bool,
	move: MoveResource,
) -> void:
	if part == MoveResource.MoveTargetParts.NONE:
		return
	recent_target_parts.append(part)
	while recent_target_parts.size() > 8:
		recent_target_parts.pop_front()
	target_focus_usage_counts[part] = int(target_focus_usage_counts.get(part, 0)) + 1
	if not landed:
		return
	target_attack_counts[part] = int(target_attack_counts.get(part, 0)) + 1
	target_damage_dealt[part] = float(target_damage_dealt.get(part, 0.0)) + maxf(0.0, damage)
	if move != null:
		if move.is_submission:
			last_submission_target = part
		if move.is_finisher:
			last_finisher_target = part
	if target_focus_body_part == part:
		target_focus_damage_progress += maxf(0.0, damage)


func recent_target_part_count(part: int, limit: int = 5) -> int:
	var count := 0
	var start := maxi(0, recent_target_parts.size() - maxi(1, limit))
	for index in range(start, recent_target_parts.size()):
		if recent_target_parts[index] == part:
			count += 1
	return count


func mark_crossed_thresholds(part: int, before_hp: float, after_hp: float) -> Array[int]:
	var crossed: Array[int] = []
	var recorded: Array = body_part_thresholds_crossed.get(part, [])
	for threshold in [80, 60, 40, 20, 0]:
		if before_hp > float(threshold) and after_hp <= float(threshold) and threshold not in recorded:
			recorded.append(threshold)
			crossed.append(threshold)
	body_part_thresholds_crossed[part] = recorded
	return crossed


func mark_repeated_target_milestone(part: int, count: int) -> bool:
	if count not in [3, 5]:
		return false
	var recorded: Array = repeated_target_milestones.get(part, [])
	if count in recorded:
		return false
	recorded.append(count)
	repeated_target_milestones[part] = recorded
	return true


func most_targeted_part() -> int:
	return _highest_dictionary_part(target_attack_counts)


func most_used_focus_part() -> int:
	return _highest_dictionary_part(target_focus_usage_counts)


func most_damaged_part() -> int:
	var parts := [
		MoveResource.MoveTargetParts.HEAD,
		MoveResource.MoveTargetParts.BODY,
		MoveResource.MoveTargetParts.LEFT_ARM,
		MoveResource.MoveTargetParts.RIGHT_ARM,
		MoveResource.MoveTargetParts.LEFT_LEG,
		MoveResource.MoveTargetParts.RIGHT_LEG,
	]
	var result := int(parts[0])
	for part in parts:
		if get_part_hp(int(part)) < get_part_hp(result):
			result = int(part)
	return result


func get_body_damage_summary() -> Dictionary:
	return {
		"final_hp": {
			MoveResource.MoveTargetParts.HEAD: head_hp,
			MoveResource.MoveTargetParts.BODY: body_hp,
			MoveResource.MoveTargetParts.LEFT_ARM: left_arm_hp,
			MoveResource.MoveTargetParts.RIGHT_ARM: right_arm_hp,
			MoveResource.MoveTargetParts.LEFT_LEG: left_leg_hp,
			MoveResource.MoveTargetParts.RIGHT_LEG: right_leg_hp,
		},
		"damage_taken": {
			MoveResource.MoveTargetParts.HEAD: 100.0 - head_hp,
			MoveResource.MoveTargetParts.BODY: 100.0 - body_hp,
			MoveResource.MoveTargetParts.LEFT_ARM: 100.0 - left_arm_hp,
			MoveResource.MoveTargetParts.RIGHT_ARM: 100.0 - right_arm_hp,
			MoveResource.MoveTargetParts.LEFT_LEG: 100.0 - left_leg_hp,
			MoveResource.MoveTargetParts.RIGHT_LEG: 100.0 - right_leg_hp,
		},
		"thresholds_crossed": body_part_thresholds_crossed.duplicate(true),
		"parts_reaching_zero": _parts_reaching_zero(),
		"target_attack_counts": target_attack_counts.duplicate(true),
		"last_submission_target": last_submission_target,
		"last_finisher_target": last_finisher_target,
	}


func _highest_dictionary_part(values: Dictionary) -> int:
	var result := MoveResource.MoveTargetParts.NONE
	var highest := -1.0
	var keys: Array = values.keys()
	keys.sort()
	for key in keys:
		var value := float(values.get(key, 0.0))
		if value > highest:
			highest = value
			result = int(key)
	return result


func _parts_reaching_zero() -> Array[int]:
	var result: Array[int] = []
	for part in [
		MoveResource.MoveTargetParts.HEAD,
		MoveResource.MoveTargetParts.BODY,
		MoveResource.MoveTargetParts.LEFT_ARM,
		MoveResource.MoveTargetParts.RIGHT_ARM,
		MoveResource.MoveTargetParts.LEFT_LEG,
		MoveResource.MoveTargetParts.RIGHT_LEG,
	]:
		if get_part_hp(int(part)) <= 0.0:
			result.append(int(part))
	return result


func spend_stamina(amount: float) -> void:
	stamina = clampf(stamina - maxf(0.0, amount), 0.0, 100.0)


func recover_stamina(amount: float) -> float:
	var before := stamina
	stamina = clampf(stamina + maxf(0.0, amount), 0.0, 100.0)
	return stamina - before


func add_fatigue(amount: float) -> void:
	fatigue = clampf(fatigue + amount, 0.0, 100.0)
	sync_to_resource()


func add_momentum(amount: float) -> void:
	momentum = clampf(momentum + amount, 0.0, 100.0)
	sync_to_resource()


func record_move_used(move: MoveResource, landed: bool = true) -> void:
	if move == null:
		return
	move_attempts += 1
	var display_name := move.move_name if not move.move_name.strip_edges().is_empty() else "Unnamed Move"
	move_names_used.append(display_name)
	move_use_counts[display_name] = int(move_use_counts.get(display_name, 0)) + 1
	total_move_impact_attempted += move.move_impact
	if landed:
		moves_landed += 1
	if move.is_finisher:
		finisher_attempts += 1
		if landed:
			finishers_landed += 1
	if move.is_submission:
		submission_attempts += 1
	var key := move.resource_path if not move.resource_path.is_empty() else move.move_name
	recent_moves_used.append(key)
	recent_move_types.append(move.move_type)
	while recent_moves_used.size() > 8:
		recent_moves_used.pop_front()
	while recent_move_types.size() > 8:
		recent_move_types.pop_front()
	if not pending_setup_action.is_empty():
		var pattern := StringName("%s:%d" % [pending_setup_action, move.move_type])
		recent_setup_patterns.append(pattern)
		while recent_setup_patterns.size() > 5:
			recent_setup_patterns.pop_front()
		pending_setup_action = &""
	if landed:
		last_move_landed = move
		last_move_was_finisher = move.is_finisher


func repeated_move_count(move: MoveResource) -> int:
	if move == null:
		return 0
	var key := move.resource_path if not move.resource_path.is_empty() else move.move_name
	var count := 0
	for recent_key in recent_moves_used:
		if recent_key == key:
			count += 1
	return count


func recent_move_count(move: MoveResource, window: int) -> int:
	if move == null:
		return 0
	var key := move.resource_path if not move.resource_path.is_empty() else move.move_name
	var count := 0
	var start := maxi(0, recent_moves_used.size() - maxi(0, window))
	for index in range(start, recent_moves_used.size()):
		if recent_moves_used[index] == key:
			count += 1
	return count


func last_attempted_move_matches(move: MoveResource) -> bool:
	if move == null or recent_moves_used.is_empty():
		return false
	var key := move.resource_path if not move.resource_path.is_empty() else move.move_name
	return recent_moves_used.back() == key


func recent_move_type_count(move_type: int, window: int) -> int:
	var count := 0
	var start := maxi(0, recent_move_types.size() - maxi(0, window))
	for index in range(start, recent_move_types.size()):
		if recent_move_types[index] == move_type:
			count += 1
	return count


func note_setup_action(action_id: StringName) -> void:
	pending_setup_action = action_id


func setup_pattern_repeats(move: MoveResource) -> bool:
	if move == null or pending_setup_action.is_empty():
		return false
	var pattern := StringName("%s:%d" % [pending_setup_action, move.move_type])
	return pattern in recent_setup_patterns


func average_execution_profile() -> float:
	return execution_profile_total / float(maxi(1, execution_profile_samples))


func average_response_profile() -> float:
	return response_profile_total / float(maxi(1, response_profile_samples))


func average_finish_pressure() -> float:
	return finish_pressure_total / float(maxi(1, finish_pressure_samples))


func average_late_escalation() -> float:
	return late_escalation_total / float(maxi(1, late_escalation_samples))


func note_neutral_reset() -> void:
	neutral_resets += 1
	consecutive_neutral_resets += 1
	maximum_consecutive_neutral_resets = maxi(maximum_consecutive_neutral_resets, consecutive_neutral_resets)


func clear_neutral_reset_streak() -> void:
	consecutive_neutral_resets = 0


func note_setup_streak() -> void:
	consecutive_setup_actions += 1
	maximum_consecutive_setup_actions = maxi(maximum_consecutive_setup_actions, consecutive_setup_actions)


func clear_setup_streak() -> void:
	consecutive_setup_actions = 0


func move_variety_count() -> int:
	return move_use_counts.size()


func top_move_used() -> String:
	var best_name := "None"
	var best_count := 0
	var names: Array = move_use_counts.keys()
	names.sort()
	for move_name in names:
		var count := int(move_use_counts.get(move_name, 0))
		if count > best_count:
			best_name = str(move_name)
			best_count = count
	return best_name


func average_attempted_impact() -> float:
	if move_attempts <= 0:
		return 0.0
	return float(total_move_impact_attempted) / float(move_attempts)


func lowest_target_hp(parts: Array[MoveResource.MoveTargetParts]) -> float:
	if parts.is_empty():
		return body_hp
	var lowest := 100.0
	for part in parts:
		lowest = minf(lowest, get_part_hp(int(part)))
	return lowest


func average_target_hp(parts: Array[MoveResource.MoveTargetParts]) -> float:
	if parts.is_empty():
		return body_hp
	var total := 0.0
	for part in parts:
		total += get_part_hp(int(part))
	return total / float(parts.size())


func total_hp() -> float:
	return head_hp + body_hp + left_arm_hp + right_arm_hp + left_leg_hp + right_leg_hp


func snapshot() -> Dictionary:
	return {
		"position": current_position,
		"head_hp": head_hp,
		"body_hp": body_hp,
		"left_arm_hp": left_arm_hp,
		"right_arm_hp": right_arm_hp,
		"left_leg_hp": left_leg_hp,
		"right_leg_hp": right_leg_hp,
		"stamina": stamina,
		"fatigue": fatigue,
		"momentum": momentum,
	}


func sync_to_resource() -> void:
	if wrestler == null:
		return
	wrestler.position = current_position as WrestlerResource.Position
	wrestler.head_hp = head_hp
	wrestler.body_hp = body_hp
	wrestler.left_arm_hp = left_arm_hp
	wrestler.right_arm_hp = right_arm_hp
	wrestler.left_leg_hp = left_leg_hp
	wrestler.right_leg_hp = right_leg_hp
	wrestler.fatigue = fatigue
	wrestler.momentum = momentum
