extends Node

var items: Dictionary = {}
var buildings: Dictionary = {}
var recipes: Dictionary = {}

func _ready() -> void:
    items = _load_json("res://data/items.json")
    buildings = _load_json("res://data/buildings.json")
    recipes = _load_json("res://data/recipes.json")

func _load_json(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("Could not open data file: %s" % path)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if parsed is Dictionary:
        return parsed
    push_error("Invalid JSON object in %s" % path)
    return {}
