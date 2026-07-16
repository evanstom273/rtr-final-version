@tool
extends Resource
class_name ContractResource

@export_group("Contract Info")
@export var wrestler_id: int = 0 
@export var promotion_id: int = 0
@export_range(1, 52, 1) var length_weeks: float
@export_range(0, 25000, 1000) var salary: float
@export var start_date: String
@export var end_date: String

@export_group("Clauses")
@export var clause_creative_control: bool = false
@export var clause_iron_clad: bool = false
@export var clause_title_shot: bool = false:
	set(value):
		clause_title_shot = value
		notify_property_list_changed()
@export_range(1, 52, 1) var title_shot_deadline_week: float
@export var clause_medical_care: bool = false

func _validate_property(property: Dictionary):
	if property.name == "title_shot_deadline_week" and clause_title_shot != true:
		property.usage = PROPERTY_USAGE_NO_EDITOR
