extends RefCounted
class_name MatchInteractionModel

enum InteractionType {
	TIMING_STRIKE,
	TIMING_AERIAL,
	HOLD_POWER,
	HOLD_REPOSITION,
	TIMING_REVERSAL,
	PIN_CIRCLE,
	SUBMISSION_LOCK_IN,
	SUBMISSION_TUG,
	PIN_CONTROL_METER,
}

enum InputResult { FAIL, SUCCESS, NEAR_MISS }

enum CombinedOutcome {
	CLEAN_SUCCESS,
	REVERSAL,
	CONTESTED_STRUGGLE,
	BOTCH_OR_SCRAMBLE,
	HIGH_RISK_CRASH,
	KICKOUT,
	PIN_CONTINUES,
	PINFALL,
	SUBMISSION_ESCAPE,
	SUBMISSION_CONTINUES,
	TAP_OUT,
	LABOURED_SUCCESS,
}

const AERIAL_TERMS := [
	"aerial",
	"dive",
	"diving",
	"springboard",
	"moonsault",
	"shooting star",
	"crossbody",
	"senton",
	"splash",
	"hurricanrana",
	"rana",
	"plancha",
	"corkscrew",
	"elbow drop",
	"leg drop",
	"knee drop",
	"headbutt drop",
	"double stomp",
	"meteora",
]

static func get_interaction_type_for_move(move: MoveResource) -> int:
	if move == null:
		return InteractionType.HOLD_POWER
	match move.interaction_override:
		MoveResource.InteractionOverride.TIMING_STRIKE:
			return InteractionType.TIMING_STRIKE
		MoveResource.InteractionOverride.TIMING_AERIAL:
			return InteractionType.TIMING_AERIAL
		MoveResource.InteractionOverride.HOLD_POWER:
			return InteractionType.HOLD_POWER
		MoveResource.InteractionOverride.SUBMISSION_LOCK_IN:
			return InteractionType.SUBMISSION_LOCK_IN
	if move.is_submission or move.move_type == MoveResource.MoveType.SUBMISSION:
		return InteractionType.SUBMISSION_LOCK_IN
	if move.is_strike or move.move_type == MoveResource.MoveType.STRIKE:
		return InteractionType.TIMING_STRIKE
	if move.move_type in [
		MoveResource.MoveType.AERIAL,
		MoveResource.MoveType.SPRINGBOARD,
	] or (
		move.required_attacker_area_mode == MoveResource.AreaRequirementMode.SPECIFIC
		and move.required_attacker_area in [WrestlerResource.Area.TOP_ROPE, WrestlerResource.Area.APRON]
	):
		return InteractionType.TIMING_AERIAL
	var normalized_name := move.move_name.to_lower()
	for term in AERIAL_TERMS:
		if normalized_name.contains(term):
			return InteractionType.TIMING_AERIAL
	return InteractionType.HOLD_POWER


static func get_interaction_type_for_setup_action(action_id: StringName) -> int:
	if MatchSetupStateRules.is_contested(action_id):
		return InteractionType.HOLD_REPOSITION
	return -1


static func is_contested_setup(action_id: StringName) -> bool:
	return get_interaction_type_for_setup_action(action_id) == InteractionType.HOLD_REPOSITION


static func combine_results(
	attacker_result: int,
	defender_result: int,
	high_risk: bool = false,
	allow_laboured: bool = false,
) -> int:
	if attacker_result == InputResult.SUCCESS:
		if defender_result == InputResult.FAIL:
			return CombinedOutcome.CLEAN_SUCCESS
		return CombinedOutcome.CONTESTED_STRUGGLE
	if attacker_result == InputResult.NEAR_MISS:
		if defender_result == InputResult.SUCCESS:
			return CombinedOutcome.HIGH_RISK_CRASH if high_risk else CombinedOutcome.REVERSAL
		if allow_laboured and defender_result == InputResult.FAIL:
			return CombinedOutcome.LABOURED_SUCCESS
		if allow_laboured and defender_result == InputResult.NEAR_MISS:
			return CombinedOutcome.CONTESTED_STRUGGLE
		return CombinedOutcome.BOTCH_OR_SCRAMBLE
	if defender_result == InputResult.SUCCESS:
		return CombinedOutcome.HIGH_RISK_CRASH if high_risk else CombinedOutcome.REVERSAL
	return CombinedOutcome.HIGH_RISK_CRASH if high_risk else CombinedOutcome.BOTCH_OR_SCRAMBLE


static func resolve_binary_outcome(reversed: bool, high_risk: bool = false) -> int:
	if not reversed:
		return CombinedOutcome.CLEAN_SUCCESS
	return CombinedOutcome.HIGH_RISK_CRASH if high_risk else CombinedOutcome.REVERSAL


static func build_execution_profile(
	state: MatchSideState,
	move: MoveResource,
	interaction_type: int,
	environmental_followup: bool = false,
) -> Dictionary:
	var base_window := 22.0
	var time_limit := 1.6
	var marker_speed := 1.25
	var heavy := move != null and (move.move_impact >= 7 or move.strike_weight == MoveResource.StrikeWeight.STRIKE_HEAVY)
	var finisher := move != null and move.is_finisher
	var high_risk := _is_high_risk(move)
	var running_or_rebound_power := move != null and (
		move.move_type == MoveResource.MoveType.RUNNING
		or move.required_attacker_motion_state in [WrestlerResource.MotionState.RUNNING, WrestlerResource.MotionState.ROPE_REBOUND]
		or move.required_target_motion_state == WrestlerResource.MotionState.ROPE_REBOUND
	)
	var control_meter := interaction_type in [
		InteractionType.HOLD_POWER,
		InteractionType.HOLD_REPOSITION,
		InteractionType.SUBMISSION_LOCK_IN,
	]
	match interaction_type:
		InteractionType.TIMING_STRIKE:
			base_window = 17.0 if heavy else 22.0
			time_limit = 1.4 if heavy else 1.6
			if finisher:
				base_window = 13.0
				time_limit = 1.25
		InteractionType.TIMING_AERIAL:
			base_window = 8.0 if finisher else 13.0
			time_limit = 1.1 if finisher else 1.25
		_:
			if finisher:
				base_window = 10.0
				marker_speed = 2.0
				time_limit = 1.2
			elif running_or_rebound_power or high_risk:
				base_window = 16.0
				marker_speed = 1.7
				time_limit = 1.35
			elif heavy:
				base_window = 16.0
				marker_speed = 1.7
				time_limit = 1.4
	var modifiers := _difficulty_modifiers(state, move, control_meter, environmental_followup)
	var authored_window := (base_window + float(modifiers.window)) * float(modifiers.execution_multiplier)
	var speed_multiplier := float(modifiers.speed)
	if control_meter:
		authored_window = clampf(authored_window, 6.0, 30.0)
		marker_speed *= speed_multiplier
	else:
		authored_window = clampf(authored_window, 3.0, 30.0)
		speed_multiplier *= 1.20
		if high_risk:
			speed_multiplier *= 1.20
		if finisher:
			speed_multiplier *= 1.20
		marker_speed *= speed_multiplier
	# Every offensive move now uses the same horizontal, one-shot execution
	# meter. The calculated chance remains the AI roll probability; the player's
	# timing target deliberately presents a quarter-scale skill window.
	var effective_chance := clampf(
		execution_success_chance(state, move, interaction_type, environmental_followup),
		6.0,
		70.0,
	)
	return {
		"interaction_type": interaction_type,
		"success_window": effective_chance,
		"authored_window": authored_window,
		# Player execution is a timing-skill check. Keep its visible target compact;
		# AI offence no longer rolls against this value.
		"gold_zone_scale": 1.0 / 7.0,
		"raw_zone_min": 6.0,
		"raw_zone_max": 70.0,
		"binary_only": true,
		"one_way": true,
		"minimum_target_travel": 0.24,
		"time_limit": time_limit,
		"marker_speed": marker_speed,
		"speed_multiplier": speed_multiplier,
		"ai_success_chance": effective_chance,
		"low_stamina_penalty": bool(modifiers.low_stamina),
		"exhaustion_band": int(modifiers.exhaustion_band),
		"exhaustion_combined": float(modifiers.exhaustion_combined),
		"execution_penalty": float(modifiers.execution_penalty),
		"fatigue_amplification": float(modifiers.fatigue_amplification),
	}


static func build_setup_execution_profile(state: MatchSideState, action_id: StringName) -> Dictionary:
	var base_window := 22.0
	var marker_speed := 1.45
	var time_limit := 1.5
	if action_id == MatchSetupStateRules.PICK_OPPONENT_UP:
		base_window = 24.0
		marker_speed = 1.25
		time_limit = 1.7
	elif action_id in [
		MatchSetupStateRules.THROW_INTO_CORNER,
		MatchSetupStateRules.TURN_OPPONENT_IN_CORNER,
		MatchSetupStateRules.SEAT_OPPONENT_IN_CORNER,
	]:
		base_window = 20.0
	var modifiers := _difficulty_modifiers(state, null, true)
	var setup_attribute_profile := MatchAttributeModel.get_setup_modifier(state, null, action_id)
	var window := clampf(
		(base_window + float(modifiers.window) + float(setup_attribute_profile.get("window_modifier", 0.0))) * float(modifiers.execution_multiplier),
		6.0,
		30.0,
	)
	return {
		"interaction_type": InteractionType.HOLD_REPOSITION,
		"success_window": window,
		"gold_zone_scale": 0.25,
		"time_limit": time_limit,
		"marker_speed": marker_speed * float(modifiers.speed),
		"ai_success_chance": setup_execution_success_chance(state, action_id),
		"low_stamina_penalty": bool(modifiers.low_stamina),
		"exhaustion_band": int(modifiers.exhaustion_band),
		"exhaustion_combined": float(modifiers.exhaustion_combined),
		"execution_penalty": float(modifiers.execution_penalty),
		"fatigue_amplification": float(modifiers.fatigue_amplification),
	}


static func build_response_profile(
	attacker: MatchSideState,
	defender: MatchSideState,
	move: MoveResource = null,
	visible_player: bool = false,
	match_time_seconds: int = 0,
	setup_action: StringName = &"",
	target_resolution: Dictionary = {},
) -> Dictionary:
	return build_reversal_profile(
		attacker,
		defender,
		move,
		setup_action,
		visible_player,
		match_time_seconds,
		target_resolution,
	)


static func build_reversal_profile(
	attacker: MatchSideState,
	defender: MatchSideState,
	move: MoveResource = null,
	setup_action: StringName = &"",
	visible_player: bool = false,
	match_time_seconds: int = 0,
	target_resolution: Dictionary = {},
) -> Dictionary:
	var chance := reversal_success_chance(attacker, defender, move, setup_action, match_time_seconds, target_resolution)
	var visible_window := chance * 0.78 if visible_player else chance
	var heavy := _is_heavy_move(move)
	# Reversal targets are deliberately narrow, so give the player enough time
	# to read the prompt and watch at least one useful pass of the marker.
	var time_limit := 2.0
	if move != null and move.is_finisher:
		time_limit = 1.6
	elif move != null and _is_high_risk(move):
		time_limit = 1.75
	elif heavy:
		time_limit = 1.8
	return {
		"interaction_type": InteractionType.HOLD_REPOSITION,
		# With the one-eighth visual scale, a raw minimum of 24 produces an exact
		# three-percent rendered target instead of a near-hairline reversal zone.
		"success_window": clampf(visible_window, 24.0, 65.0),
		"gold_zone_scale": 1.0 / 8.0,
		"raw_zone_min": 24.0,
		"raw_zone_max": 65.0,
		"time_limit": time_limit,
		"marker_speed": 1.25,
		"ai_success_chance": chance,
		"reversal_chance": chance,
		"reversal_exhaustion_penalty": MatchExhaustionModel.reversal_penalty(defender),
		"attribute_reversal_modifier": float(MatchAttributeModel.get_reversal_modifier(attacker, defender, move, setup_action).get("modifier", 0.0)),
		"attacker_execution_penalty": MatchExhaustionModel.execution_penalty(
			attacker,
			MatchExhaustionModel.move_demand(
				move,
				attacker != null and attacker.is_signature_move(move),
				attacker != null and attacker.current_area == WrestlerResource.Area.LADDER,
			),
		),
		# Reversal success uses the exact rendered gold rectangle on every device.
		"edge_forgiveness": 0.0,
		"edge_forgiveness_pixels": 0.0,
		"touch_edge_forgiveness": 0.0,
		"touch_edge_forgiveness_pixels": 0.0,
		"binary_only": true,
		"one_way": true,
		"minimum_target_travel": 0.24,
	}


static func build_pin_profile(
	base_window: float,
	base_time: float,
	pressure: float,
	resistance: float,
	count: int = 0,
	defender: MatchSideState = null,
) -> Dictionary:
	var difference := resistance - pressure
	# Calculate the normal pressure-sensitive window first, then shrink that
	# result by the count-specific divisor. These are divisions of the calculated
	# width, not fixed fractions of the complete track.
	var calculated_window := clampf(
		base_window + clampf(difference * 0.30, -10.0, 46.0),
		6.0,
		80.0,
	)
	var divisor := 1.0
	match count:
		1:
			divisor = 4.0
		2:
			divisor = 5.0
		3:
			divisor = 6.0
	var exhaustion_penalty := MatchExhaustionModel.kickout_penalty(defender)
	var window := maxf(0.75, calculated_window / divisor)
	window = maxf(0.75, window * (1.0 - exhaustion_penalty / 100.0))
	# The count divisors are a player-facing timing challenge. They must not also
	# turn a fresh AI defender's survival roll into a single-digit chance. AI uses
	# the unshrunk pressure/resistance result, with resistance deliberately given
	# enough leverage for ordinary under-five-minute covers to remain rare.
	var ai_calculated_window := clampf(base_window + difference * 0.55, 6.0, 80.0)
	var ai_window := clampf(
		ai_calculated_window * (1.0 - exhaustion_penalty / 100.0),
		1.0,
		80.0,
	)
	var time_multiplier := clampf(1.0 + difference / 500.0, 0.82, 1.20)
	var count_speed := 1.30 if count == 3 else 1.20
	var speed_multiplier := clampf(1.0 - difference / 400.0, 0.80, 1.25) * count_speed
	return {
		"interaction_type": InteractionType.PIN_CONTROL_METER,
		"success_window": window,
		"gold_zone_scale": 1.0,
		# Pin targets intentionally need to render below the general Control
		# Meter's six-percent minimum. This override is pin-request-only.
		"raw_zone_min": 0.75,
		"raw_zone_max": 80.0,
		"zone_height_scale": 1.0,
		"zone_opacity": 1.0,
		"binary_only": true,
		"one_way": true,
		"minimum_target_travel": 0.24,
		"time_limit": base_time * 1.20 * time_multiplier,
		"marker_speed": speed_multiplier,
		"ai_success_chance": ai_window,
		"calculated_window": calculated_window,
		"ai_calculated_window": ai_calculated_window,
		"exhaustion_penalty": exhaustion_penalty,
	}


static func execution_success_chance(
	state: MatchSideState,
	move: MoveResource,
	interaction_type: int,
	environmental_followup: bool = false,
) -> float:
	if state == null or state.wrestler == null:
		return 50.0
	var impact := move.move_impact if move != null else 1
	var control_meter := interaction_type in [
		InteractionType.HOLD_POWER,
		InteractionType.HOLD_REPOSITION,
		InteractionType.SUBMISSION_LOCK_IN,
	]
	var chance := (
		(70.0 if control_meter else 72.0)
		+ (state.momentum - 50.0) * 0.12
		- float(maxi(0, impact - 5)) * 1.5
	)
	var attribute_profile := MatchAttributeModel.get_move_attribute_profile(
		state,
		null,
		move,
		{"environmental_followup": environmental_followup},
	)
	chance += float(attribute_profile.get("window_modifier", 0.0))
	if move != null and move.is_finisher:
		chance -= 8.0
	if move != null and _is_high_risk(move):
		chance -= 6.0
	chance += _compatibility_bonus(state.wrestler, move)
	var demand := MatchExhaustionModel.effective_move_demand(
		move,
		state.is_signature_move(move),
		state.current_area == WrestlerResource.Area.LADDER,
		environmental_followup,
	)
	chance *= MatchExhaustionModel.execution_multiplier(state, demand)
	return clampf(chance, 18.0, 92.0)


static func setup_execution_success_chance(state: MatchSideState, action_id: StringName = &"") -> float:
	if state == null or state.wrestler == null:
		return 50.0
	var chance := (
		70.0
		+ (state.momentum - 50.0) * 0.12
	)
	var setup_profile := MatchAttributeModel.get_setup_modifier(state, null, action_id)
	chance += float(setup_profile.get("window_modifier", 0.0))
	chance *= MatchExhaustionModel.execution_multiplier(state, MatchExhaustionModel.Demand.BASIC)
	return clampf(chance, 18.0, 92.0)


static func response_success_chance(
	attacker: MatchSideState,
	defender: MatchSideState,
	move: MoveResource = null,
	match_time_seconds: int = 0,
	setup_action: StringName = &"",
	target_resolution: Dictionary = {},
) -> float:
	return reversal_success_chance(attacker, defender, move, setup_action, match_time_seconds, target_resolution)


static func reversal_success_chance(
	attacker: MatchSideState,
	defender: MatchSideState,
	move: MoveResource = null,
	setup_action: StringName = &"",
	match_time_seconds: int = 0,
	target_resolution: Dictionary = {},
) -> float:
	if attacker == null or defender == null or defender.wrestler == null:
		return 22.0
	var chance := (
		_taunt_interruption_base(attacker.current_area, defender.current_position)
		if setup_action == MatchSetupStateRules.TAUNT
		else _base_reversal_chance(move, setup_action)
	)

	if defender.momentum >= 70.0:
		chance += 10.0
	elif defender.momentum >= 40.0:
		chance += 5.0
	elif defender.momentum < 20.0:
		chance -= 5.0

	if attacker.momentum >= 70.0:
		chance -= 8.0
	elif attacker.momentum >= 40.0:
		chance -= 4.0
	elif attacker.momentum < 20.0:
		chance += 4.0
	# Attacker execution now resolves separately. Do not fold its exhaustion
	# penalty into the defender's reversal chance as well.

	if move != null:
		if move.move_impact <= 3:
			chance += 4.0
		elif move.move_impact >= 9:
			chance -= 8.0
		elif move.move_impact >= 7:
			chance -= 4.0
		if move.is_finisher:
			chance -= 10.0
		if _is_high_risk(move):
			chance += 10.0
		if attacker.last_attempted_move_matches(move):
			chance += 10.0
		if attacker.recent_move_type_count(move.move_type, 5) >= 3:
			chance += 6.0
		if attacker.setup_pattern_repeats(move):
			chance += 5.0
		var target_hp := (
			MoveTargetResolver.target_hp(defender, target_resolution)
			if not target_resolution.is_empty()
			else defender.average_target_hp(move.move_target_parts)
		)
		if not target_resolution.is_empty():
			var story_part := int(target_resolution.get("story_part", MoveResource.MoveTargetParts.NONE))
			if MoveTargetResolver.is_limb_focus(story_part):
				# Different moves aimed at the same limb are still predictable. This
				# rewards a coherent targeting plan while giving a defender a modest
				# adaptation bonus on the third and fifth recent attempts.
				var recent_targeting := attacker.recent_target_part_count(story_part, 5)
				if recent_targeting >= 4:
					chance += 12.0
				elif recent_targeting >= 2:
					chance += 7.0
		if target_hp < 25.0:
			chance -= 10.0
		elif target_hp < 50.0:
			chance -= 5.0
		if attacker.wrestler != null and (
			_class_is_compatible(attacker.wrestler, move)
			or _inferred_class_compatible(attacker.wrestler, move)
		):
			chance -= 5.0
	if WrestlerResource.WrestlerClass.TECHNICIAN in defender.wrestler.wrestler_class:
		chance += 5.0
	var attribute_reversal_profile := MatchAttributeModel.get_reversal_modifier(
		attacker,
		defender,
		move,
		setup_action,
	)
	chance += float(attribute_reversal_profile.get("modifier", 0.0))
	if (
		defender.current_position in [WrestlerResource.Position.GROUNDED, WrestlerResource.Position.SEATED, WrestlerResource.Position.KNEELING]
		or defender.current_area == WrestlerResource.Area.CORNER
		or defender.current_motion_state == WrestlerResource.MotionState.ROPE_REBOUND
	):
		chance -= 3.0
	# Late-match recovery strength belongs to neutral recovery and finish
	# pressure, not reversal odds. Exhaustion still affects the defender through
	# the shared reversal penalty below.
	chance -= defender.bleeding_resistance_penalty()
	chance *= 1.0 - MatchExhaustionModel.reversal_penalty(defender) / 100.0
	return clampf(chance, 5.0, 65.0)


static func _base_reversal_chance(move: MoveResource, setup_action: StringName) -> float:
	if not setup_action.is_empty():
		if setup_action == MatchSetupStateRules.PICK_OPPONENT_UP:
			return 30.0
		if setup_action in [
			MatchSetupStateRules.IRISH_WHIP,
			MatchSetupStateRules.THROW_INTO_CORNER,
			MatchSetupStateRules.SEND_OPPONENT_OUTSIDE,
			MatchSetupStateRules.CALL_OPPONENT_OUTSIDE,
			MatchSetupStateRules.TAKE_FIGHT_OUTSIDE,
		]:
			return 28.0
		return 25.0
	if move == null:
		return 22.0
	if move.is_finisher:
		return 12.0
	if _is_high_risk(move):
		return 28.0
	return 18.0 if _is_heavy_move(move) else 22.0


static func _taunt_interruption_base(attacker_area: int, defender_position: int) -> float:
	var defender_grounded := defender_position == WrestlerResource.Position.GROUNDED
	match attacker_area:
		WrestlerResource.Area.TOP_ROPE:
			return 28.0 if defender_grounded else 42.0
		WrestlerResource.Area.APRON:
			return 23.0 if defender_grounded else 35.0
	return 18.0 if defender_grounded else 30.0


static func _is_heavy_move(move: MoveResource) -> bool:
	return move != null and (
		move.move_impact >= 7
		or (move.is_strike and move.strike_weight == MoveResource.StrikeWeight.STRIKE_HEAVY)
	)


static func build_late_match_profile(match_time_seconds: int) -> Dictionary:
	if match_time_seconds >= 2100:
		return {
			"finish_pressure": 45.0,
			"recovery_penalty": 25.0,
			"control_threshold": 4.0,
			"allow_laboured": true,
			"ai_finish_bonus": 35.0,
			"movement_setup_penalty": 50.0,
		}
	if match_time_seconds >= 1500:
		return {
			"finish_pressure": 30.0,
			"recovery_penalty": 15.0,
			"control_threshold": 8.0,
			"allow_laboured": true,
			"ai_finish_bonus": 20.0,
			"movement_setup_penalty": 20.0,
		}
	if match_time_seconds >= 900:
		return {
			"finish_pressure": 15.0,
			"recovery_penalty": 8.0,
			"control_threshold": 12.0,
			"allow_laboured": false,
			"ai_finish_bonus": 8.0,
			"movement_setup_penalty": 0.0,
		}
	return {
		"finish_pressure": 0.0,
		"recovery_penalty": 0.0,
		"control_threshold": 15.0,
		"allow_laboured": false,
		"ai_finish_bonus": 0.0,
		"movement_setup_penalty": 0.0,
	}


static func build_submission_context(
	attacker: MatchSideState,
	defender: MatchSideState,
	move: MoveResource,
	match_time_seconds: int,
	contested_lock: bool,
	squash_context: bool = false,
	target_resolution: Dictionary = {},
) -> Dictionary:
	if target_resolution.is_empty():
		target_resolution = MoveTargetResolver.resolve(move, MoveResource.MoveTargetParts.NONE, defender)
	var target_hp := MoveTargetResolver.target_hp(defender, target_resolution)
	var time_resistance := 0.0
	var attacker_pressure_bonus := 0.0
	var tap_out_threshold := 90.0
	if match_time_seconds < 300:
		time_resistance = 35.0
		tap_out_threshold = 96.0
	elif match_time_seconds < 600:
		time_resistance = 18.0
		tap_out_threshold = 93.0
	elif match_time_seconds >= 900:
		var late_profile := build_late_match_profile(match_time_seconds)
		if match_time_seconds >= 2100:
			attacker_pressure_bonus = float(late_profile.finish_pressure)
			tap_out_threshold = 82.0
		elif match_time_seconds >= 1500:
			attacker_pressure_bonus = float(late_profile.finish_pressure)
			tap_out_threshold = 85.0
		else:
			# At 15â€“24 minutes submissions are dangerous without the tug
			# immediately becoming one-sided. Full escalation begins at 25:00.
			attacker_pressure_bonus = 10.0
			tap_out_threshold = 89.0
	var body_resistance := 0.0
	if target_hp >= 80.0:
		body_resistance = 30.0
		if not move.is_finisher:
			body_resistance = 35.0
			tap_out_threshold = minf(98.0, tap_out_threshold + 2.0)
	elif target_hp >= 60.0:
		body_resistance = 15.0
	elif target_hp >= 40.0 and not move.is_finisher:
		# Moderate damage should create danger, not an automatic finish. Repeated
		# work, condition and specialist advantages can earn this resistance back.
		body_resistance = 10.0
	elif target_hp < 20.0:
		attacker_pressure_bonus += 30.0
	elif target_hp < 40.0:
		attacker_pressure_bonus += 15.0
	var story_part := int(target_resolution.get("story_part", MoveResource.MoveTargetParts.BODY))
	var targeted_attacks := int(attacker.target_attack_counts.get(story_part, 0))
	if targeted_attacks >= 5:
		attacker_pressure_bonus += 8.0
	elif targeted_attacks >= 3:
		attacker_pressure_bonus += 4.0
	if attacker.wrestler != null and WrestlerResource.WrestlerClass.TECHNICIAN in attacker.wrestler.wrestler_class:
		attacker_pressure_bonus += 4.0
	if attacker.momentum >= 65.0:
		attacker_pressure_bonus += 4.0
	if move.is_finisher:
		time_resistance *= 0.5
		tap_out_threshold = minf(tap_out_threshold, 92.0)
	if squash_context:
		time_resistance = 0.0
	var resistance_bonus := time_resistance + body_resistance
	var contextual_start_marker := submission_start_marker(attacker, defender, move, contested_lock, target_resolution)
	contextual_start_marker += (attacker_pressure_bonus - resistance_bonus) * 0.18
	var attacker_score := submission_pressure_score(attacker, defender, move, true, target_resolution) + attacker_pressure_bonus
	var defender_score := submission_pressure_score(defender, defender, move, false, target_resolution) + resistance_bonus - defender.bleeding_resistance_penalty()
	var attribute_submission_profile := MatchAttributeModel.get_submission_modifiers(
		attacker,
		defender,
		move,
		target_resolution,
	)
	attacker_score += float(attribute_submission_profile.get("attack_score_modifier", 0.0))
	defender_score += float(attribute_submission_profile.get("defence_score_modifier", 0.0))
	var escape_penalty := MatchExhaustionModel.submission_escape_penalty(defender)
	return {
		# Every struggle begins from a visibly neutral centre. Damage, condition,
		# time, finishers, and contested lock-ins affect pressure and thresholds,
		# rather than granting free track position before the struggle starts.
		"start_marker": 50.0,
		"contextual_start_marker": clampf(contextual_start_marker, 15.0, 85.0),
		"attacker_score": clampf(attacker_score, 5.0, 100.0),
		"defender_score": clampf(defender_score, 5.0, 100.0),
		"tap_out_threshold": clampf(tap_out_threshold, 80.0, 98.0),
		"escape_threshold": 10.0,
		"target_hp": target_hp,
		"pressure_bonus": attacker_pressure_bonus,
		"resistance_bonus": resistance_bonus,
		"healthy_target_resistance_bonus": 5.0 if target_hp >= 80.0 and not move.is_finisher else 0.0,
		"attribute_submission_attack": float(attribute_submission_profile.get("attack_score_modifier", 0.0)),
		"attribute_submission_defence": float(attribute_submission_profile.get("defence_score_modifier", 0.0)),
		"squash_context": squash_context,
		"submission_escape_penalty": escape_penalty,
	}


static func submission_start_marker(
	attacker: MatchSideState,
	defender: MatchSideState,
	move: MoveResource,
	contested_lock: bool,
	target_resolution: Dictionary = {},
) -> float:
	var marker := 50.0
	if target_resolution.is_empty():
		target_resolution = MoveTargetResolver.resolve(move, MoveResource.MoveTargetParts.NONE, defender)
	var target_hp := MoveTargetResolver.target_hp(defender, target_resolution)
	if target_hp >= 80.0:
		marker -= 15.0
	elif target_hp >= 60.0:
		marker -= 5.0
	elif target_hp < 20.0:
		marker += 25.0
	elif target_hp < 40.0:
		marker += 12.0
	if move.is_finisher:
		marker += 20.0
	if defender.momentum > 70.0:
		marker -= 12.0
	if attacker.momentum > 70.0:
		marker += 12.0
	if contested_lock:
		marker -= 15.0
	return clampf(marker, 15.0, 85.0)


static func submission_pressure_score(
	state: MatchSideState,
	opponent: MatchSideState,
	move: MoveResource,
	attacking: bool,
	target_resolution: Dictionary = {},
) -> float:
	if state == null or state.wrestler == null:
		return 50.0
	if target_resolution.is_empty():
		target_resolution = MoveTargetResolver.resolve(move, MoveResource.MoveTargetParts.NONE, opponent)
	var target_hp := MoveTargetResolver.target_hp(opponent, target_resolution)
	if attacking:
		var attacking_score := (
			20.0
			+ state.wrestler.skill * 0.35
			+ state.momentum * 0.20
			+ (100.0 - target_hp) * 0.25
			+ float(move.move_impact) * 2.0
			+ (15.0 if move.is_finisher else 0.0)
		)
		var demand := MatchExhaustionModel.Demand.EXPLOSIVE if move.is_finisher else MatchExhaustionModel.Demand.STANDARD
		attacking_score *= MatchExhaustionModel.execution_multiplier(state, demand)
		return clampf(attacking_score, 5.0, 100.0)
	var defender_score := (
		20.0
		+ state.wrestler.skill * 0.30
		+ state.momentum * 0.20
		+ target_hp * 0.15
	)
	defender_score *= 1.0 - MatchExhaustionModel.submission_escape_penalty(state) / 100.0
	return clampf(defender_score, 5.0, 100.0)


static func _difficulty_modifiers(
	state: MatchSideState,
	move: MoveResource,
	control_meter: bool,
	environmental_followup: bool = false,
) -> Dictionary:
	if state == null:
		return {
			"window": 0.0,
			"speed": 1.0,
			"low_stamina": false,
			"execution_multiplier": 1.0,
			"execution_penalty": 0.0,
			"fatigue_amplification": 1.0,
			"exhaustion_combined": 0.0,
			"exhaustion_band": MatchExhaustionModel.ExhaustionBand.FRESH,
		}
	var window := 0.0
	var speed_add := 0.0
	var low_stamina := state.stamina_percent() < 50.0
	var high_risk := _is_high_risk(move)
	var finisher := move != null and move.is_finisher
	if state.momentum >= 90.0:
		window += 10.0
		speed_add -= 0.08
	elif state.momentum >= 70.0:
		window += 6.0
		speed_add -= 0.05
	if move != null:
		if move.move_impact >= 9:
			window -= 10.0
			speed_add += 0.10
		elif move.move_impact >= 7:
			window -= 5.0
			speed_add += 0.05
		window += _compatibility_bonus(state.wrestler, move)
		if control_meter and finisher:
			window -= 8.0
			speed_add += 0.12
		if control_meter and high_risk:
			window -= 8.0
			speed_add += 0.12
		var attribute_profile := MatchAttributeModel.get_move_attribute_profile(
			state,
			null,
			move,
			{"environmental_followup": environmental_followup},
		)
		window += float(attribute_profile.get("window_modifier", 0.0))
		speed_add += float(attribute_profile.get("speed_multiplier", 1.0)) - 1.0
	var demand := MatchExhaustionModel.effective_move_demand(
		move,
		state.is_signature_move(move),
		state.current_area == WrestlerResource.Area.LADDER,
		environmental_followup,
	)
	var execution_penalty := MatchExhaustionModel.execution_penalty(state, demand)
	return {
		"window": window,
		"speed": clampf(1.0 + speed_add, 0.65, 2.0),
		"low_stamina": low_stamina,
		"execution_multiplier": 1.0 - execution_penalty / 100.0,
		"execution_penalty": execution_penalty,
		"fatigue_amplification": MatchExhaustionModel.fatigue_amplification(state),
		"exhaustion_combined": MatchExhaustionModel.combined_exhaustion(state),
		"exhaustion_band": MatchExhaustionModel.exhaustion_band(state),
	}


static func _condition_chance_penalty(state: MatchSideState, move: MoveResource) -> float:
	if state == null:
		return 0.0
	var demand := MatchExhaustionModel.move_demand(
		move,
		state.is_signature_move(move),
		state.current_area == WrestlerResource.Area.LADDER,
	)
	return -MatchExhaustionModel.execution_penalty(state, demand)


static func _compatibility_bonus(wrestler: WrestlerResource, move: MoveResource) -> float:
	if wrestler == null or move == null:
		return 0.0
	if _class_is_compatible(wrestler, move):
		return 8.0
	return 5.0 if _inferred_class_compatible(wrestler, move) else 0.0


static func _inferred_class_compatible(wrestler: WrestlerResource, move: MoveResource) -> bool:
	if WrestlerResource.WrestlerClass.STRIKER in wrestler.wrestler_class and move.is_strike:
		return true
	if WrestlerResource.WrestlerClass.TECHNICIAN in wrestler.wrestler_class and (
		move.is_submission or move.move_type in [MoveResource.MoveType.SUBMISSION, MoveResource.MoveType.GRAPPLE]
	):
		return true
	if WrestlerResource.WrestlerClass.HIGH_FLYER in wrestler.wrestler_class and _is_high_risk(move):
		return true
	return (
		WrestlerResource.WrestlerClass.POWERHOUSE in wrestler.wrestler_class
		and not move.is_strike
		and not move.is_submission
		and move.move_impact >= 5
	)


static func _execution_window_modifier(state: MatchSideState, move: MoveResource, interaction_type: int) -> float:
	if state == null:
		return 0.0
	var relevant := _relevant_attribute(state, interaction_type)
	var impact := move.move_impact if move != null else 1
	var compatible := move != null and state.wrestler != null and _class_is_compatible(state.wrestler, move)
	return _condition_window_modifier(state, relevant, impact, compatible)


static func _condition_window_modifier(
	state: MatchSideState,
	relevant: float,
	impact: int,
	compatible: bool,
) -> float:
	return (
		(relevant - 70.0) * 0.10
		+ (state.momentum - 50.0) * 0.04
		- float(maxi(0, impact - 5)) * 0.70
		+ (2.0 if compatible else 0.0)
	)


static func _relevant_attribute(state: MatchSideState, interaction_type: int) -> float:
	if state == null or state.wrestler == null:
		return 50.0
	match interaction_type:
		InteractionType.TIMING_STRIKE:
			return state.wrestler.striking
		InteractionType.TIMING_AERIAL:
			return (state.wrestler.speed + state.wrestler.skill) * 0.5
		InteractionType.SUBMISSION_LOCK_IN:
			return state.wrestler.skill
	return (state.wrestler.strength + state.wrestler.skill) * 0.5


static func _setup_attribute(state: MatchSideState) -> float:
	if state == null or state.wrestler == null:
		return 50.0
	return (state.wrestler.strength + state.wrestler.skill) * 0.5


static func _class_is_compatible(wrestler: WrestlerResource, move: MoveResource) -> bool:
	if wrestler == null or move == null:
		return false
	for wrestler_class in wrestler.wrestler_class:
		if move.class_preferrence.has(wrestler_class):
			return true
	return false


static func _is_high_risk(move: MoveResource) -> bool:
	return is_high_risk_move(move)


static func is_high_risk_move(move: MoveResource) -> bool:
	if move == null:
		return false
	if move.move_type in [
		MoveResource.MoveType.AERIAL,
		MoveResource.MoveType.SPRINGBOARD,
	] or (
		move.required_attacker_area_mode == MoveResource.AreaRequirementMode.SPECIFIC
		and move.required_attacker_area in [WrestlerResource.Area.TOP_ROPE, WrestlerResource.Area.APRON]
	):
		return true
	if move.move_type != MoveResource.MoveType.RUNNING and move.required_attacker_motion_state not in [WrestlerResource.MotionState.RUNNING, WrestlerResource.MotionState.ROPE_REBOUND]:
		return false
	var normalized_name := move.move_name.to_lower()
	for term in AERIAL_TERMS:
		if normalized_name.contains(term):
			return true
	return false
