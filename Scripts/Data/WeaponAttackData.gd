@tool
extends Resource
class_name WeaponAttackResource

enum TargetPosture { STANDING, GROUNDED }

@export var attack_id: StringName = &""
@export var display_name: String = "Weapon Attack"
@export var target_posture: TargetPosture = TargetPosture.STANDING
@export_range(-2, 2, 1) var impact_modifier: int = 0
@export_range(-4.0, 8.0, 0.5) var stamina_modifier: float = 0.0
@export var is_strike: bool = true
@export var interaction_override: MoveResource.InteractionOverride = MoveResource.InteractionOverride.TIMING_STRIKE
@export var resulting_target_position: WrestlerResource.Position = WrestlerResource.Position.GROUNDED
@export var resulting_target_orientation: WrestlerResource.Orientation = WrestlerResource.Orientation.FACE_UP

