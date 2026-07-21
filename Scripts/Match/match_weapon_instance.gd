extends RefCounted
class_name MatchWeaponInstance

enum Lifecycle {
	HELD,
	DROPPED,
	SET_FLAT,
	SET_CORNER,
	SET_STACKED,
	SPREAD,
	SET_LADDER,
	BROKEN,
	CONSUMED,
}

var instance_id: int = 0
var weapon: WeaponResource
var durability: int = 0
var lifecycle: int = Lifecycle.DROPPED
var area: int = WrestlerResource.Area.OUTSIDE
var holder_side: int = 0
var positioned_side: int = 0
var positioned_by_side: int = 0
var ladder_climber_side: int = 0
var ladder_climb_stage: int = 0
var stacked_instance_ids: Array[int] = []


func is_live() -> bool:
	return lifecycle not in [Lifecycle.BROKEN, Lifecycle.CONSUMED]


func is_held() -> bool:
	return lifecycle == Lifecycle.HELD


func is_table_setup() -> bool:
	return lifecycle in [Lifecycle.SET_FLAT, Lifecycle.SET_CORNER, Lifecycle.SET_STACKED]


func clear_positioning() -> void:
	positioned_side = 0
	positioned_by_side = 0


func snapshot() -> Dictionary:
	return {
		"instance_id": instance_id,
		"weapon_id": String(weapon.weapon_id) if weapon != null else "",
		"weapon_name": weapon.display_name if weapon != null else "Unknown",
		"weapon_kind": weapon.weapon_kind if weapon != null else -1,
		"durability": durability,
		"lifecycle": lifecycle,
		"area": area,
		"holder_side": holder_side,
		"positioned_side": positioned_side,
		"positioned_by_side": positioned_by_side,
		"ladder_climber_side": ladder_climber_side,
		"ladder_climb_stage": ladder_climb_stage,
		"stacked_instance_ids": stacked_instance_ids.duplicate(),
	}

