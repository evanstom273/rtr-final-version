extends Resource
class_name WeaponResource

@export var weapon_id: StringName = &""
@export var display_name: String = "Weapon"
@export_multiline var description: String = ""
@export_range(1, 10, 1) var impact: int = 7
@export_range(0.0, 30.0, 0.5) var stamina_cost: float = 8.0
@export var target_body_part: MoveResource.MoveTargetParts = MoveResource.MoveTargetParts.BODY
@export var is_illegal_under_normal_rules: bool = true
@export var can_be_retrieved_from_under_ring: bool = true
@export var ai_weight: float = 1.0
@export_range(1, 10, 1) var minimum_durability: int = 1
@export_range(1, 10, 1) var maximum_durability: int = 4
