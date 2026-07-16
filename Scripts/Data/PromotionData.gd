@tool
extends Resource
class_name PromotionResource

enum Region { NONE, NORTH_AMERICA, SOUTH_AMERICA, ASIA, AFRICA, OCEANIA, EUROPE }
enum NA_Countries { USA, CANADA, MEXICO, OTHER }
enum SA_Countries { BRAZIL, ARGENTINA, CHILE, OTHER }
enum Europe_Countries { UK, GERMANY, FRANCE, ITALY, SPAIN, OTHER }
enum Asia_Countries { JAPAN, CHINA, SOUTH_KOREA, INDIA, OTHER }
enum Oceania_Countries { AUSTRALIA, NEW_ZEALAND, SAMOA, OTHER }
enum Africa_Countries { GHANA, NIGERIA, EGYPT, SOUTH_AFRICA, OTHER }

@export_group("Promotion Info")
@export var promotion_name = str("")
@export var promotion_initials: String = ""
@export var promotion_id: int = 0
@export var preferred_styles: Array[WrestlerResource.WrestlerClass] = []
@export var is_indie: bool = false:
	set(value):
		is_indie = value
		notify_property_list_changed()
@export_range(-100000, 1000000, 10000) var bank_balance: float = 0
@export var home_region: Region = Region.NONE:
	set(value):
		home_region = value
		notify_property_list_changed()
@export var north_american_country: NA_Countries = NA_Countries.OTHER
@export var south_american_country: SA_Countries = SA_Countries.OTHER
@export var europe_country: Europe_Countries = Europe_Countries.OTHER
@export var asia_country: Asia_Countries = Asia_Countries.OTHER
@export var africa_country: Africa_Countries = Africa_Countries.OTHER
@export var oceania_country: Oceania_Countries = Oceania_Countries.OTHER

@export_group("Roster")
@export var mens_division: Array[WrestlerResource]
@export var womens_division: Array[WrestlerResource]
@export var titles: Array[TitleResource]

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

func _validate_property(property: Dictionary):
	# Hide country enums that don't match the current home_region
	if property.name == "north_american_country" and home_region != Region.NORTH_AMERICA:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name == "south_american_country" and home_region != Region.SOUTH_AMERICA:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name == "europe_country" and home_region != Region.EUROPE:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name == "asia_country" and home_region != Region.ASIA:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name == "africa_country" and home_region != Region.AFRICA:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name == "oceania_country" and home_region != Region.OCEANIA:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name == "bank_balance" and is_indie != false:
		property.usage = PROPERTY_USAGE_NO_EDITOR
