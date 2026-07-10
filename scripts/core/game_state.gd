extends Node

signal changed

const SAVE_PATH := "user://foundry_frontier_save.json"

var credits: int = 600
var research_points: int = 3
var unlocked_tech: Array[String] = []
var delivered: Dictionary = {}
var played_seconds: float = 0.0

func reset() -> void:
    credits = 600
    research_points = 3
    unlocked_tech.clear()
    delivered.clear()
    played_seconds = 0.0
    changed.emit()

func add_delivery(item_id: String, amount: int, value: int) -> void:
    delivered[item_id] = int(delivered.get(item_id, 0)) + amount
    credits += value * amount
    if item_id == "science":
        research_points += amount
    changed.emit()

func save_world(world_payload: Dictionary) -> bool:
    var payload := {
        "version": 1,
        "credits": credits,
        "research_points": research_points,
        "unlocked_tech": unlocked_tech,
        "delivered": delivered,
        "played_seconds": played_seconds,
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
    changed.emit()
    return payload.get("world", {})
