extends RefCounted
class_name MoveTargetResolver

const ARM_PARTS: Array[int] = [
	MoveResource.MoveTargetParts.LEFT_ARM,
	MoveResource.MoveTargetParts.RIGHT_ARM,
]
const LEG_PARTS: Array[int] = [
	MoveResource.MoveTargetParts.LEFT_LEG,
	MoveResource.MoveTargetParts.RIGHT_LEG,
]


static func resolve(
	move: MoveResource,
	requested_focus: int,
	defender_state: MatchSideState,
) -> Dictionary:
	if move == null:
		return _fallback_resolution()
	# Weapon actions can be aimed at any explicit focus. Their fallback target
	# remains authored on the weapon/move when the selector is left on Auto.
	if move.move_type == MoveResource.MoveType.WEAPON and is_target_focus(requested_focus):
		return _single_part_resolution(requested_focus, true)
	var mode := int(move.targeting_mode)
	var listed_parts := _listed_parts(move)
	var parts: Array[int] = []
	var pressure_parts: Array[int] = []
	var weights: Dictionary = {}
	var story_part := MoveResource.MoveTargetParts.BODY
	var is_bilateral := false

	match mode:
		MoveResource.TargetingMode.CHOOSE_ARM:
			story_part = _choose_side(move, requested_focus, defender_state, ARM_PARTS)
			parts = _replace_limb_pair(listed_parts, ARM_PARTS, story_part)
			pressure_parts = [story_part]
			_set_standard_weights(weights, parts)
		MoveResource.TargetingMode.CHOOSE_LEG:
			story_part = _choose_side(move, requested_focus, defender_state, LEG_PARTS)
			parts = _replace_limb_pair(listed_parts, LEG_PARTS, story_part)
			pressure_parts = [story_part]
			_set_standard_weights(weights, parts)
		MoveResource.TargetingMode.BOTH_ARMS:
			is_bilateral = true
			parts = listed_parts
			pressure_parts = ARM_PARTS.duplicate()
			story_part = _weakest_part(defender_state, pressure_parts)
			_set_bilateral_weights(weights, parts, ARM_PARTS)
		MoveResource.TargetingMode.BOTH_LEGS:
			is_bilateral = true
			parts = listed_parts
			pressure_parts = LEG_PARTS.duplicate()
			story_part = _weakest_part(defender_state, pressure_parts)
			_set_bilateral_weights(weights, parts, LEG_PARTS)
		_:
			parts = listed_parts
			pressure_parts = parts.duplicate()
			story_part = requested_focus if requested_focus in parts else _weakest_part(defender_state, parts)
			_set_standard_weights(weights, parts)

	if parts.is_empty():
		parts = [MoveResource.MoveTargetParts.BODY]
		pressure_parts = parts.duplicate()
		weights[MoveResource.MoveTargetParts.BODY] = 1.0
		story_part = MoveResource.MoveTargetParts.BODY
	var full_tag := _full_tag(mode, parts)
	var compact_tag := _compact_tag(mode, parts)
	return {
		"parts": parts,
		"primary_part": story_part,
		"story_part": story_part,
		"damage_weights": weights,
		"pressure_parts": pressure_parts,
		"pressure_uses_average": is_bilateral,
		"is_bilateral": is_bilateral,
		"focus_applied": mode in [
			MoveResource.TargetingMode.CHOOSE_ARM,
			MoveResource.TargetingMode.CHOOSE_LEG,
		],
		"full_tag": full_tag,
		"compact_tag": compact_tag,
	}


static func target_hp(defender_state: MatchSideState, resolution: Dictionary) -> float:
	if defender_state == null:
		return 100.0
	var parts: Array = resolution.get("pressure_parts", [])
	if parts.is_empty():
		return defender_state.body_hp
	if bool(resolution.get("pressure_uses_average", false)):
		var total := 0.0
		for part in parts:
			total += defender_state.get_part_hp(int(part))
		return total / float(parts.size())
	var lowest := 100.0
	for part in parts:
		lowest = minf(lowest, defender_state.get_part_hp(int(part)))
	return lowest


static func part_label(part: int) -> String:
	match part:
		MoveResource.MoveTargetParts.HEAD:
			return "Head"
		MoveResource.MoveTargetParts.BODY:
			return "Body"
		MoveResource.MoveTargetParts.LEFT_ARM:
			return "Left Arm"
		MoveResource.MoveTargetParts.RIGHT_ARM:
			return "Right Arm"
		MoveResource.MoveTargetParts.LEFT_LEG:
			return "Left Leg"
		MoveResource.MoveTargetParts.RIGHT_LEG:
			return "Right Leg"
	return "Auto"


static func is_limb_focus(part: int) -> bool:
	return part in ARM_PARTS or part in LEG_PARTS


static func is_target_focus(part: int) -> bool:
	return part in [
		MoveResource.MoveTargetParts.HEAD,
		MoveResource.MoveTargetParts.BODY,
		MoveResource.MoveTargetParts.LEFT_ARM,
		MoveResource.MoveTargetParts.RIGHT_ARM,
		MoveResource.MoveTargetParts.LEFT_LEG,
		MoveResource.MoveTargetParts.RIGHT_LEG,
	]


static func focus_applies_to_move(move: MoveResource, part: int) -> bool:
	if move == null:
		return false
	if move.targeting_mode == MoveResource.TargetingMode.CHOOSE_ARM:
		return part in ARM_PARTS
	if move.targeting_mode == MoveResource.TargetingMode.CHOOSE_LEG:
		return part in LEG_PARTS
	return part in move.move_target_parts


static func _listed_parts(move: MoveResource) -> Array[int]:
	var parts: Array[int] = []
	for part in move.move_target_parts:
		var value := int(part)
		if value != MoveResource.MoveTargetParts.NONE and value not in parts:
			parts.append(value)
	if parts.is_empty():
		parts.append(MoveResource.MoveTargetParts.BODY)
	return parts


static func _choose_side(
	move: MoveResource,
	requested_focus: int,
	defender_state: MatchSideState,
	valid_sides: Array[int],
) -> int:
	if requested_focus in valid_sides:
		return requested_focus
	if defender_state != null:
		var first_hp := defender_state.get_part_hp(valid_sides[0])
		var second_hp := defender_state.get_part_hp(valid_sides[1])
		if not is_equal_approx(first_hp, second_hp):
			return valid_sides[0] if first_hp < second_hp else valid_sides[1]
	var declared_default := int(move.default_side_target)
	return declared_default if declared_default in valid_sides else valid_sides[0]


static func _replace_limb_pair(
	listed_parts: Array[int],
	limb_pair: Array[int],
	chosen_part: int,
) -> Array[int]:
	var result: Array[int] = []
	for part in listed_parts:
		if part in limb_pair:
			continue
		result.append(part)
	if chosen_part not in result:
		result.append(chosen_part)
	return result


static func _set_standard_weights(weights: Dictionary, parts: Array[int]) -> void:
	var weight := 0.7 if parts.size() > 1 else 1.0
	for part in parts:
		weights[part] = weight


static func _set_bilateral_weights(
	weights: Dictionary,
	parts: Array[int],
	limb_pair: Array[int],
) -> void:
	for part in parts:
		weights[part] = 0.5 if part in limb_pair else 0.7


static func _weakest_part(defender_state: MatchSideState, parts: Array[int]) -> int:
	if parts.is_empty():
		return MoveResource.MoveTargetParts.BODY
	var weakest := parts[0]
	if defender_state == null:
		return weakest
	for part in parts:
		if defender_state.get_part_hp(part) < defender_state.get_part_hp(weakest):
			weakest = part
	return weakest


static func _full_tag(mode: int, parts: Array[int]) -> String:
	match mode:
		MoveResource.TargetingMode.BOTH_ARMS:
			return "BOTH ARMS"
		MoveResource.TargetingMode.BOTH_LEGS:
			return "BOTH LEGS"
	if parts.size() == 1:
		return part_label(parts[0]).to_upper()
	if parts.size() == 2:
		return "%s/%s" % [part_label(parts[0]).to_upper(), part_label(parts[1]).to_upper()]
	return "MULTI"


static func _compact_tag(mode: int, parts: Array[int]) -> String:
	match mode:
		MoveResource.TargetingMode.BOTH_ARMS:
			return "BA"
		MoveResource.TargetingMode.BOTH_LEGS:
			return "BL"
	if parts.size() != 1:
		return "MULTI"
	match parts[0]:
		MoveResource.MoveTargetParts.HEAD:
			return "H"
		MoveResource.MoveTargetParts.BODY:
			return "B"
		MoveResource.MoveTargetParts.LEFT_ARM:
			return "LA"
		MoveResource.MoveTargetParts.RIGHT_ARM:
			return "RA"
		MoveResource.MoveTargetParts.LEFT_LEG:
			return "LL"
		MoveResource.MoveTargetParts.RIGHT_LEG:
			return "RL"
	return "B"


static func _fallback_resolution() -> Dictionary:
	return {
		"parts": [MoveResource.MoveTargetParts.BODY],
		"primary_part": MoveResource.MoveTargetParts.BODY,
		"story_part": MoveResource.MoveTargetParts.BODY,
		"damage_weights": {MoveResource.MoveTargetParts.BODY: 1.0},
		"pressure_parts": [MoveResource.MoveTargetParts.BODY],
		"pressure_uses_average": false,
		"is_bilateral": false,
		"focus_applied": false,
		"full_tag": "BODY",
		"compact_tag": "B",
	}


static func _single_part_resolution(part: int, focus_applied: bool) -> Dictionary:
	var parts: Array[int] = [part]
	return {
		"parts": parts,
		"primary_part": part,
		"story_part": part,
		"damage_weights": {part: 1.0},
		"pressure_parts": parts.duplicate(),
		"pressure_uses_average": false,
		"is_bilateral": false,
		"focus_applied": focus_applied,
		"full_tag": part_label(part).to_upper(),
		"compact_tag": _compact_tag(MoveResource.TargetingMode.FIXED_PARTS, parts),
	}
