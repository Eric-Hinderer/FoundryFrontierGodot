extends CanvasLayer

@onready var credits_label: Label = %CreditsLabel
@onready var power_label: Label = %PowerLabel
@onready var research_label: Label = %ResearchLabel
@onready var status_label: Label = %StatusLabel
@onready var inspector_label: RichTextLabel = %InspectorLabel
@onready var world: WorldController = %World

func _ready() -> void:
    GameState.changed.connect(_refresh)
    world.status_changed.connect(_set_status)
    world.selection_changed.connect(_inspect)
    world.tool_changed.connect(_highlight_tool)
    _bind_buttons()
    _highlight_tool(world.selected_tool)
    _refresh()

func _process(_delta: float) -> void:
    var power := world.grid_power()
    power_label.text = "⚡ %d / %d (%d%%)" % [power.demand, power.generation, roundi(float(power.efficiency) * 100.0)]

func _bind_buttons() -> void:
    for button: Button in %BuildButtons.get_children():
        button.pressed.connect(func() -> void: world.set_tool(String(button.get_meta("tool"))))
    %SaveButton.pressed.connect(_save)
    %LoadButton.pressed.connect(_load)

func _highlight_tool(tool_id: String) -> void:
    for button: Button in %BuildButtons.get_children():
        var active := String(button.get_meta("tool")) == tool_id
        button.modulate = Color(0.55, 1.0, 0.85) if active else Color.WHITE

func _refresh() -> void:
    credits_label.text = "₡ %d" % GameState.credits
    research_label.text = "◈ %d" % GameState.research_points

func _set_status(message: String) -> void:
    status_label.text = message

func _inspect(building: Dictionary) -> void:
    if building.is_empty():
        inspector_label.text = "[b]INSPECTOR[/b]\nSelect a building to inspect its state."
        return
    var definition: Dictionary = DataRegistry.buildings.get(building.type, {})
    var lines: Array[String] = []
    lines.append("[b]%s[/b]" % definition.get("name", building.type))
    lines.append("Facing: %s" % ["North", "East", "South", "West"][int(building.direction)])
    var recipe_id := String(building.get("recipe", ""))
    if recipe_id != "" and DataRegistry.recipes.has(recipe_id):
        var recipe: Dictionary = DataRegistry.recipes[recipe_id]
        var output_name := String(DataRegistry.items.get(recipe.output, {}).get("name", recipe.output))
        lines.append("Recipe: %s" % output_name)
    if int(definition.get("power", 0)) > 0:
        lines.append("Power draw: %d" % int(definition.get("power", 0)))
    lines.append("Stored: %s" % _format_items(building.inventory))
    lines.append("Buffer: %s" % _format_items_list(building.output))
    if building.type in ["miner", "furnace", "assembler"]:
        lines.append("Progress: %d%%" % roundi(float(building.progress) * 100.0))
    inspector_label.text = "\n".join(lines)

func _format_items(inventory: Dictionary) -> String:
    if inventory.is_empty():
        return "empty"
    var parts: Array[String] = []
    for item_id: String in inventory:
        if int(inventory[item_id]) <= 0:
            continue
        var name := String(DataRegistry.items.get(item_id, {}).get("name", item_id))
        parts.append("%s ×%d" % [name, int(inventory[item_id])])
    return "empty" if parts.is_empty() else ", ".join(parts)

func _format_items_list(items: Array) -> String:
    if items.is_empty():
        return "empty"
    var counts: Dictionary = {}
    for item_id: Variant in items:
        counts[item_id] = int(counts.get(item_id, 0)) + 1
    return _format_items(counts)

func _save() -> void:
    _set_status("Game saved" if GameState.save_world(world.serialize()) else "Save failed")

func _load() -> void:
    world.restore(GameState.load_world())
    _refresh()
    _set_status("Game loaded")
