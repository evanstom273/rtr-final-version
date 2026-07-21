extends RefCounted
class_name RingVisualPlacementResolver

enum RingAnchor {
	NONE,
	RING_CENTER,
	RING_NORTH,
	RING_EAST,
	RING_SOUTH,
	RING_WEST,
	CORNER_NORTH_WEST,
	CORNER_NORTH_EAST,
	CORNER_SOUTH_EAST,
	CORNER_SOUTH_WEST,
	ROPES_NORTH,
	ROPES_EAST,
	ROPES_SOUTH,
	ROPES_WEST,
	APRON_NORTH,
	APRON_EAST,
	APRON_SOUTH,
	APRON_WEST,
	OUTSIDE_NORTH,
	OUTSIDE_EAST,
	OUTSIDE_SOUTH,
	OUTSIDE_WEST,
	RAMP_NEAR,
	RAMP_MIDDLE,
	RAMP_FAR,
	TOP_ROPE_NORTH_WEST,
	TOP_ROPE_NORTH_EAST,
	TOP_ROPE_SOUTH_EAST,
	TOP_ROPE_SOUTH_WEST,
}

const _NORTH := 0
const _EAST := 1
const _SOUTH := 2
const _WEST := 3
const _RING_CENTRE := Vector2(0.66, 0.50)
const _RING_HEIGHT_FRACTION := 0.72
const _RING_WIDTH_FRACTION := 0.50
const _APRON_MARGIN_FRACTION := 0.045


static func resolve(
	snapshot: Dictionary,
	previous_anchor: int = RingAnchor.NONE,
	partner_snapshot: Dictionary = {},
	context: Dictionary = {},
) -> int:
	var area := int(snapshot.get("area", WrestlerResource.Area.IN_RING))
	var partner_anchor := int(context.get("partner_anchor", RingAnchor.NONE))
	var shared_interaction := bool(context.get("shared_interaction", false))
	var preferred_side := _side_for_anchor(previous_anchor)
	if preferred_side < 0 and partner_anchor != RingAnchor.NONE:
		preferred_side = _side_for_anchor(partner_anchor)
	if preferred_side < 0:
		preferred_side = _stable_side(snapshot)

	match area:
		WrestlerResource.Area.IN_RING:
			if shared_interaction and _is_ring_anchor(partner_anchor):
				return partner_anchor
			if _is_ring_anchor(previous_anchor):
				return previous_anchor
			return _ring_anchor_for_side(preferred_side, bool(context.get("prefer_centre", true)))
		WrestlerResource.Area.CORNER:
			if shared_interaction and _is_corner_anchor(partner_anchor):
				return partner_anchor
			if _is_corner_anchor(previous_anchor):
				return previous_anchor
			return _corner_for_side(preferred_side)
		WrestlerResource.Area.ROPES:
			if shared_interaction and _is_ropes_anchor(partner_anchor):
				return partner_anchor
			if _is_ropes_anchor(previous_anchor):
				return previous_anchor
			return _ropes_for_side(preferred_side)
		WrestlerResource.Area.APRON:
			if shared_interaction and _is_apron_anchor(partner_anchor):
				return partner_anchor
			if _is_apron_anchor(previous_anchor):
				return previous_anchor
			return _apron_for_side(preferred_side)
		WrestlerResource.Area.OUTSIDE:
			if shared_interaction and _is_outside_anchor(partner_anchor):
				return partner_anchor
			if _is_outside_anchor(previous_anchor):
				return previous_anchor
			return _outside_for_side(preferred_side)
		WrestlerResource.Area.RAMP:
			if previous_anchor in [RingAnchor.RAMP_NEAR, RingAnchor.RAMP_MIDDLE, RingAnchor.RAMP_FAR]:
				return previous_anchor
			if partner_anchor in [RingAnchor.RAMP_NEAR, RingAnchor.RAMP_MIDDLE, RingAnchor.RAMP_FAR]:
				return partner_anchor
			return RingAnchor.RAMP_NEAR
		WrestlerResource.Area.TOP_ROPE:
			if shared_interaction and _is_top_rope_anchor(partner_anchor):
				return partner_anchor
			if _is_top_rope_anchor(previous_anchor):
				return previous_anchor
			return _top_rope_for_side(preferred_side)
		WrestlerResource.Area.LADDER:
			return RingAnchor.RING_CENTER
	return RingAnchor.RING_CENTER


static func normalized_position(anchor: int) -> Vector2:
	var reference_size := Vector2(1000.0, 1000.0)
	return canvas_position(anchor, reference_size) / reference_size


static func mat_rect_for_canvas(canvas_size: Vector2) -> Rect2:
	var side := minf(
		canvas_size.y * _RING_HEIGHT_FRACTION,
		canvas_size.x * _RING_WIDTH_FRACTION,
	)
	var centre := canvas_size * _RING_CENTRE
	return Rect2(centre - Vector2(side, side) * 0.5, Vector2(side, side))


static func apron_rect_for_canvas(canvas_size: Vector2) -> Rect2:
	var mat_rect := mat_rect_for_canvas(canvas_size)
	var margin := minf(canvas_size.x, canvas_size.y) * _APRON_MARGIN_FRACTION
	return mat_rect.grow(margin)


static func canvas_position(anchor: int, canvas_size: Vector2) -> Vector2:
	var mat_rect := mat_rect_for_canvas(canvas_size)
	var apron_rect := apron_rect_for_canvas(canvas_size)
	var centre := mat_rect.get_center()
	var side := mat_rect.size.x
	var inner_offset := side * 0.23
	var corner_inset := side * 0.09
	var outside_offset := maxf(24.0, side * 0.22)
	var ramp_near_x := maxf(canvas_size.x * 0.17, apron_rect.position.x - side * 0.13)
	var ramp_far_x := canvas_size.x * 0.055
	match anchor:
		RingAnchor.RING_CENTER:
			return centre
		RingAnchor.RING_NORTH:
			return centre + Vector2(0.0, -inner_offset)
		RingAnchor.RING_EAST:
			return centre + Vector2(inner_offset, 0.0)
		RingAnchor.RING_SOUTH:
			return centre + Vector2(0.0, inner_offset)
		RingAnchor.RING_WEST:
			return centre + Vector2(-inner_offset, 0.0)
		RingAnchor.CORNER_NORTH_WEST, RingAnchor.TOP_ROPE_NORTH_WEST:
			return mat_rect.position + Vector2(corner_inset, corner_inset)
		RingAnchor.CORNER_NORTH_EAST, RingAnchor.TOP_ROPE_NORTH_EAST:
			return Vector2(mat_rect.end.x - corner_inset, mat_rect.position.y + corner_inset)
		RingAnchor.CORNER_SOUTH_EAST, RingAnchor.TOP_ROPE_SOUTH_EAST:
			return mat_rect.end - Vector2(corner_inset, corner_inset)
		RingAnchor.CORNER_SOUTH_WEST, RingAnchor.TOP_ROPE_SOUTH_WEST:
			return Vector2(mat_rect.position.x + corner_inset, mat_rect.end.y - corner_inset)
		RingAnchor.ROPES_NORTH:
			return Vector2(centre.x, mat_rect.position.y)
		RingAnchor.ROPES_EAST:
			return Vector2(mat_rect.end.x, centre.y)
		RingAnchor.ROPES_SOUTH:
			return Vector2(centre.x, mat_rect.end.y)
		RingAnchor.ROPES_WEST:
			return Vector2(mat_rect.position.x, centre.y)
		RingAnchor.APRON_NORTH:
			return Vector2(centre.x, apron_rect.position.y)
		RingAnchor.APRON_EAST:
			return Vector2(apron_rect.end.x, centre.y)
		RingAnchor.APRON_SOUTH:
			return Vector2(centre.x, apron_rect.end.y)
		RingAnchor.APRON_WEST:
			return Vector2(apron_rect.position.x, centre.y)
		RingAnchor.OUTSIDE_NORTH:
			return Vector2(centre.x, apron_rect.position.y - outside_offset)
		RingAnchor.OUTSIDE_EAST:
			return Vector2(apron_rect.end.x + outside_offset, centre.y)
		RingAnchor.OUTSIDE_SOUTH:
			return Vector2(centre.x, apron_rect.end.y + outside_offset)
		RingAnchor.OUTSIDE_WEST:
			return Vector2(apron_rect.position.x - outside_offset, centre.y + side * 0.30)
		RingAnchor.RAMP_NEAR:
			return Vector2(ramp_near_x, centre.y)
		RingAnchor.RAMP_MIDDLE:
			return Vector2(lerpf(ramp_far_x, ramp_near_x, 0.5), centre.y)
		RingAnchor.RAMP_FAR:
			return Vector2(ramp_far_x, centre.y)
	return centre


static func anchor_name(anchor: int) -> String:
	for key in RingAnchor:
		if int(RingAnchor[key]) == anchor:
			return str(key).to_lower().replace("_", " ").capitalize()
	return "Unknown"


static func _stable_side(snapshot: Dictionary) -> int:
	var identity := str(snapshot.get("id", snapshot.get("display_name", "wrestler")))
	return abs(identity.hash()) % 4


static func _side_for_anchor(anchor: int) -> int:
	match anchor:
		RingAnchor.RING_NORTH, RingAnchor.ROPES_NORTH, RingAnchor.APRON_NORTH, RingAnchor.OUTSIDE_NORTH:
			return _NORTH
		RingAnchor.RING_EAST, RingAnchor.ROPES_EAST, RingAnchor.APRON_EAST, RingAnchor.OUTSIDE_EAST:
			return _EAST
		RingAnchor.RING_SOUTH, RingAnchor.ROPES_SOUTH, RingAnchor.APRON_SOUTH, RingAnchor.OUTSIDE_SOUTH:
			return _SOUTH
		RingAnchor.RING_WEST, RingAnchor.ROPES_WEST, RingAnchor.APRON_WEST, RingAnchor.OUTSIDE_WEST:
			return _WEST
		RingAnchor.CORNER_NORTH_WEST, RingAnchor.TOP_ROPE_NORTH_WEST:
			return _WEST
		RingAnchor.CORNER_NORTH_EAST, RingAnchor.TOP_ROPE_NORTH_EAST:
			return _NORTH
		RingAnchor.CORNER_SOUTH_EAST, RingAnchor.TOP_ROPE_SOUTH_EAST:
			return _EAST
		RingAnchor.CORNER_SOUTH_WEST, RingAnchor.TOP_ROPE_SOUTH_WEST:
			return _SOUTH
	return -1


static func _ring_anchor_for_side(side: int, prefer_centre: bool) -> int:
	if prefer_centre:
		return RingAnchor.RING_CENTER
	return [RingAnchor.RING_NORTH, RingAnchor.RING_EAST, RingAnchor.RING_SOUTH, RingAnchor.RING_WEST][side]


static func _corner_for_side(side: int) -> int:
	return [RingAnchor.CORNER_NORTH_EAST, RingAnchor.CORNER_SOUTH_EAST, RingAnchor.CORNER_SOUTH_WEST, RingAnchor.CORNER_NORTH_WEST][side]


static func _top_rope_for_side(side: int) -> int:
	return [RingAnchor.TOP_ROPE_NORTH_EAST, RingAnchor.TOP_ROPE_SOUTH_EAST, RingAnchor.TOP_ROPE_SOUTH_WEST, RingAnchor.TOP_ROPE_NORTH_WEST][side]


static func _ropes_for_side(side: int) -> int:
	return [RingAnchor.ROPES_NORTH, RingAnchor.ROPES_EAST, RingAnchor.ROPES_SOUTH, RingAnchor.ROPES_WEST][side]


static func _apron_for_side(side: int) -> int:
	return [RingAnchor.APRON_NORTH, RingAnchor.APRON_EAST, RingAnchor.APRON_SOUTH, RingAnchor.APRON_WEST][side]


static func _outside_for_side(side: int) -> int:
	return [RingAnchor.OUTSIDE_NORTH, RingAnchor.OUTSIDE_EAST, RingAnchor.OUTSIDE_SOUTH, RingAnchor.OUTSIDE_WEST][side]


static func _is_ring_anchor(anchor: int) -> bool:
	return anchor >= RingAnchor.RING_CENTER and anchor <= RingAnchor.RING_WEST


static func _is_corner_anchor(anchor: int) -> bool:
	return anchor >= RingAnchor.CORNER_NORTH_WEST and anchor <= RingAnchor.CORNER_SOUTH_WEST


static func _is_ropes_anchor(anchor: int) -> bool:
	return anchor >= RingAnchor.ROPES_NORTH and anchor <= RingAnchor.ROPES_WEST


static func _is_apron_anchor(anchor: int) -> bool:
	return anchor >= RingAnchor.APRON_NORTH and anchor <= RingAnchor.APRON_WEST


static func _is_outside_anchor(anchor: int) -> bool:
	return anchor >= RingAnchor.OUTSIDE_NORTH and anchor <= RingAnchor.OUTSIDE_WEST


static func _is_top_rope_anchor(anchor: int) -> bool:
	return anchor >= RingAnchor.TOP_ROPE_NORTH_WEST and anchor <= RingAnchor.TOP_ROPE_SOUTH_WEST
