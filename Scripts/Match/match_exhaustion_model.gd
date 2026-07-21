extends RefCounted
class_name MatchExhaustionModel

## Central stamina/fatigue tuning. All percentages returned by this model are
## relative reductions, not automatic failure chances.

enum Demand { BASIC, STANDARD, EXPLOSIVE }
enum ExhaustionBand { FRESH, WINDED, TIRED, EXHAUSTED, SPENT }

## Catch Breath thresholds and recovery are percentages of the wrestler's
## authored stamina capacity, rather than absolute points on a universal tank.
const CATCH_BREATH_STAMINA_THRESHOLD := 60.0
const CATCH_BREATH_BASE_RECOVERY := 18.0
const CATCH_BREATH_COOLDOWN_SECONDS := 90

const BASIC_EXECUTION_CAP := 15.0
const STANDARD_EXECUTION_CAP := 22.0
const EXPLOSIVE_EXECUTION_CAP := 35.0
const REVERSAL_PENALTY_CAP := 20.0
const KICKOUT_PENALTY_CAP := 32.0
const SUBMISSION_ESCAPE_PENALTY_CAP := 35.0
const RECOVERY_DELAY_CAP := 35.0


static func stamina_ratio(state: MatchSideState) -> float:
	return state.stamina_ratio() if state != null else 1.0


static func stamina_percent(state: MatchSideState) -> float:
	return stamina_ratio(state) * 100.0


static func catch_breath_recovery(state: MatchSideState) -> float:
	if state == null:
		return 0.0
	return (
		state.max_stamina
		* CATCH_BREATH_BASE_RECOVERY
		/ 100.0
		* stamina_recovery_multiplier(state)
	)


static func fatigue_ratio(state: MatchSideState) -> float:
	return clampf(state.fatigue / 100.0, 0.0, 1.0) if state != null else 0.0


static func combined_exhaustion(state: MatchSideState) -> float:
	if state == null:
		return 0.0
	var depletion := 1.0 - stamina_ratio(state)
	var wear := fatigue_ratio(state)
	return clampf(0.65 * depletion + 0.35 * wear + 0.25 * depletion * wear, 0.0, 1.0)


static func exhaustion_band(state: MatchSideState) -> int:
	var severity := combined_exhaustion(state)
	if severity < 0.20:
		return ExhaustionBand.FRESH
	if severity < 0.45:
		return ExhaustionBand.WINDED
	if severity < 0.70:
		return ExhaustionBand.TIRED
	if severity < 0.90:
		return ExhaustionBand.EXHAUSTED
	return ExhaustionBand.SPENT


static func exhaustion_band_label(state: MatchSideState) -> String:
	match exhaustion_band(state):
		ExhaustionBand.WINDED:
			return "Winded"
		ExhaustionBand.TIRED:
			return "Tired"
		ExhaustionBand.EXHAUSTED:
			return "Exhausted"
		ExhaustionBand.SPENT:
			return "Spent"
	return "Fresh"


static func move_demand(
	move: MoveResource,
	is_signature: bool = false,
	is_ladder_variant: bool = false,
) -> int:
	if move == null:
		return Demand.BASIC
	if (
		is_signature
		or is_ladder_variant
		or move.is_finisher
		or move.move_type in [
			MoveResource.MoveType.AERIAL,
			MoveResource.MoveType.SPRINGBOARD,
			MoveResource.MoveType.RUNNING,
		]
		or move.required_attacker_motion_state in [
			WrestlerResource.MotionState.RUNNING,
			WrestlerResource.MotionState.ROPE_REBOUND,
		]
		or move.required_target_motion_state == WrestlerResource.MotionState.ROPE_REBOUND
		or move.required_attacker_position in [WrestlerResource.Position.PERCHED, WrestlerResource.Position.CLIMBING]
		or move.required_attacker_area in [WrestlerResource.Area.TOP_ROPE, WrestlerResource.Area.LADDER]
		or (move.move_type == MoveResource.MoveType.GRAPPLE and move.move_impact >= 8)
		or (move.move_type == MoveResource.MoveType.WEAPON and move.move_impact >= 7)
	):
		return Demand.EXPLOSIVE
	if move.move_impact <= 3 and move.move_type in [MoveResource.MoveType.STRIKE, MoveResource.MoveType.GRAPPLE]:
		return Demand.BASIC
	return Demand.STANDARD


static func effective_move_demand(
	move: MoveResource,
	is_signature: bool = false,
	is_ladder_variant: bool = false,
	environmental_followup: bool = false,
) -> int:
	if environmental_followup:
		return Demand.EXPLOSIVE
	return move_demand(move, is_signature, is_ladder_variant)


static func demand_label(demand: int) -> String:
	match demand:
		Demand.BASIC:
			return "Basic"
		Demand.EXPLOSIVE:
			return "Explosive"
	return "Standard"


static func execution_penalty(
	state: MatchSideState,
	demand: int,
) -> float:
	if state == null:
		return 0.0
	var base_values := PackedFloat32Array([0.0, 5.0, 10.0, 15.0])
	var cap := STANDARD_EXECUTION_CAP
	match demand:
		Demand.BASIC:
			base_values = PackedFloat32Array([0.0, 3.0, 6.0, 10.0])
			cap = BASIC_EXECUTION_CAP
		Demand.EXPLOSIVE:
			base_values = PackedFloat32Array([0.0, 7.0, 15.0, 25.0])
			cap = EXPLOSIVE_EXECUTION_CAP
	var stamina_penalty := _sample_descending(
		stamina_percent(state),
		PackedFloat32Array([100.0, 50.0, 25.0, 0.0]),
		base_values,
	)
	return clampf(stamina_penalty * fatigue_amplification(state), 0.0, cap)


static func execution_multiplier(state: MatchSideState, demand: int) -> float:
	return clampf(1.0 - execution_penalty(state, demand) / 100.0, 0.01, 1.0)


static func fatigue_amplification(state: MatchSideState) -> float:
	if state == null:
		return 1.0
	return _sample_ascending(
		state.fatigue,
		PackedFloat32Array([0.0, 50.0, 75.0, 90.0, 100.0]),
		PackedFloat32Array([1.0, 1.10, 1.35, 1.60, 1.70]),
	)


static func stamina_cost_multiplier(state: MatchSideState, demand: int = Demand.STANDARD) -> float:
	if state == null:
		return 1.0
	var fatigue_cost := _sample_ascending(
		state.fatigue,
		PackedFloat32Array([0.0, 50.0, 75.0, 90.0, 100.0]),
		PackedFloat32Array([1.0, 1.10, 1.25, 1.40, 1.50]),
	)
	var surcharge := 0.0
	if demand == Demand.STANDARD:
		surcharge = 0.05 * combined_exhaustion(state)
	elif demand == Demand.EXPLOSIVE:
		surcharge = 0.15 * combined_exhaustion(state)
	return clampf(fatigue_cost * (1.0 + surcharge), 1.0, 1.75)


static func stamina_recovery_multiplier(state: MatchSideState) -> float:
	if state == null:
		return 1.0
	return _sample_ascending(
		state.fatigue,
		PackedFloat32Array([0.0, 50.0, 75.0, 90.0, 100.0]),
		PackedFloat32Array([1.0, 0.75, 0.50, 0.25, 0.10]),
	)


static func reversal_penalty(state: MatchSideState) -> float:
	if state == null:
		return 0.0
	var stamina_penalty := _sample_descending(
		stamina_percent(state),
		PackedFloat32Array([100.0, 50.0, 25.0, 0.0]),
		PackedFloat32Array([0.0, 5.0, 9.0, 12.0]),
	)
	var fatigue_penalty := _sample_ascending(
		state.fatigue,
		PackedFloat32Array([0.0, 50.0, 75.0, 100.0]),
		PackedFloat32Array([0.0, 0.0, 2.0, 5.0]),
	)
	return clampf(stamina_penalty * fatigue_amplification(state) + fatigue_penalty, 0.0, REVERSAL_PENALTY_CAP)


static func kickout_penalty(state: MatchSideState) -> float:
	return _finish_defence_penalty(state, false)


static func submission_escape_penalty(state: MatchSideState) -> float:
	return _finish_defence_penalty(state, true)


static func control_retention_chance(state: MatchSideState, demand: int) -> float:
	if state == null or demand == Demand.BASIC:
		return 100.0
	var severity := combined_exhaustion(state)
	if demand == Demand.EXPLOSIVE:
		return clampf(100.0 - 40.0 * severity + state.momentum * 0.10, 60.0, 100.0)
	return clampf(100.0 - 18.0 * severity, 82.0, 100.0)


static func recovery_delay_chance(state: MatchSideState, after_crash: bool = false) -> float:
	if state == null:
		return 0.0
	var severity := combined_exhaustion(state)
	var chance := 25.0 * clampf(inverse_lerp(0.45, 1.0, severity), 0.0, 1.0)
	if after_crash:
		chance += 10.0
	return clampf(chance, 0.0, RECOVERY_DELAY_CAP)


static func profile(
	state: MatchSideState,
	move: MoveResource = null,
	is_signature: bool = false,
	is_ladder_variant: bool = false,
	environmental_followup: bool = false,
) -> Dictionary:
	var demand := effective_move_demand(
		move,
		is_signature,
		is_ladder_variant,
		environmental_followup,
	)
	return {
		"stamina_ratio": stamina_ratio(state),
		"fatigue_ratio": fatigue_ratio(state),
		"combined_exhaustion": combined_exhaustion(state),
		"band": exhaustion_band(state),
		"band_label": exhaustion_band_label(state),
		"demand": demand,
		"demand_label": demand_label(demand),
		"execution_penalty": execution_penalty(state, demand),
		"execution_multiplier": execution_multiplier(state, demand),
		"fatigue_amplification": fatigue_amplification(state),
		"stamina_cost_multiplier": stamina_cost_multiplier(state, demand),
		"stamina_recovery_multiplier": stamina_recovery_multiplier(state),
		"reversal_penalty": reversal_penalty(state),
		"kickout_penalty": kickout_penalty(state),
		"submission_escape_penalty": submission_escape_penalty(state),
		"control_retention_chance": control_retention_chance(state, demand),
		"recovery_delay_chance": recovery_delay_chance(state),
	}


static func _finish_defence_penalty(state: MatchSideState, submission: bool) -> float:
	if state == null:
		return 0.0
	var stamina_penalty := _sample_descending(
		stamina_percent(state),
		PackedFloat32Array([100.0, 50.0, 25.0, 0.0]),
		PackedFloat32Array([0.0, 6.0, 12.0, 20.0]),
	)
	var fatigue_penalty := _sample_ascending(
		state.fatigue,
		PackedFloat32Array([0.0, 50.0, 75.0, 100.0]),
		PackedFloat32Array([0.0, 0.0, 8.0, 15.0 if submission else 12.0]),
	)
	return clampf(
		stamina_penalty + fatigue_penalty,
		0.0,
		SUBMISSION_ESCAPE_PENALTY_CAP if submission else KICKOUT_PENALTY_CAP,
	)


static func _sample_ascending(value: float, points: PackedFloat32Array, values: PackedFloat32Array) -> float:
	if points.is_empty() or points.size() != values.size():
		return 0.0
	if value <= points[0]:
		return values[0]
	for index in range(1, points.size()):
		if value <= points[index]:
			return lerpf(values[index - 1], values[index], inverse_lerp(points[index - 1], points[index], value))
	return values[values.size() - 1]


static func _sample_descending(value: float, points: PackedFloat32Array, values: PackedFloat32Array) -> float:
	if points.is_empty() or points.size() != values.size():
		return 0.0
	if value >= points[0]:
		return values[0]
	for index in range(1, points.size()):
		if value >= points[index]:
			return lerpf(values[index - 1], values[index], inverse_lerp(points[index - 1], points[index], value))
	return values[values.size() - 1]
