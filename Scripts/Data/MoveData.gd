@tool
extends Resource
class_name MoveResource

enum MoveTargetParts { NONE, HEAD, BODY, LEFT_ARM, RIGHT_ARM, LEFT_LEG, RIGHT_LEG }
enum TargetingMode { FIXED_PARTS, CHOOSE_ARM, CHOOSE_LEG, BOTH_ARMS, BOTH_LEGS }
enum MoveType { NONE, 
				STANDING_FRONT, 
				STANDING_BEHIND, 
				RUNNING, 
				ROPE_REBOUND, 
				GROUNDED,                      
				SPRINGBOARD, 
				CORNER,
				DIVING_STANDING, 
				DIVING_GROUNDED                 
				}
enum StrikeWeight { STRIKE_WEAK,
					STRIKE_MEDIUM,
					STRIKE_HEAVY
				}
enum InteractionOverride { AUTO, TIMING_STRIKE, TIMING_AERIAL, HOLD_POWER, SUBMISSION_LOCK_IN }
					
@export_group("Move Info")
@export var move_name: String = ""
@export var move_type: MoveType = MoveType.NONE
@export var class_preferrence: Array[WrestlerResource.WrestlerClass]
@export var move_target_parts: Array[MoveTargetParts] = []
@export var targeting_mode: TargetingMode = TargetingMode.FIXED_PARTS
@export var default_side_target: MoveTargetParts = MoveTargetParts.NONE
@export var required_attacker_position: WrestlerResource.Position
@export var required_target_position: WrestlerResource.Position
@export var resulting_attacker_position: WrestlerResource.Position
@export var resulting_target_position: WrestlerResource.Position
@export var is_finisher: bool = false
@export var is_submission: bool = false
@export var is_flash_pin: bool = false
@export var interaction_override: InteractionOverride = InteractionOverride.AUTO
@export var is_strike: bool = false:
	set(value):
		is_strike = value
		notify_property_list_changed()
@export var strike_weight: StrikeWeight = StrikeWeight.STRIKE_WEAK
@export_range(1, 10, 1) var move_impact: int = 1

func _validate_property(property: Dictionary) -> void:
	if property.name == "strike_weight" and is_strike != true:
		property.usage = PROPERTY_USAGE_NO_EDITOR
