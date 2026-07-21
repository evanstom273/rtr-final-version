extends Resource
class_name WeaponResource

enum WeaponKind { HANDHELD, TABLE, LADDER, THUMBTACKS }

@export var weapon_id: StringName = &""
@export var display_name: String = "Weapon"
@export_multiline var description: String = ""
@export var weapon_kind: WeaponKind = WeaponKind.HANDHELD
@export var icon_id: StringName = &"weapon"
@export_range(1, 10, 1) var impact: int = 7
@export_range(0.0, 30.0, 0.5) var stamina_cost: float = 8.0
@export var target_body_part: MoveResource.MoveTargetParts = MoveResource.MoveTargetParts.BODY
@export var is_illegal_under_normal_rules: bool = true
@export var can_be_retrieved_from_under_ring: bool = true
@export var ai_weight: float = 1.0
@export_range(1, 4, 1) var minimum_durability: int = 1
@export_range(1, 4, 1) var maximum_durability: int = 4
@export_range(0.0, 100.0, 1.0) var bleed_rating: float = 0.0
@export var can_bleed_any_target: bool = false
@export_group("Environmental Setup")
@export var can_set_flat: bool = false
@export var can_set_in_corner: bool = false
@export var can_stack: bool = false
@export var can_be_climbed: bool = false
@export var can_be_spread: bool = false
@export_range(1, 2, 1) var maximum_live_instances: int = 1
@export var attack_set: Array[WeaponAttackResource] = []


func supports_direct_attacks() -> bool:
	return not attack_set.is_empty()


func durability_range_text() -> String:
	return (
		str(minimum_durability)
		if minimum_durability == maximum_durability
		else "%d-%d" % [minimum_durability, maximum_durability]
	)
