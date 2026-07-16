@tool
extends Resource
class_name TraitsResource

@export var trait_name: String = ""
@export var trait_description: String = ""

@export_group("Booking Behaviour")
## If booked to lose: chance to refuse, backstage incident + morale hit
@export var refuses_to_job: bool = false
## Contract negotiations cost more; booking against preferred outcome triggers penalty
@export var demands_creative_control: bool = false
## Passively drains morale of all wrestlers in same promotion each week
@export var locker_room_cancer: bool = false
## Passively boosts morale of all wrestlers in same promotion each week
@export var locker_room_leader: bool = false

@export_group("Match Modifiers")
## Raises match quality floor when opponent has low skill
@export var carry_artist: bool = false
## Adds small injury chance roll to opponents after matches
@export var stiff_worker: bool = false
## Reduces injury chance roll for opponents
@export var safe_worker: bool = false

@export_group("Popularity")
## Multiplies attendance/revenue when in a main event slot
@export var mainstream_draw: bool = false
## Popularity resists decline but has a lower ceiling
@export var cult_following: bool = false
