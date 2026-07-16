@tool
extends Resource
class_name TitleResource

enum TitleGender { MALE = 1, FEMALE = 2 }

@export_group("Title Info")
@export var title_name: String = ""
@export var promotion_id: int = 0
@export var gender: TitleGender = TitleGender.MALE
@export var current_holder_id: int = 0
@export var weeks_held: int = 0
@export var previous_holder_ids: Array[int] = []
