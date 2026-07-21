@tool
extends RefCounted
class_name MatchSetupStateRules

const STAND_UP := &"stand_up"
const PREPARE_SPRINGBOARD := &"prepare_springboard"
const START_RUNNING := &"start_running"
const CLIMB_TOP_ROPE := &"climb_top_rope"
const PICK_OPPONENT_UP := &"pick_opponent_up"
const IRISH_WHIP := &"irish_whip"
const GRAPPLE_OPPONENT := &"grapple_opponent"
const THROW_INTO_CORNER := &"throw_into_corner"
const WAKE_OPPONENT := &"wake_opponent"
const STOP_RUNNING := &"stop_running"
const LEAVE_CORNER := &"leave_corner"
const REGAIN_FOOTING := &"regain_footing"
const CLIMB_DOWN := &"climb_down"
const RETURN_TO_RING := &"return_to_ring"
const RESET_STANCE := &"reset_stance"
const TAUNT := &"taunt"
const CATCH_BREATH := &"catch_breath"

const STEP_TO_ROPES := &"step_to_ropes"
const LEAVE_ROPES := &"leave_ropes"
const GET_BEHIND_OPPONENT := &"get_behind_opponent"
const TURN_OPPONENT_FACE_UP := &"turn_opponent_face_up"
const TURN_OPPONENT_FACE_DOWN := &"turn_opponent_face_down"
const SIT_OPPONENT_UP_FRONT := &"sit_opponent_up_front"
const SIT_OPPONENT_UP_BACK := &"sit_opponent_up_back"
const PULL_OPPONENT_TO_KNEES_FRONT := &"pull_opponent_to_knees_front"
const PULL_OPPONENT_TO_KNEES_BACK := &"pull_opponent_to_knees_back"
const TURN_OPPONENT_IN_CORNER := &"turn_opponent_in_corner"
const SEAT_OPPONENT_IN_CORNER := &"seat_opponent_in_corner"
const LEAN_OPPONENT_ON_ROPES_FRONT := &"lean_opponent_on_ropes_front"
const LEAN_OPPONENT_ON_ROPES_BACK := &"lean_opponent_on_ropes_back"
const DRAPE_OPPONENT_ON_ROPES_FRONT := &"drape_opponent_on_ropes_front"
const DRAPE_OPPONENT_ON_ROPES_BACK := &"drape_opponent_on_ropes_back"
const PLACE_OPPONENT_ON_APRON_FRONT := &"place_opponent_on_apron_front"
const PLACE_OPPONENT_ON_APRON_BACK := &"place_opponent_on_apron_back"
const SET_OPPONENT_ON_TOP_ROPE_FRONT := &"set_opponent_on_top_rope_front"
const SET_OPPONENT_ON_TOP_ROPE_BACK := &"set_opponent_on_top_rope_back"
const SEND_OPPONENT_OUTSIDE := &"send_opponent_outside"
const CALL_OPPONENT_OUTSIDE := &"call_opponent_outside"
const EXIT_RING := &"exit_ring"
const TAKE_FIGHT_OUTSIDE := &"take_fight_outside"
const FIGHT_UP_RAMP := &"fight_up_ramp"
const RETURN_FROM_RAMP := &"return_from_ramp"
const BRING_MATCH_BACK_TO_RING := &"bring_match_back_to_ring"
const PULL_OPPONENT_FROM_CORNER := &"pull_opponent_from_corner"
const PULL_OPPONENT_FROM_ROPES := &"pull_opponent_from_ropes"
const BRING_OPPONENT_INTO_RING := &"bring_opponent_into_ring"
const CATCH_OPPONENT_RUNNING := &"catch_opponent_running"
const CALL_OPPONENT_RUNNING := &"call_opponent_running"
const REGAIN_COMPOSURE := &"regain_composure"
const PRESS_ADVANTAGE := &"press_advantage"
const WAIT_FOR_COUNT := &"wait_for_count"
const RETRIEVE_STEEL_CHAIR := &"retrieve_steel_chair"
const RETRIEVE_WEAPON := &"retrieve_weapon"
const PICK_UP_WEAPON := &"pick_up_weapon"
const DROP_WEAPON := &"drop_weapon"
const CHAIR_SHOT := &"chair_shot"
const SET_TABLE_FLAT := &"set_table_flat"
const SET_TABLE_CORNER := &"set_table_corner"
const STACK_TABLE := &"stack_table"
const POSITION_AT_TABLE := &"position_at_table"
const LAY_ON_TABLE := &"lay_on_table"
const POSITION_AT_CORNER_TABLE := &"position_at_corner_table"
const MOVE_CLEAR_TABLE := &"move_clear_table"
const SET_UP_LADDER := &"set_up_ladder"
const CLIMB_LADDER := &"climb_ladder"
const CLIMB_LADDER_TOP := &"climb_ladder_top"
const TIP_LADDER := &"tip_ladder"
const CLIMB_DOWN_LADDER := &"climb_down_ladder"
const SPREAD_THUMBTACKS := &"spread_thumbtacks"
const POSITION_OVER_THUMBTACKS := &"position_over_thumbtacks"
const MOVE_CLEAR_THUMBTACKS := &"move_clear_thumbtacks"

const _TRANSIENT_MOTIONS := [
	WrestlerResource.MotionState.RISING,
]
const _GROUNDED_POSTURES := [
	WrestlerResource.Position.GROUNDED,
	WrestlerResource.Position.SEATED,
	WrestlerResource.Position.KNEELING,
]


static func get_candidate_actions(attacker: Variant, target: Variant) -> Array[StringName]:
	var actor := _snapshot_of(attacker)
	var defender := _snapshot_of(target)
	var actions: Array[StringName] = []
	if actor.is_empty() or defender.is_empty():
		return actions
	var actor_position := int(actor.position)
	var actor_orientation := int(actor.orientation)
	var actor_area := int(actor.area)
	var actor_motion := int(actor.motion_state)
	var target_position := int(defender.position)
	var target_area := int(defender.area)
	var target_motion := int(defender.motion_state)

	if actor_position in _GROUNDED_POSTURES:
		actions.append(STAND_UP)
	if actor_motion == WrestlerResource.MotionState.RUNNING:
		actions.append(STOP_RUNNING)
	if actor_motion == WrestlerResource.MotionState.ROPE_REBOUND:
		actions.append(REGAIN_FOOTING)
	if actor_motion in _TRANSIENT_MOTIONS:
		actions.append(REGAIN_COMPOSURE)
	# RISING is a recovery transition that can be closed down. STAGGERING is an
	# authored attack opportunity in the new catalogue, so it must remain usable
	# directly instead of forcing an extra setup action first.
	if target_motion == WrestlerResource.MotionState.RISING:
		actions.append(PRESS_ADVANTAGE)
	if actor_area == WrestlerResource.Area.CORNER:
		actions.append(LEAVE_CORNER)
	if actor_area == WrestlerResource.Area.TOP_ROPE:
		actions.append(CLIMB_DOWN)
	if actor_area in [WrestlerResource.Area.APRON, WrestlerResource.Area.OUTSIDE]:
		actions.append(RETURN_TO_RING)
	if actor_area == WrestlerResource.Area.RAMP and target_area != WrestlerResource.Area.RAMP:
		actions.append(RETURN_TO_RING)
	if actor_area == WrestlerResource.Area.ROPES:
		actions.append(LEAVE_ROPES)

	var actor_flat_ready := (
		actor_position == WrestlerResource.Position.STANDING
		and actor_orientation == WrestlerResource.Orientation.FRONT
		and motion_matches(WrestlerResource.MotionState.STATIONARY, actor_motion)
		and MatchAreaRules.is_shared_flat_area(actor_area)
	)
	var same_flat_ready := (
		actor_flat_ready
		and motion_matches(WrestlerResource.MotionState.STATIONARY, target_motion)
		and actor_area == target_area
		and MatchAreaRules.is_shared_flat_area(target_area)
	)
	if actor_flat_ready:
		actions.append(START_RUNNING)
	if actor_flat_ready and actor_area == WrestlerResource.Area.IN_RING:
		actions.append(CLIMB_TOP_ROPE)
		actions.append(PREPARE_SPRINGBOARD)
		actions.append(STEP_TO_ROPES)
		actions.append(EXIT_RING)
	if same_flat_ready and target_position in _GROUNDED_POSTURES:
		actions.append(PICK_OPPONENT_UP)
	if same_flat_ready and target_position == WrestlerResource.Position.STANDING:
		actions.append(GET_BEHIND_OPPONENT)
		actions.append(IRISH_WHIP)
	if same_flat_ready and target_position == WrestlerResource.Position.GROUNDED:
		actions.append(TURN_OPPONENT_FACE_DOWN if int(defender.orientation) == WrestlerResource.Orientation.FACE_UP else TURN_OPPONENT_FACE_UP)
	if same_flat_ready and target_position in [WrestlerResource.Position.STANDING, WrestlerResource.Position.GROUNDED]:
		actions.append(SIT_OPPONENT_UP_FRONT)
		actions.append(SIT_OPPONENT_UP_BACK)
		actions.append(PULL_OPPONENT_TO_KNEES_FRONT)
		actions.append(PULL_OPPONENT_TO_KNEES_BACK)

	var both_in_ring_standing := (
		actor_flat_ready
		and actor_area == WrestlerResource.Area.IN_RING
		and target_area == WrestlerResource.Area.IN_RING
		and target_position == WrestlerResource.Position.STANDING
		and target_motion == WrestlerResource.MotionState.STATIONARY
	)
	if both_in_ring_standing:
		actions.append(THROW_INTO_CORNER)
		actions.append(LEAN_OPPONENT_ON_ROPES_FRONT)
		actions.append(LEAN_OPPONENT_ON_ROPES_BACK)
		actions.append(DRAPE_OPPONENT_ON_ROPES_FRONT)
		actions.append(DRAPE_OPPONENT_ON_ROPES_BACK)
		actions.append(PLACE_OPPONENT_ON_APRON_FRONT)
		actions.append(PLACE_OPPONENT_ON_APRON_BACK)
		actions.append(SET_OPPONENT_ON_TOP_ROPE_FRONT)
		actions.append(SET_OPPONENT_ON_TOP_ROPE_BACK)
		actions.append(SEND_OPPONENT_OUTSIDE)
		actions.append(TAKE_FIGHT_OUTSIDE)
	if actor_area == WrestlerResource.Area.IN_RING and target_area == WrestlerResource.Area.CORNER and actor_flat_ready:
		actions.append(PULL_OPPONENT_FROM_CORNER)
		if target_position == WrestlerResource.Position.STANDING:
			actions.append(TURN_OPPONENT_IN_CORNER)
			actions.append(SEAT_OPPONENT_IN_CORNER)
	if actor_area == WrestlerResource.Area.IN_RING and target_area == WrestlerResource.Area.ROPES and actor_flat_ready:
		actions.append(PULL_OPPONENT_FROM_ROPES)
	if (
		actor_area == WrestlerResource.Area.IN_RING
		and target_area in [WrestlerResource.Area.APRON, WrestlerResource.Area.TOP_ROPE]
		and actor_flat_ready
	):
		actions.append(BRING_OPPONENT_INTO_RING)
	if (
		actor_flat_ready
		and actor_area == target_area
		and MatchAreaRules.is_shared_flat_area(target_area)
		and target_position == WrestlerResource.Position.STANDING
		and target_motion in [WrestlerResource.MotionState.RUNNING, WrestlerResource.MotionState.ROPE_REBOUND]
	):
		actions.append(CATCH_OPPONENT_RUNNING)
	if actor_area == WrestlerResource.Area.TOP_ROPE and target_position in _GROUNDED_POSTURES:
		actions.append(WAKE_OPPONENT)
	if (
		actor_area == WrestlerResource.Area.TOP_ROPE
		and actor_position == WrestlerResource.Position.PERCHED
		and target_area == WrestlerResource.Area.IN_RING
		and target_position == WrestlerResource.Position.STANDING
		and target_motion == WrestlerResource.MotionState.STATIONARY
	):
		actions.append(CALL_OPPONENT_RUNNING)
	if same_flat_ready and actor_area == WrestlerResource.Area.OUTSIDE and target_position == WrestlerResource.Position.STANDING:
		actions.append(FIGHT_UP_RAMP)
	if (
		actor_flat_ready
		and actor_area == WrestlerResource.Area.OUTSIDE
		and target_area == WrestlerResource.Area.IN_RING
		and target_position == WrestlerResource.Position.STANDING
		and target_motion == WrestlerResource.MotionState.STATIONARY
	):
		actions.append(CALL_OPPONENT_OUTSIDE)
	if actor_area == WrestlerResource.Area.RAMP and target_area == WrestlerResource.Area.RAMP:
		actions.append(RETURN_FROM_RAMP)
	if _needs_ring_recovery(actor_area, target_area) and BRING_OPPONENT_INTO_RING not in actions:
		actions.append(BRING_MATCH_BACK_TO_RING)
	if _taunt_is_positionally_valid(actor, defender):
		actions.append(TAUNT)
	if actor_flat_ready and actor_area in [WrestlerResource.Area.IN_RING, WrestlerResource.Area.OUTSIDE, WrestlerResource.Area.RAMP]:
		actions.append(CATCH_BREATH)
	return _unique_actions(actions)


static func project_action(action_id: StringName, attacker_snapshot: Dictionary, target_snapshot: Dictionary) -> Dictionary:
	var actor := attacker_snapshot.duplicate(true)
	var target := target_snapshot.duplicate(true)
	var candidates := get_candidate_actions(actor, target)
	var valid := action_id in candidates or action_id == RESET_STANCE or action_id == GRAPPLE_OPPONENT
	var details := action_details(action_id, actor)
	if not valid:
		return {
			"valid": false,
			"attacker": actor,
			"target": target,
			"contested": is_contested(action_id),
			"recovery": is_recovery(action_id),
			"label": str(details.title),
			"description": str(details.description),
			"intent_key": action_id,
		}
	match action_id:
		STAND_UP:
			_set_state(actor, WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, int(actor.area), WrestlerResource.MotionState.STATIONARY)
		STOP_RUNNING, REGAIN_FOOTING, REGAIN_COMPOSURE:
			actor.motion_state = WrestlerResource.MotionState.STATIONARY
		PRESS_ADVANTAGE:
			target.motion_state = WrestlerResource.MotionState.STATIONARY
		LEAVE_CORNER, CLIMB_DOWN, RETURN_TO_RING, LEAVE_ROPES:
			_set_state(actor, WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.IN_RING, WrestlerResource.MotionState.STATIONARY)
		START_RUNNING:
			_set_state(actor, WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, int(actor.area), WrestlerResource.MotionState.RUNNING)
		CLIMB_TOP_ROPE:
			_set_state(actor, WrestlerResource.Position.PERCHED, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.TOP_ROPE, WrestlerResource.MotionState.STATIONARY)
		PREPARE_SPRINGBOARD:
			_set_state(actor, WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.APRON, WrestlerResource.MotionState.STATIONARY)
		STEP_TO_ROPES:
			_set_state(actor, WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.ROPES, WrestlerResource.MotionState.STATIONARY)
		PICK_OPPONENT_UP, WAKE_OPPONENT:
			_set_state(target, WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, int(target.area), WrestlerResource.MotionState.STATIONARY)
		GET_BEHIND_OPPONENT:
			_set_state(target, WrestlerResource.Position.STANDING, WrestlerResource.Orientation.BACK, int(target.area), WrestlerResource.MotionState.STATIONARY)
		IRISH_WHIP:
			_set_state(target, WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, int(actor.area), WrestlerResource.MotionState.ROPE_REBOUND)
		TURN_OPPONENT_FACE_UP:
			_set_state(target, WrestlerResource.Position.GROUNDED, WrestlerResource.Orientation.FACE_UP, int(target.area), WrestlerResource.MotionState.STATIONARY)
		TURN_OPPONENT_FACE_DOWN:
			_set_state(target, WrestlerResource.Position.GROUNDED, WrestlerResource.Orientation.FACE_DOWN, int(target.area), WrestlerResource.MotionState.STATIONARY)
		SIT_OPPONENT_UP_FRONT:
			_set_state(target, WrestlerResource.Position.SEATED, WrestlerResource.Orientation.FRONT, int(target.area), WrestlerResource.MotionState.STATIONARY)
		SIT_OPPONENT_UP_BACK:
			_set_state(target, WrestlerResource.Position.SEATED, WrestlerResource.Orientation.BACK, int(target.area), WrestlerResource.MotionState.STATIONARY)
		PULL_OPPONENT_TO_KNEES_FRONT:
			_set_state(target, WrestlerResource.Position.KNEELING, WrestlerResource.Orientation.FRONT, int(target.area), WrestlerResource.MotionState.STATIONARY)
		PULL_OPPONENT_TO_KNEES_BACK:
			_set_state(target, WrestlerResource.Position.KNEELING, WrestlerResource.Orientation.BACK, int(target.area), WrestlerResource.MotionState.STATIONARY)
		THROW_INTO_CORNER:
			_set_state(target, WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.CORNER, WrestlerResource.MotionState.STATIONARY)
		TURN_OPPONENT_IN_CORNER:
			_set_state(target, WrestlerResource.Position.STANDING, WrestlerResource.Orientation.BACK, WrestlerResource.Area.CORNER, WrestlerResource.MotionState.STATIONARY)
		SEAT_OPPONENT_IN_CORNER:
			_set_state(target, WrestlerResource.Position.SEATED, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.CORNER, WrestlerResource.MotionState.STATIONARY)
		LEAN_OPPONENT_ON_ROPES_FRONT:
			_set_state(target, WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.ROPES, WrestlerResource.MotionState.STATIONARY)
		LEAN_OPPONENT_ON_ROPES_BACK:
			_set_state(target, WrestlerResource.Position.STANDING, WrestlerResource.Orientation.BACK, WrestlerResource.Area.ROPES, WrestlerResource.MotionState.STATIONARY)
		DRAPE_OPPONENT_ON_ROPES_FRONT:
			_set_state(target, WrestlerResource.Position.KNEELING, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.ROPES, WrestlerResource.MotionState.STATIONARY)
		DRAPE_OPPONENT_ON_ROPES_BACK:
			_set_state(target, WrestlerResource.Position.KNEELING, WrestlerResource.Orientation.BACK, WrestlerResource.Area.ROPES, WrestlerResource.MotionState.STATIONARY)
		PLACE_OPPONENT_ON_APRON_FRONT:
			_set_state(target, WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.APRON, WrestlerResource.MotionState.STATIONARY)
		PLACE_OPPONENT_ON_APRON_BACK:
			_set_state(target, WrestlerResource.Position.STANDING, WrestlerResource.Orientation.BACK, WrestlerResource.Area.APRON, WrestlerResource.MotionState.STATIONARY)
		SET_OPPONENT_ON_TOP_ROPE_FRONT, SET_OPPONENT_ON_TOP_ROPE_BACK:
			_set_state(actor, WrestlerResource.Position.PERCHED, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.TOP_ROPE, WrestlerResource.MotionState.STATIONARY)
			_set_state(target, WrestlerResource.Position.PERCHED, WrestlerResource.Orientation.FRONT if action_id == SET_OPPONENT_ON_TOP_ROPE_FRONT else WrestlerResource.Orientation.BACK, WrestlerResource.Area.TOP_ROPE, WrestlerResource.MotionState.STATIONARY)
		SEND_OPPONENT_OUTSIDE:
			_set_state(target, WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.OUTSIDE, WrestlerResource.MotionState.STATIONARY)
		CALL_OPPONENT_OUTSIDE:
			_set_state(target, WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.OUTSIDE, WrestlerResource.MotionState.STATIONARY)
		EXIT_RING:
			_set_state(actor, WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.OUTSIDE, WrestlerResource.MotionState.STATIONARY)
		TAKE_FIGHT_OUTSIDE:
			_set_neutral_flat(actor, WrestlerResource.Area.OUTSIDE)
			_set_neutral_flat(target, WrestlerResource.Area.OUTSIDE)
		FIGHT_UP_RAMP:
			_set_neutral_flat(actor, WrestlerResource.Area.RAMP)
			_set_neutral_flat(target, WrestlerResource.Area.RAMP)
		RETURN_FROM_RAMP:
			_set_neutral_flat(actor, WrestlerResource.Area.OUTSIDE)
			_set_neutral_flat(target, WrestlerResource.Area.OUTSIDE)
		PULL_OPPONENT_FROM_CORNER, PULL_OPPONENT_FROM_ROPES, BRING_OPPONENT_INTO_RING:
			_set_neutral_flat(target, WrestlerResource.Area.IN_RING)
		CATCH_OPPONENT_RUNNING:
			target.motion_state = WrestlerResource.MotionState.STATIONARY
		BRING_MATCH_BACK_TO_RING, RESET_STANCE, GRAPPLE_OPPONENT:
			_set_neutral_flat(actor, WrestlerResource.Area.IN_RING)
			_set_neutral_flat(target, WrestlerResource.Area.IN_RING)
		CALL_OPPONENT_RUNNING:
			_set_state(target, WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.IN_RING, WrestlerResource.MotionState.RUNNING)
		TAUNT:
			pass
		CATCH_BREATH:
			pass
	return {
		"valid": true,
		"attacker": actor,
		"target": target,
		"contested": is_contested(action_id),
		"recovery": is_recovery(action_id),
		"label": str(details.title),
		"description": str(details.description),
		"intent_key": action_id,
	}


static func find_followup_paths(
	move_set: Array[MoveResource],
	attacker_snapshot: Dictionary,
	target_snapshot: Dictionary,
	max_setup_steps: int = 2,
) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var frontier: Array[Dictionary] = [{
		"attacker": attacker_snapshot.duplicate(true),
		"target": target_snapshot.duplicate(true),
		"actions": [],
	}]
	var visited := {_state_pair_key(attacker_snapshot, target_snapshot): 0}
	for depth in range(maxi(0, max_setup_steps) + 1):
		var next_frontier: Array[Dictionary] = []
		for node in frontier:
			var actor: Dictionary = node.attacker
			var target: Dictionary = node.target
			var path: Array = node.actions
			for move in move_set:
				if move != null and move_matches_snapshots(move, actor, target):
					results.append({"actions": path.duplicate(), "move": move, "attacker": actor, "target": target})
			if depth >= max_setup_steps:
				continue
			for action_id in get_candidate_actions(actor, target):
				if not _is_planning_action(action_id) or action_id in path:
					continue
				var projected := project_action(action_id, actor, target)
				if not bool(projected.valid):
					continue
				var next_actor: Dictionary = projected.attacker
				var next_target: Dictionary = projected.target
				var next_path := path.duplicate()
				next_path.append(action_id)
				var key := _state_pair_key(next_actor, next_target)
				if int(visited.get(key, 999)) <= next_path.size():
					continue
				visited[key] = next_path.size()
				next_frontier.append({"attacker": next_actor, "target": next_target, "actions": next_path})
		frontier = next_frontier
		if frontier.is_empty():
			break
	return results


static func move_matches_snapshots(move: MoveResource, attacker: Dictionary, target: Dictionary) -> bool:
	if move == null:
		return false
	return (
		_position_matches(move.required_attacker_position, int(attacker.get("position", WrestlerResource.Position.NONE)))
		and _position_matches(move.required_target_position, int(target.get("position", WrestlerResource.Position.NONE)))
		and _orientation_matches(move.required_attacker_orientation, int(attacker.get("orientation", WrestlerResource.Orientation.NONE)))
		and _orientation_matches(move.required_target_orientation, int(target.get("orientation", WrestlerResource.Orientation.NONE)))
		and MatchAreaRules.move_areas_match(move, int(attacker.get("area", WrestlerResource.Area.IN_RING)), int(target.get("area", WrestlerResource.Area.IN_RING)))
		and motion_matches(move.required_attacker_motion_state, int(attacker.get("motion_state", WrestlerResource.MotionState.STATIONARY)))
		and motion_matches(move.required_target_motion_state, int(target.get("motion_state", WrestlerResource.MotionState.STATIONARY)))
	)


static func motion_matches(required: int, actual: int) -> bool:
	# STAGGERING is a descriptive vulnerability/presentation state, not a
	# mechanical lockout. It satisfies ordinary stationary requirements while
	# remaining available to moves that explicitly require STAGGERING.
	return (
		required == actual
		or (
			required == WrestlerResource.MotionState.STATIONARY
			and actual == WrestlerResource.MotionState.STAGGERING
		)
	)


static func is_contested(action_id: StringName) -> bool:
	return action_id in [
		PICK_OPPONENT_UP,
		IRISH_WHIP,
		GET_BEHIND_OPPONENT,
		TURN_OPPONENT_FACE_UP,
		TURN_OPPONENT_FACE_DOWN,
		SIT_OPPONENT_UP_FRONT,
		SIT_OPPONENT_UP_BACK,
		PULL_OPPONENT_TO_KNEES_FRONT,
		PULL_OPPONENT_TO_KNEES_BACK,
		THROW_INTO_CORNER,
		TURN_OPPONENT_IN_CORNER,
		SEAT_OPPONENT_IN_CORNER,
		LEAN_OPPONENT_ON_ROPES_FRONT,
		LEAN_OPPONENT_ON_ROPES_BACK,
		DRAPE_OPPONENT_ON_ROPES_FRONT,
		DRAPE_OPPONENT_ON_ROPES_BACK,
		PLACE_OPPONENT_ON_APRON_FRONT,
		PLACE_OPPONENT_ON_APRON_BACK,
		SET_OPPONENT_ON_TOP_ROPE_FRONT,
		SET_OPPONENT_ON_TOP_ROPE_BACK,
		SEND_OPPONENT_OUTSIDE,
		CALL_OPPONENT_OUTSIDE,
		TAKE_FIGHT_OUTSIDE,
		FIGHT_UP_RAMP,
		RETURN_FROM_RAMP,
		BRING_MATCH_BACK_TO_RING,
		PULL_OPPONENT_FROM_CORNER,
		PULL_OPPONENT_FROM_ROPES,
		BRING_OPPONENT_INTO_RING,
		CATCH_OPPONENT_RUNNING,
		CALL_OPPONENT_RUNNING,
		POSITION_AT_TABLE,
		LAY_ON_TABLE,
		POSITION_AT_CORNER_TABLE,
		CLIMB_LADDER,
		CLIMB_LADDER_TOP,
		TIP_LADDER,
		POSITION_OVER_THUMBTACKS,
		TAUNT,
	]


static func is_recovery(action_id: StringName) -> bool:
	return action_id in [
		STAND_UP,
		STOP_RUNNING,
		REGAIN_FOOTING,
		REGAIN_COMPOSURE,
		PRESS_ADVANTAGE,
		LEAVE_CORNER,
		CLIMB_DOWN,
		RETURN_TO_RING,
		LEAVE_ROPES,
		RETURN_FROM_RAMP,
		BRING_MATCH_BACK_TO_RING,
		PULL_OPPONENT_FROM_CORNER,
		PULL_OPPONENT_FROM_ROPES,
		BRING_OPPONENT_INTO_RING,
		CATCH_OPPONENT_RUNNING,
		MOVE_CLEAR_TABLE,
		MOVE_CLEAR_THUMBTACKS,
		CLIMB_DOWN_LADDER,
		TIP_LADDER,
		RESET_STANCE,
	]


static func action_details(action_id: StringName, attacker: Variant = {}) -> Dictionary:
	var actor := _snapshot_of(attacker)
	match action_id:
		STAND_UP: return {"title": "STAND UP", "description": "Return to standing without changing area."}
		START_RUNNING: return {"title": "START RUNNING", "description": "Build speed in the current flat area."}
		STOP_RUNNING: return {"title": "STOP RUNNING / RESET STANCE", "description": "Slow down without leaving the current area."}
		REGAIN_FOOTING: return {"title": "REGAIN FOOTING", "description": "Recover from the forced rope rebound."}
		REGAIN_COMPOSURE: return {"title": "REGAIN COMPOSURE", "description": "Shake off the transient motion state."}
		PRESS_ADVANTAGE: return {"title": "CLOSE IN ON OPPONENT", "description": "Use one action while the opponent finishes rising."}
		CLIMB_TOP_ROPE: return {"title": "CLIMB TOP ROPE", "description": "Perch on the top rope for an aerial attack."}
		CLIMB_DOWN: return {"title": "CLIMB DOWN", "description": "Return to a standing in-ring position."}
		PREPARE_SPRINGBOARD: return {"title": "STEP TO APRON", "description": "Move to the apron for a springboard attack."}
		STEP_TO_ROPES: return {"title": "STEP TO ROPES", "description": "Set at the ropes for a springboard to the floor."}
		LEAVE_ROPES: return {"title": "LEAVE ROPES", "description": "Step away from the ropes and return inside."}
		RETURN_TO_RING: return {"title": "RETURN TO RING", "description": "Return to a neutral standing position inside the ring."}
		LEAVE_CORNER: return {"title": "LEAVE CORNER", "description": "Step away from the corner."}
		PICK_OPPONENT_UP: return {"title": "PICK OPPONENT UP", "description": "Bring the opponent to standing in their current area."}
		WAKE_OPPONENT: return {"title": "CALL OPPONENT TO THEIR FEET", "description": "Remain perched while the opponent rises."}
		GET_BEHIND_OPPONENT: return {"title": "GET BEHIND OPPONENT", "description": "Move into rear control for standing-back offence."}
		IRISH_WHIP: return {"title": "IRISH WHIP", "description": "Send the opponent into a rope rebound without changing flat area."}
		TURN_OPPONENT_FACE_UP: return {"title": "TURN OPPONENT FACE UP", "description": "Roll the grounded opponent onto their back."}
		TURN_OPPONENT_FACE_DOWN: return {"title": "TURN OPPONENT FACE DOWN", "description": "Roll the grounded opponent onto their front."}
		SIT_OPPONENT_UP_FRONT: return {"title": "SIT OPPONENT UP — FRONT", "description": "Position the opponent seated and facing you."}
		SIT_OPPONENT_UP_BACK: return {"title": "SIT OPPONENT UP — BACK", "description": "Position the opponent seated with their back exposed."}
		PULL_OPPONENT_TO_KNEES_FRONT: return {"title": "PULL TO KNEES — FRONT", "description": "Position the opponent kneeling and facing you."}
		PULL_OPPONENT_TO_KNEES_BACK: return {"title": "PULL TO KNEES — BACK", "description": "Position the kneeling opponent with their back exposed."}
		THROW_INTO_CORNER: return {"title": "SEND OPPONENT INTO CORNER", "description": "Drive the opponent into a front-facing corner position."}
		TURN_OPPONENT_IN_CORNER: return {"title": "TURN OPPONENT IN CORNER", "description": "Expose the opponent's back in the corner."}
		SEAT_OPPONENT_IN_CORNER: return {"title": "SEAT OPPONENT IN CORNER", "description": "Leave the opponent seated against the turnbuckles."}
		LEAN_OPPONENT_ON_ROPES_FRONT: return {"title": "LEAN ON ROPES — FRONT", "description": "Position the standing opponent front-first at the ropes."}
		LEAN_OPPONENT_ON_ROPES_BACK: return {"title": "LEAN ON ROPES — BACK", "description": "Position the standing opponent back-first at the ropes."}
		DRAPE_OPPONENT_ON_ROPES_FRONT: return {"title": "DRAPE ON ROPES — FRONT", "description": "Leave the opponent kneeling front-first on the ropes."}
		DRAPE_OPPONENT_ON_ROPES_BACK: return {"title": "DRAPE ON ROPES — BACK", "description": "Leave the kneeling opponent's back exposed at the ropes."}
		PLACE_OPPONENT_ON_APRON_FRONT: return {"title": "PLACE ON APRON — FRONT", "description": "Move the standing opponent to the apron facing you."}
		PLACE_OPPONENT_ON_APRON_BACK: return {"title": "PLACE ON APRON — BACK", "description": "Move the standing opponent to the apron with their back exposed."}
		SET_OPPONENT_ON_TOP_ROPE_FRONT: return {"title": "SET ON TOP ROPE — FRONT", "description": "Position both wrestlers on top with the opponent facing front."}
		SET_OPPONENT_ON_TOP_ROPE_BACK: return {"title": "SET ON TOP ROPE — BACK", "description": "Position both wrestlers on top with the opponent facing back."}
		SEND_OPPONENT_OUTSIDE: return {"title": "SEND OPPONENT OUTSIDE", "description": "Leave the opponent standing outside while you remain inside."}
		CALL_OPPONENT_OUTSIDE: return {"title": "CALL OPPONENT OUTSIDE", "description": "Draw the in-ring opponent out to meet you at ringside."}
		EXIT_RING: return {"title": "EXIT RING", "description": "Leave the ring by yourself while the opponent stays where they are."}
		TAKE_FIGHT_OUTSIDE: return {"title": "TAKE THE FIGHT OUTSIDE", "description": "Move both wrestlers to the floor."}
		FIGHT_UP_RAMP: return {"title": "FIGHT UP THE RAMP", "description": "Move the outside fight onto the ramp."}
		RETURN_FROM_RAMP: return {"title": "RETURN FROM RAMP", "description": "Bring both wrestlers back to ringside."}
		BRING_MATCH_BACK_TO_RING: return {"title": "BRING MATCH BACK TO RING", "description": "Recover a stranded match state inside the ring."}
		PULL_OPPONENT_FROM_CORNER: return {"title": "PULL OPPONENT FROM CORNER", "description": "Bring the opponent out of the corner and back to a usable in-ring stance."}
		PULL_OPPONENT_FROM_ROPES: return {"title": "PULL OPPONENT FROM ROPES", "description": "Pull the opponent away from the ropes and back into the ring."}
		BRING_OPPONENT_INTO_RING: return {"title": "BRING OPPONENT INTO RING", "description": "Bring an opponent down from the apron or top rope into a standing in-ring stance."}
		CATCH_OPPONENT_RUNNING: return {"title": "CUT OFF OPPONENT", "description": "Intercept the opponent's run and force them back to a stationary stance."}
		CALL_OPPONENT_RUNNING: return {"title": "CALL OPPONENT FORWARD", "description": "Draw the opponent into a run beneath the top rope."}
		WAIT_FOR_COUNT: return {"title": "STAY INSIDE / LET REFEREE COUNT", "description": "Remain safely inside while the referee continues counting."}
		RETRIEVE_STEEL_CHAIR: return {"title": "RETRIEVE STEEL CHAIR", "description": "Reach beneath the ring for a steel chair."}
		RETRIEVE_WEAPON: return {"title": "RETRIEVE WEAPON", "description": "Choose an available weapon from beneath the ring."}
		PICK_UP_WEAPON: return {"title": "PICK UP WEAPON", "description": "Choose a dropped object from the current area."}
		DROP_WEAPON: return {"title": "DROP WEAPON", "description": "Leave the held weapon in the current area so it can be recovered."}
		CHAIR_SHOT: return {"title": "CHAIR SHOT", "description": "Swing the held steel chair at the opponent."}
		SET_TABLE_FLAT: return {"title": "SET TABLE FLAT", "description": "Unfold the held table in the current area."}
		SET_TABLE_CORNER: return {"title": "SET TABLE IN CORNER", "description": "Prop the held table against an in-ring corner."}
		STACK_TABLE: return {"title": "STACK SECOND TABLE", "description": "Add the held table to a flat table in the current area."}
		POSITION_AT_TABLE: return {"title": "POSITION OPPONENT AT TABLE", "description": "Set the standing opponent for an immediate table move."}
		LAY_ON_TABLE: return {"title": "LAY OPPONENT ON TABLE", "description": "Place the grounded opponent across the table for an aerial attack."}
		POSITION_AT_CORNER_TABLE: return {"title": "POSITION AT CORNER TABLE", "description": "Set the opponent against the table in the corner."}
		MOVE_CLEAR_TABLE: return {"title": "MOVE CLEAR OF TABLE", "description": "Escape the armed table position without moving the table."}
		SET_UP_LADDER: return {"title": "SET UP LADDER", "description": "Open the held ladder in the current area."}
		CLIMB_LADDER: return {"title": "CLIMB LADDER", "description": "Begin the first reversible stage of the climb."}
		CLIMB_LADDER_TOP: return {"title": "CLIMB TO THE TOP", "description": "Complete the reversible climb and prepare to dive."}
		TIP_LADDER: return {"title": "TIP LADDER", "description": "Try to knock the climbing opponent from the ladder."}
		CLIMB_DOWN_LADDER: return {"title": "CLIMB DOWN", "description": "Safely return from the ladder to the current area."}
		SPREAD_THUMBTACKS: return {"title": "SPREAD THUMBTACKS", "description": "Empty the held bag into a persistent patch."}
		POSITION_OVER_THUMBTACKS: return {"title": "POSITION OVER THUMBTACKS", "description": "Set the opponent for a grounding move onto the tacks."}
		MOVE_CLEAR_THUMBTACKS: return {"title": "MOVE CLEAR OF THUMBTACKS", "description": "Escape the armed tack position without removing the patch."}
		RESET_STANCE: return {"title": "RESET STANCE", "description": "Use the safe match fallback and return both wrestlers inside."}
		TAUNT:
			match int(actor.get("area", WrestlerResource.Area.IN_RING)):
				WrestlerResource.Area.TOP_ROPE: return {"title": "TOP-ROPE TAUNT", "description": "Risk showboating from the top rope."}
				WrestlerResource.Area.APRON: return {"title": "APRON TAUNT", "description": "Play to the crowd from the apron."}
				WrestlerResource.Area.OUTSIDE, WrestlerResource.Area.RAMP: return {"title": "RINGSIDE TAUNT", "description": "Play to the crowd outside while the count remains a threat."}
			return {"title": "TAUNT / PLAY TO CROWD", "description": "Showboat for stamina and momentum."}
		CATCH_BREATH: return {"title": "CATCH BREATH", "description": "Recover short-term stamina, then return the match to neutral."}
	return {"title": "SETUP ACTION", "description": "Change the current match state."}


static func state_name(value: Variant) -> String:
	var state := _snapshot_of(value)
	if state.is_empty():
		return "Unknown"
	return "%s / %s / %s / %s" % [
		_enum_name(WrestlerResource.Position, int(state.position), "Not Set"),
		_enum_name(WrestlerResource.Orientation, int(state.orientation), "Not Set"),
		_enum_name(WrestlerResource.Area, int(state.area), "Unknown"),
		_enum_name(WrestlerResource.MotionState, int(state.motion_state), "Unknown"),
	]


static func _snapshot_of(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is MatchSideState:
		return (value as MatchSideState).snapshot()
	if value is WrestlerResource:
		var wrestler := value as WrestlerResource
		return {
			"position": wrestler.position,
			"orientation": wrestler.orientation,
			"area": wrestler.area,
			"motion_state": wrestler.motion_state,
		}
	return {}


static func _set_state(state: Dictionary, position: int, orientation: int, area: int, motion: int) -> void:
	state.position = position
	state.orientation = orientation
	state.area = area
	state.motion_state = motion


static func _set_neutral_flat(state: Dictionary, area: int) -> void:
	_set_state(state, WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, area, WrestlerResource.MotionState.STATIONARY)


static func _taunt_is_positionally_valid(actor: Dictionary, target: Dictionary) -> bool:
	return (
		int(actor.position) in [WrestlerResource.Position.STANDING, WrestlerResource.Position.PERCHED]
		and int(actor.area) in [WrestlerResource.Area.IN_RING, WrestlerResource.Area.APRON, WrestlerResource.Area.TOP_ROPE, WrestlerResource.Area.OUTSIDE, WrestlerResource.Area.RAMP]
		and motion_matches(WrestlerResource.MotionState.STATIONARY, int(actor.motion_state))
		and int(target.position) in [WrestlerResource.Position.STANDING, WrestlerResource.Position.GROUNDED, WrestlerResource.Position.SEATED, WrestlerResource.Position.KNEELING]
	)


static func _needs_ring_recovery(actor_area: int, target_area: int) -> bool:
	if actor_area == target_area and actor_area in [WrestlerResource.Area.OUTSIDE, WrestlerResource.Area.RAMP]:
		return true
	if actor_area == WrestlerResource.Area.IN_RING and target_area in [WrestlerResource.Area.APRON, WrestlerResource.Area.OUTSIDE, WrestlerResource.Area.RAMP, WrestlerResource.Area.TOP_ROPE]:
		return true
	return actor_area in [WrestlerResource.Area.OUTSIDE, WrestlerResource.Area.RAMP] and target_area in [WrestlerResource.Area.IN_RING, WrestlerResource.Area.APRON, WrestlerResource.Area.ROPES, WrestlerResource.Area.TOP_ROPE]


static func _is_planning_action(action_id: StringName) -> bool:
	return not is_recovery(action_id) and action_id not in [TAUNT, CATCH_BREATH]


static func _state_pair_key(attacker: Dictionary, target: Dictionary) -> String:
	return "%d:%d:%d:%d|%d:%d:%d:%d" % [
		int(attacker.position), int(attacker.orientation), int(attacker.area), int(attacker.motion_state),
		int(target.position), int(target.orientation), int(target.area), int(target.motion_state),
	]


static func _position_matches(required: int, actual: int) -> bool:
	return required == WrestlerResource.Position.NONE or required == actual


static func _orientation_matches(required: int, actual: int) -> bool:
	return required == WrestlerResource.Orientation.NONE or required == actual


static func _enum_name(values: Dictionary, current_value: int, missing: String) -> String:
	for key in values:
		if int(values[key]) == current_value:
			return missing if str(key) == "NONE" else str(key).replace("_", " ").to_lower().capitalize()
	return "Unknown"


static func _unique_actions(actions: Array[StringName]) -> Array[StringName]:
	var result: Array[StringName] = []
	for action_id in actions:
		if action_id not in result:
			result.append(action_id)
	return result
