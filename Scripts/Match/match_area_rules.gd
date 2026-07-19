@tool
extends RefCounted
class_name MatchAreaRules


static func is_shared_flat_area(area: int) -> bool:
	return area in [
		WrestlerResource.Area.IN_RING,
		WrestlerResource.Area.OUTSIDE,
		WrestlerResource.Area.RAMP,
	]


static func is_supported_directional_pair(attacker_area: int, target_area: int) -> bool:
	if attacker_area == target_area:
		return true
	return Vector2i(attacker_area, target_area) in [
		Vector2i(WrestlerResource.Area.IN_RING, WrestlerResource.Area.CORNER),
		Vector2i(WrestlerResource.Area.IN_RING, WrestlerResource.Area.ROPES),
		Vector2i(WrestlerResource.Area.IN_RING, WrestlerResource.Area.APRON),
		Vector2i(WrestlerResource.Area.APRON, WrestlerResource.Area.IN_RING),
		Vector2i(WrestlerResource.Area.APRON, WrestlerResource.Area.ROPES),
		Vector2i(WrestlerResource.Area.ROPES, WrestlerResource.Area.OUTSIDE),
		Vector2i(WrestlerResource.Area.TOP_ROPE, WrestlerResource.Area.IN_RING),
		Vector2i(WrestlerResource.Area.TOP_ROPE, WrestlerResource.Area.OUTSIDE),
	]


static func move_areas_match(move: MoveResource, attacker_area: int, target_area: int) -> bool:
	if move == null:
		return false
	# Do not call MoveResource methods here. Editor tools can encounter an
	# already-cached .tres as a placeholder instance after its script changes,
	# but its serialized exported values remain available. Evaluating those
	# values here keeps catalogue audits/generation safe in editor mode.
	if not _area_requirement_matches(
		int(move.required_attacker_area_mode),
		int(move.required_attacker_area),
		attacker_area,
		target_area,
	):
		return false
	if not _area_requirement_matches(
		int(move.required_target_area_mode),
		int(move.required_target_area),
		target_area,
		attacker_area,
	):
		return false
	if (
		move.required_attacker_area_mode == MoveResource.AreaRequirementMode.SPECIFIC
		and move.required_target_area_mode == MoveResource.AreaRequirementMode.SPECIFIC
		and attacker_area != target_area
	):
		return is_supported_directional_pair(attacker_area, target_area)
	return true


static func _area_requirement_matches(
	mode: int,
	specific_area: int,
	actual_area: int,
	other_area: int,
) -> bool:
	match mode:
		MoveResource.AreaRequirementMode.ANY:
			return true
		MoveResource.AreaRequirementMode.SAME_AS_OTHER:
			return actual_area == other_area
		MoveResource.AreaRequirementMode.SHARED_FLAT_AREA:
			return actual_area == other_area and is_shared_flat_area(actual_area)
		MoveResource.AreaRequirementMode.SPECIFIC:
			return actual_area == specific_area
	return false


static func area_name(area: int) -> String:
	for key in WrestlerResource.Area:
		if int(WrestlerResource.Area[key]) == area:
			return str(key).replace("_", " ").to_lower().capitalize()
	return "Unknown"
