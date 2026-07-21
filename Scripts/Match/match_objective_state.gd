extends RefCounted
class_name MatchObjectiveState

signal table_broken(initiator_side: int, victim_side: int, instance_ids: Array[int])
signal ladder_progressed(side: int, stage: int, area: int)
signal suspended_object_reach_changed(side: int, eligible: bool)

var last_table_break_initiator: int = 0
var last_table_break_victim: int = 0
var last_table_instance_ids: Array[int] = []
var ladder_setup_area: int = WrestlerResource.Area.IN_RING
var ladder_climb_stage_by_side: Dictionary = {}
var suspended_object_reach_eligible: Dictionary = {}


func reset() -> void:
	last_table_break_initiator = 0
	last_table_break_victim = 0
	last_table_instance_ids.clear()
	ladder_setup_area = WrestlerResource.Area.IN_RING
	ladder_climb_stage_by_side.clear()
	suspended_object_reach_eligible.clear()


func note_table_break(initiator_side: int, victim_side: int, instance_ids: Array[int]) -> void:
	last_table_break_initiator = initiator_side
	last_table_break_victim = victim_side
	last_table_instance_ids = instance_ids.duplicate()
	table_broken.emit(initiator_side, victim_side, last_table_instance_ids)


func note_ladder_setup(area: int) -> void:
	ladder_setup_area = area


func note_ladder_stage(side: int, stage: int, area: int) -> void:
	ladder_setup_area = area
	ladder_climb_stage_by_side[side] = stage
	var eligible := stage >= 2 and area == WrestlerResource.Area.IN_RING
	suspended_object_reach_eligible[side] = eligible
	ladder_progressed.emit(side, stage, area)
	suspended_object_reach_changed.emit(side, eligible)


func snapshot() -> Dictionary:
	return {
		"table_break_initiator": last_table_break_initiator,
		"table_break_victim": last_table_break_victim,
		"table_instance_ids": last_table_instance_ids.duplicate(),
		"ladder_setup_area": ladder_setup_area,
		"ladder_climb_stages": ladder_climb_stage_by_side.duplicate(true),
		"suspended_object_reach_eligible": suspended_object_reach_eligible.duplicate(true),
	}
