@tool
extends Resource
class_name WrestlerResource

enum WrestlerClass { HIGH_FLYER, POWERHOUSE, TECHNICIAN, STRIKER, HARDCORE }
enum Region { NONE, NORTH_AMERICA, SOUTH_AMERICA, ASIA, AFRICA, OCEANIA, EUROPE }
enum NA_Countries { USA, CANADA, MEXICO, OTHER }
enum SA_Countries { BRAZIL, ARGENTINA, CHILE, OTHER }
enum Europe_Countries { UK, GERMANY, FRANCE, ITALY, SPAIN, OTHER }
enum Asia_Countries { JAPAN, CHINA, SOUTH_KOREA, INDIA, OTHER }
enum Oceania_Countries { AUSTRALIA, NEW_ZEALAND, SAMOA, OTHER }
enum Africa_Countries { GHANA, NIGERIA, EGYPT, SOUTH_AFRICA, OTHER }
enum Position {
	NONE = 0,
	STANDING = 1,
	GROUNDED = 2,
	IN_CORNER = 3,
	RUNNING = 4,
	ROPE_REBOUND = 5,
	TOP_ROPE = 6,
	APRON = 7,
}

enum WrestlerGender { NONE, MALE, FEMALE }
enum WrestlerDisposition { NONE, FACE, HEEL }

enum WrestlerStatus {NONE, ACTIVE, INJURED, RETIRED }

@export_group("Personal Info")
@export var wrestler_name = str("")
@export var gimmick_name: String = ""
@export var gimmick_description: String = ""
@export var wrestler_id: int = 0
@export var wrestler_class: Array[WrestlerClass] = []
@export var wrestler_gender = WrestlerGender.MALE
@export var wrestler_disposition = WrestlerDisposition.FACE
@export_range(16, 99) var Age: int = 25
@export var wrestler_height: String = "6'0"
@export var wrestler_weight: int = 220
@export var wrestler_traits: Array[TraitsResource] = []
@export var birthplace: Region = Region.NONE:
	set(value):
		birthplace = value
		notify_property_list_changed()
@export var north_american_country: NA_Countries = NA_Countries.OTHER
@export var south_american_country: SA_Countries = SA_Countries.OTHER
@export var europe_country: Europe_Countries = Europe_Countries.OTHER
@export var asia_country: Asia_Countries = Asia_Countries.OTHER
@export var africa_country: Africa_Countries = Africa_Countries.OTHER
@export var oceania_country: Oceania_Countries = Oceania_Countries.OTHER

# --- Contract ---
@export_group("Contract & Fiances")
@export var current_contract: ContractResource
@export var contract_history: Array[ContractResource] = []
@export_range(-100000, 1000000, 1000) var bank_balance: float = 0

# --- Stats ---
@export_group("Physical Attributes")
@export_range(0, 100, 5) var strength: float = 10
@export_range(0, 100, 5) var speed: float = 10
@export_range(0, 100, 5) var stamina: float = 10

@export_group("Wrestling Attributes")
@export_range(0, 100, 5) var skill: float = 10
@export_range(0, 100, 5) var striking: float = 10
@export_range(0, 100, 5) var charisma: float = 10

# --- Popularity by Region ---
@export_group("Popularity")
@export var global_popularity: float = 0:
	get:
		return roundi((
			pop_north_america
			+ pop_south_america
			+ pop_europe
			+ pop_asia
			+ pop_africa
			+ pop_oceania
		) / 6.0)
@export_range(0, 100, 5) var pop_north_america: float = 0
@export_range(0, 100, 5) var pop_south_america: float = 0
@export_range(0, 100, 5) var pop_europe: float = 0
@export_range(0, 100, 5) var pop_asia: float = 0
@export_range(0, 100, 5) var pop_africa: float = 0
@export_range(0, 100, 5) var pop_oceania: float = 0

# --- Match-Specific Stats ---
@export_group("Health & Fatigue")
@export_range(0, 100) var fatigue: float = 0.0
@export_range(0, 100, 5) var head_hp: float = 100
@export_range(0, 100, 5) var body_hp: float = 100
@export_range(0, 100, 5) var left_arm_hp: float = 100
@export_range(0, 100, 5) var right_arm_hp: float = 100
@export_range(0, 100, 5) var left_leg_hp: float = 100
@export_range(0, 100, 5) var right_leg_hp: float = 100
@export_range(0,100, 1) var momentum: float = 0.0
var position: Position = Position.STANDING

# --- Moveset ---
@export_group("Moveset")
@export var move_set: Array[MoveResource]

func _validate_property(property: Dictionary):
	# Hide country enums that don't match the current birthplace
	if property.name == "north_american_country" and birthplace != Region.NORTH_AMERICA:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name == "south_american_country" and birthplace != Region.SOUTH_AMERICA:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name == "europe_country" and birthplace != Region.EUROPE:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name == "asia_country" and birthplace != Region.ASIA:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name == "africa_country" and birthplace != Region.AFRICA:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name == "oceania_country" and birthplace != Region.OCEANIA:
		property.usage = PROPERTY_USAGE_NO_EDITOR
