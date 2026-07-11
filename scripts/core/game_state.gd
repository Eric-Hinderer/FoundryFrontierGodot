extends Node

signal changed
signal mission_completed(mission: Dictionary)
signal tech_unlocked(tech_id: String)

const SAVE_PATH := "user://foundry_frontier_save.json"

var credits: int = 600
var research_points: int = 3
var unlocked_tech: Array[String] = []
var delivered: Dictionary = {}
var played_seconds: float = 0.0
var mission_index: int = 0
var mission_baseline: int = 0

func _ready() -> void:
	_grant_free_tech()

func reset() -> void:
	credits = 600
	research_points = 3
	unlocked_tech.clear()
	delivered.clear()
	played_seconds = 0.0
	mission_index = 0
	mission_baseline = 0
	_grant_free_tech()
	changed.emit()

func add_delivery(item_id: String, amount: int, value: int) -> void:
	delivered[item_id] = int(delivered.get(item_id, 0)) + amount
	credits += value * amount
	if item_id == "science":
		research_points += amount
	_check_missions()
	changed.emit()

# --- Technology -----------------------------------------------------------

func is_building_unlocked(building_id: String) -> bool:
	if building_id == "hub":
		return true
	for tech_id: String in DataRegistry.technology:
		var tech: Dictionary = DataRegistry.technology[tech_id]
		if building_id in tech.get("unlocks_buildings", []):
			return tech_id in unlocked_tech
	return true

func is_recipe_unlocked(recipe_id: String) -> bool:
	for tech_id: String in DataRegistry.technology:
		var tech: Dictionary = DataRegistry.technology[tech_id]
		if recipe_id in tech.get("unlocks_recipes", []):
			return tech_id in unlocked_tech
	return true

func can_research(tech_id: String) -> bool:
	if tech_id in unlocked_tech:
		return false
	var tech: Dictionary = DataRegistry.technology.get(tech_id, {})
	if tech.is_empty():
		return false
	for requirement: String in tech.get("requires", []):
		if not requirement in unlocked_tech:
			return false
	return research_points >= int(tech.get("cost", 0))

func research_tech(tech_id: String) -> bool:
	if not can_research(tech_id):
		return false
	var tech: Dictionary = DataRegistry.technology[tech_id]
	research_points -= int(tech.get("cost", 0))
	unlocked_tech.append(tech_id)
	tech_unlocked.emit(tech_id)
	changed.emit()
	return true

func _grant_free_tech() -> void:
	var progressed := true
	while progressed:
		progressed = false
		for tech_id: String in DataRegistry.technology:
			if tech_id in unlocked_tech:
				continue
			var tech: Dictionary = DataRegistry.technology[tech_id]
			if int(tech.get("cost", 0)) != 0:
				continue
			var prereqs := true
			for requirement: String in tech.get("requires", []):
				if not requirement in unlocked_tech:
					prereqs = false
					break
			if prereqs:
				unlocked_tech.append(tech_id)
				progressed = true

# --- Missions -------------------------------------------------------------

func current_mission() -> Dictionary:
	if mission_index < DataRegistry.missions.size():
		return DataRegistry.missions[mission_index]
	return {}

func mission_progress() -> int:
	var mission := current_mission()
	if mission.is_empty():
		return 0
	return maxi(0, int(delivered.get(mission.item, 0)) - mission_baseline)

func _check_missions() -> void:
	var mission := current_mission()
	if mission.is_empty():
		return
	if int(delivered.get(mission.item, 0)) - mission_baseline < int(mission.amount):
		return
	credits += int(mission.get("reward_credits", 0))
	research_points += int(mission.get("reward_research", 0))
	mission_index += 1
	var next := current_mission()
	mission_baseline = int(delivered.get(next.item, 0)) if not next.is_empty() else 0
	mission_completed.emit(mission)

# --- Persistence ----------------------------------------------------------

func save_world(world_payload: Dictionary) -> bool:
	var payload := {
		"version": 2,
		"credits": credits,
		"research_points": research_points,
		"unlocked_tech": unlocked_tech,
		"delivered": delivered,
		"played_seconds": played_seconds,
		"mission_index": mission_index,
		"mission_baseline": mission_baseline,
		"world": world_payload
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Unable to write save file")
		return false
	file.store_string(JSON.stringify(payload, "  "))
	return true

func load_world() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {}
	var payload: Dictionary = parsed
	credits = int(payload.get("credits", 600))
	research_points = int(payload.get("research_points", 3))
	unlocked_tech.assign(payload.get("unlocked_tech", []))
	delivered = payload.get("delivered", {})
	played_seconds = float(payload.get("played_seconds", 0.0))
	mission_index = int(payload.get("mission_index", 0))
	mission_baseline = int(payload.get("mission_baseline", 0))
	_grant_free_tech()
	changed.emit()
	return payload.get("world", {})
