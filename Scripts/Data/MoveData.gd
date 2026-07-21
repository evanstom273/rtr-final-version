@tool
extends Resource
class_name MoveResource

enum MoveTargetParts { NONE, HEAD, BODY, LEFT_ARM, RIGHT_ARM, LEFT_LEG, RIGHT_LEG }
enum TargetingMode { FIXED_PARTS, CHOOSE_ARM, CHOOSE_LEG, BOTH_ARMS, BOTH_LEGS }
enum MoveType { NONE,
				STRIKE,
				GRAPPLE,
				SUBMISSION,
				AERIAL,
				SPRINGBOARD,
				RUNNING,
				REVERSAL,
				PINNING_MOVE,
				WEAPON,
				ENVIRONMENTAL }

enum StrikeWeight { STRIKE_WEAK,
					STRIKE_MEDIUM,
					STRIKE_HEAVY
				}
enum InteractionOverride { AUTO, TIMING_STRIKE, TIMING_AERIAL, HOLD_POWER, SUBMISSION_LOCK_IN }
enum AreaRequirementMode { SPECIFIC, ANY, SAME_AS_OTHER, SHARED_FLAT_AREA }
enum AreaResultMode { UNCHANGED, SPECIFIC }

@export_group("Move Info")
@export var move_name: String = ""
@export var move_type: MoveType = MoveType.NONE
@export var class_preferrence: Array[WrestlerResource.WrestlerClass]
@export var move_target_parts: Array[MoveTargetParts] = []
@export var targeting_mode: TargetingMode = TargetingMode.FIXED_PARTS
@export var default_side_target: MoveTargetParts = MoveTargetParts.NONE
@export_group("Attacker Requirements")
@export var required_attacker_position: WrestlerResource.Position
@export var required_attacker_orientation: WrestlerResource.Orientation
@export var required_attacker_area_mode: AreaRequirementMode = AreaRequirementMode.ANY
@export var required_attacker_area: WrestlerResource.Area = WrestlerResource.Area.IN_RING
@export var required_attacker_motion_state: WrestlerResource.MotionState = WrestlerResource.MotionState.STATIONARY

@export_group("Target Requirements")
@export var required_target_position: WrestlerResource.Position
@export var required_target_orientation: WrestlerResource.Orientation
@export var required_target_area_mode: AreaRequirementMode = AreaRequirementMode.SAME_AS_OTHER
@export var required_target_area: WrestlerResource.Area = WrestlerResource.Area.IN_RING
@export var required_target_motion_state: WrestlerResource.MotionState = WrestlerResource.MotionState.STATIONARY

@export_group("Attacker Results")
@export var resulting_attacker_position: WrestlerResource.Position
@export var resulting_attacker_orientation: WrestlerResource.Orientation
@export var resulting_attacker_area_mode: AreaResultMode = AreaResultMode.UNCHANGED
@export var resulting_attacker_area: WrestlerResource.Area = WrestlerResource.Area.IN_RING
@export var resulting_attacker_motion_state: WrestlerResource.MotionState = WrestlerResource.MotionState.STATIONARY

@export_group("Target Results")
@export var resulting_target_position: WrestlerResource.Position
@export var resulting_target_orientation: WrestlerResource.Orientation
@export var resulting_target_area_mode: AreaResultMode = AreaResultMode.UNCHANGED
@export var resulting_target_area: WrestlerResource.Area = WrestlerResource.Area.IN_RING
@export var resulting_target_motion_state: WrestlerResource.MotionState = WrestlerResource.MotionState.STATIONARY

@export_group("Move Behaviour")
@export var is_finisher: bool = false
@export var is_submission: bool = false
@export var is_flash_pin: bool = false
@export var is_pinning_combination: bool = false
@export var interaction_override: InteractionOverride = InteractionOverride.AUTO
@export var required_weapon_id: StringName = &""
@export var additional_valid_target_positions: Array[WrestlerResource.Position] = []
@export var is_strike: bool = false:
	set(value):
		is_strike = value
		notify_property_list_changed()
@export var strike_weight: StrikeWeight = StrikeWeight.STRIKE_WEAK
@export_range(1, 10, 1) var move_impact: int = 1

func _validate_property(property: Dictionary) -> void:
	if property.name == "strike_weight" and is_strike != true:
		property.usage = PROPERTY_USAGE_NO_EDITOR


func areas_match(attacker_area: int, target_area: int) -> bool:
	return (
		_area_requirement_matches(
			required_attacker_area_mode,
			required_attacker_area,
			attacker_area,
			target_area,
		)
		and _area_requirement_matches(
			required_target_area_mode,
			required_target_area,
			target_area,
			attacker_area,
		)
	)


func resolved_attacker_area(current_area: int) -> int:
	return (
		resulting_attacker_area
		if resulting_attacker_area_mode == AreaResultMode.SPECIFIC
		else current_area
	)


func resolved_target_area(current_area: int) -> int:
	return (
		resulting_target_area
		if resulting_target_area_mode == AreaResultMode.SPECIFIC
		else current_area
	)


static func _area_requirement_matches(
	mode: int,
	specific_area: int,
	actual_area: int,
	other_area: int,
) -> bool:
	match mode:
		AreaRequirementMode.ANY:
			return true
		AreaRequirementMode.SAME_AS_OTHER:
			return actual_area == other_area
		AreaRequirementMode.SHARED_FLAT_AREA:
			return (
				actual_area == other_area
				and actual_area in [
					WrestlerResource.Area.IN_RING,
					WrestlerResource.Area.OUTSIDE,
					WrestlerResource.Area.RAMP,
				]
			)
	return actual_area == specific_area
