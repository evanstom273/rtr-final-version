extends RefCounted
class_name MatchAttributeModel

const NEUTRAL_ATTRIBUTE := 70.0
const ATTRIBUTE_RANGE := 30.0


static func attribute_delta(value: float) -> float:
	return clampf((value - NEUTRAL_ATTRIBUTE) / ATTRIBUTE_RANGE, -1.0, 1.0)


static func stat(wrestler: WrestlerResource, stat_name: StringName) -> float:
	if wrestler == null:
		return NEUTRAL_ATTRIBUTE
	match stat_name:
		&"strength":
			return wrestler.strength
		&"speed":
			return wrestler.speed
		&"skill":
			return wrestler.skill
		&"striking":
			return wrestler.striking
		&"charisma":
			return wrestler.charisma
	return NEUTRAL_ATTRIBUTE


static func wrestler_delta(wrestler: WrestlerResource, stat_name: StringName) -> float:
	return attribute_delta(stat(wrestler, stat_name))


static func state_wrestler(state: MatchSideState) -> WrestlerResource:
	return state.wrestler if state != null else null


static func get_move_attribute_profile(
	attacker: MatchSideState,
	defender: MatchSideState,
	move: MoveResource,
	context: Dictionary = {},
) -> Dictionary:
	var wrestler: WrestlerResource = state_wrestler(attacker)
	var environmental: bool = bool(context.get("environmental_followup", false))
	var ladder_variant: bool = bool(context.get("ladder_variant", false))
	var strength_delta: float = wrestler_delta(wrestler, &"strength")
	var speed_delta: float = wrestler_delta(wrestler, &"speed")
	var skill_delta: float = wrestler_delta(wrestler, &"skill")
	var striking_delta: float = wrestler_delta(wrestler, &"striking")
	var damage_multiplier: float = 1.0
	var window_modifier: float = 0.0
	var speed_multiplier: float = 1.0
	var control_modifier: float = 0.0
	var notes: Array[String] = []
	if move != null:
		if move.is_strike or move.move_type == MoveResource.MoveType.STRIKE:
			damage_multiplier *= 1.0 + striking_delta * 0.10
			window_modifier += striking_delta * 4.0
			notes.append("striking")
		elif move.move_type == MoveResource.MoveType.GRAPPLE:
			damage_multiplier *= 1.0 + strength_delta * 0.08
			window_modifier += (strength_delta * 2.0) + (skill_delta * 2.0)
			control_modifier += skill_delta * 4.0
			notes.append("strength/skill")
		if is_speed_move(move):
			damage_multiplier *= 1.0 + speed_delta * 0.07
			window_modifier += speed_delta * 5.0
			speed_multiplier *= 1.0 - speed_delta * 0.05
			notes.append("speed")
		if move.is_submission or move.move_type == MoveResource.MoveType.SUBMISSION:
			window_modifier += skill_delta * 4.0
			control_modifier += skill_delta * 4.0
			notes.append("submission skill")
		if move.move_type == MoveResource.MoveType.WEAPON:
			damage_multiplier *= 1.0 + strength_delta * 0.06 + striking_delta * 0.04
			window_modifier += strength_delta * 2.0 + striking_delta * 2.0
			notes.append("weapon strength/striking")
		if environmental or move.move_type == MoveResource.MoveType.ENVIRONMENTAL:
			damage_multiplier *= 1.0 + strength_delta * 0.06
			window_modifier += strength_delta * 4.0
			notes.append("environmental strength")
		if ladder_variant:
			damage_multiplier *= 1.0 + speed_delta * 0.05
			window_modifier += speed_delta * 3.0
			notes.append("ladder speed")
	damage_multiplier = clampf(damage_multiplier, 0.85, 1.15)
	speed_multiplier = clampf(speed_multiplier, 0.90, 1.10)
	return {
		"damage_multiplier": damage_multiplier,
		"window_modifier": clampf(window_modifier, -8.0, 8.0),
		"speed_multiplier": speed_multiplier,
		"control_modifier": clampf(control_modifier, -4.0, 4.0),
		"strength_delta": strength_delta,
		"speed_delta": speed_delta,
		"skill_delta": skill_delta,
		"striking_delta": striking_delta,
		"charisma_delta": wrestler_delta(wrestler, &"charisma"),
		"notes": ", ".join(notes) if not notes.is_empty() else "neutral",
	}


static func get_reversal_modifier(
	attacker: MatchSideState,
	defender: MatchSideState,
	move: MoveResource,
	setup_action: StringName = &"",
) -> Dictionary:
	var defender_skill_delta: float = wrestler_delta(state_wrestler(defender), &"skill")
	var attacker_striking_delta: float = wrestler_delta(state_wrestler(attacker), &"striking")
	var attacker_speed_delta: float = wrestler_delta(state_wrestler(attacker), &"speed")
	var attacker_strength_delta: float = wrestler_delta(state_wrestler(attacker), &"strength")
	var modifier: float = defender_skill_delta * 6.0
	var attacker_modifier: float = 0.0
	if setup_action == MatchSetupStateRules.TAUNT:
		var charisma_delta: float = wrestler_delta(state_wrestler(attacker), &"charisma")
		attacker_modifier = -charisma_delta * 6.0
	elif move != null:
		if move.is_strike or move.move_type == MoveResource.MoveType.STRIKE:
			attacker_modifier = -attacker_striking_delta * 6.0
		elif is_speed_move(move):
			attacker_modifier = -attacker_speed_delta * 4.0
		elif move.move_type in [MoveResource.MoveType.GRAPPLE, MoveResource.MoveType.WEAPON, MoveResource.MoveType.ENVIRONMENTAL]:
			attacker_modifier = -attacker_strength_delta * 3.0
	modifier += attacker_modifier
	return {
		"modifier": clampf(modifier, -10.0, 10.0),
		"defender_skill_modifier": defender_skill_delta * 6.0,
		"attacker_difficulty_modifier": attacker_modifier,
	}


static func get_submission_modifiers(
	attacker: MatchSideState,
	defender: MatchSideState,
	move: MoveResource,
	target_resolution: Dictionary = {},
) -> Dictionary:
	var attack_delta: float = wrestler_delta(state_wrestler(attacker), &"skill")
	var defence_delta: float = wrestler_delta(state_wrestler(defender), &"skill")
	return {
		"attack_score_modifier": attack_delta * 8.0,
		"defence_score_modifier": defence_delta * 8.0,
	}


static func get_setup_modifier(actor: MatchSideState, target: MatchSideState, action_id: StringName) -> Dictionary:
	var wrestler: WrestlerResource = state_wrestler(actor)
	var strength_delta: float = wrestler_delta(wrestler, &"strength")
	var speed_delta: float = wrestler_delta(wrestler, &"speed")
	var skill_delta: float = wrestler_delta(wrestler, &"skill")
	var window_modifier: float = 0.0
	var recovery_modifier: float = 0.0
	var scoring_modifier: float = 0.0
	if is_movement_action(action_id):
		window_modifier += speed_delta * 3.0
		recovery_modifier += speed_delta * 5.0
		scoring_modifier += speed_delta * 8.0
	elif is_heavy_positioning_action(action_id):
		window_modifier += strength_delta * 4.0
		scoring_modifier += strength_delta * 8.0
	elif is_technical_setup_action(action_id):
		window_modifier += skill_delta * 4.0
		scoring_modifier += skill_delta * 8.0
	else:
		window_modifier += skill_delta * 2.0
	return {
		"window_modifier": clampf(window_modifier, -5.0, 5.0),
		"recovery_modifier": clampf(recovery_modifier, -5.0, 5.0),
		"scoring_modifier": clampf(scoring_modifier, -10.0, 10.0),
	}


static func get_taunt_profile(actor: MatchSideState, target: MatchSideState) -> Dictionary:
	var charisma_delta: float = wrestler_delta(state_wrestler(actor), &"charisma")
	return {
		"interruption_modifier": -charisma_delta * 6.0,
		"stamina_multiplier": clampf(1.0 + charisma_delta * 0.10, 0.90, 1.10),
		"momentum_bonus": int(clampi(roundi(charisma_delta * 2.0), -2, 2)),
		"ai_score_modifier": charisma_delta * 10.0,
	}


static func get_debug_summary(profile: Dictionary) -> String:
	return "damage x%.3f | window %+.1f | speed x%.2f | control %+.1f | %s" % [
		float(profile.get("damage_multiplier", 1.0)),
		float(profile.get("window_modifier", 0.0)),
		float(profile.get("speed_multiplier", 1.0)),
		float(profile.get("control_modifier", 0.0)),
		str(profile.get("notes", "neutral")),
	]


static func is_speed_move(move: MoveResource) -> bool:
	if move == null:
		return false
	return (
		move.move_type in [MoveResource.MoveType.AERIAL, MoveResource.MoveType.SPRINGBOARD, MoveResource.MoveType.RUNNING]
		or move.required_attacker_motion_state in [WrestlerResource.MotionState.RUNNING, WrestlerResource.MotionState.ROPE_REBOUND]
		or move.required_target_motion_state == WrestlerResource.MotionState.ROPE_REBOUND
		or move.required_attacker_area in [WrestlerResource.Area.TOP_ROPE, WrestlerResource.Area.APRON, WrestlerResource.Area.LADDER]
	)


static func is_movement_action(action_id: StringName) -> bool:
	return action_id in [
		MatchSetupStateRules.START_RUNNING,
		MatchSetupStateRules.STOP_RUNNING,
		MatchSetupStateRules.REGAIN_FOOTING,
		MatchSetupStateRules.CLIMB_TOP_ROPE,
		MatchSetupStateRules.CLIMB_DOWN,
		MatchSetupStateRules.PREPARE_SPRINGBOARD,
		MatchSetupStateRules.RETURN_TO_RING,
		MatchSetupStateRules.STEP_TO_ROPES,
		MatchSetupStateRules.LEAVE_ROPES,
		MatchSetupStateRules.EXIT_RING,
		MatchSetupStateRules.BRING_MATCH_BACK_TO_RING,
		MatchSetupStateRules.BRING_OPPONENT_INTO_RING,
		MatchSetupStateRules.RETURN_FROM_RAMP,
		MatchSetupStateRules.FIGHT_UP_RAMP,
		MatchSetupStateRules.CLIMB_LADDER,
		MatchSetupStateRules.CLIMB_LADDER_TOP,
	]


static func is_heavy_positioning_action(action_id: StringName) -> bool:
	return action_id in [
		MatchSetupStateRules.PICK_OPPONENT_UP,
		MatchSetupStateRules.IRISH_WHIP,
		MatchSetupStateRules.THROW_INTO_CORNER,
		MatchSetupStateRules.SEND_OPPONENT_OUTSIDE,
		MatchSetupStateRules.CALL_OPPONENT_OUTSIDE,
		MatchSetupStateRules.TAKE_FIGHT_OUTSIDE,
		MatchSetupStateRules.POSITION_AT_TABLE,
		MatchSetupStateRules.LAY_ON_TABLE,
		MatchSetupStateRules.POSITION_AT_CORNER_TABLE,
		MatchSetupStateRules.POSITION_OVER_THUMBTACKS,
	]


static func is_technical_setup_action(action_id: StringName) -> bool:
	return action_id in [
		MatchSetupStateRules.GET_BEHIND_OPPONENT,
		MatchSetupStateRules.TURN_OPPONENT_FACE_UP,
		MatchSetupStateRules.TURN_OPPONENT_FACE_DOWN,
		MatchSetupStateRules.SIT_OPPONENT_UP_FRONT,
		MatchSetupStateRules.SIT_OPPONENT_UP_BACK,
		MatchSetupStateRules.PULL_OPPONENT_TO_KNEES_FRONT,
		MatchSetupStateRules.PULL_OPPONENT_TO_KNEES_BACK,
		MatchSetupStateRules.TURN_OPPONENT_IN_CORNER,
		MatchSetupStateRules.SEAT_OPPONENT_IN_CORNER,
		MatchSetupStateRules.LEAN_OPPONENT_ON_ROPES_FRONT,
		MatchSetupStateRules.LEAN_OPPONENT_ON_ROPES_BACK,
		MatchSetupStateRules.DRAPE_OPPONENT_ON_ROPES_FRONT,
		MatchSetupStateRules.DRAPE_OPPONENT_ON_ROPES_BACK,
		MatchSetupStateRules.PLACE_OPPONENT_ON_APRON_FRONT,
		MatchSetupStateRules.PLACE_OPPONENT_ON_APRON_BACK,
		MatchSetupStateRules.SET_OPPONENT_ON_TOP_ROPE_FRONT,
		MatchSetupStateRules.SET_OPPONENT_ON_TOP_ROPE_BACK,
	]
