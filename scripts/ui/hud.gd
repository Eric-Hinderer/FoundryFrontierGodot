extends CanvasLayer

@onready var credits_label: Label = %CreditsLabel
@onready var power_label: Label = %PowerLabel
@onready var research_label: Label = %ResearchLabel
@onready var status_label: Label = %StatusLabel
@onready var inspector_label: RichTextLabel = %InspectorLabel
@onready var recipe_header: Label = %RecipeHeader
@onready var recipe_buttons: VBoxContainer = %RecipeButtons
@onready var tech_buttons: VBoxContainer = %TechButtons
@onready var mission_label: RichTextLabel = %MissionLabel
@onready var world: WorldController = %World

var _selected_tile := Vector2i(-999, -999)
var _tech_button_map: Dictionary = {}

func _ready() -> void:
    _apply_theme()
    GameState.changed.connect(_refresh)
    GameState.mission_completed.connect(_on_mission_completed)
    GameState.tech_unlocked.connect(_on_tech_unlocked)
    world.status_changed.connect(_set_status)
    world.selection_changed.connect(_inspect)
    world.tool_changed.connect(_highlight_tool)
    _bind_buttons()
    _build_tech_panel()
    _highlight_tool(world.selected_tool)
    _refresh()

func _apply_theme() -> void:
    var theme := Theme.new()
    theme.set_stylebox("panel", "PanelContainer", _panel_style())
    theme.set_stylebox("normal", "Button", _button_style(Color("#1d2a32")))
    theme.set_stylebox("hover", "Button", _button_style(Color("#27373f")))
    theme.set_stylebox("pressed", "Button", _button_style(Color("#2f8f9e")))
    theme.set_stylebox("focus", "Button", _button_style(Color("#27373f")))
    theme.set_stylebox("disabled", "Button", _button_style(Color("#161d22")))
    theme.set_color("font_color", "Button", Color("#d6e8ef"))
    theme.set_color("font_hover_color", "Button", Color("#ffffff"))
    theme.set_color("font_disabled_color", "Button", Color("#59666e"))
    theme.set_color("font_color", "Label", Color("#cfe3ea"))
    theme.set_color("default_color", "RichTextLabel", Color("#cfe3ea"))
    for child in get_children():
        if child is Control:
            (child as Control).theme = theme

func _panel_style() -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color("#111a20ee")
    style.set_corner_radius_all(8)
    style.set_border_width_all(1)
    style.border_color = Color("#2b3d47")
    style.set_content_margin_all(10)
    return style

func _button_style(color: Color) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.set_corner_radius_all(6)
    style.set_border_width_all(1)
    style.border_color = Color("#384a54")
    style.set_content_margin_all(6)
    return style

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
    _refresh_build_locks()
    _refresh_tech_panel()
    _refresh_mission()

func _refresh_build_locks() -> void:
    for button: Button in %BuildButtons.get_children():
        var tool_id := String(button.get_meta("tool"))
        if DataRegistry.buildings.has(tool_id) and tool_id != "hub":
            button.disabled = not GameState.is_building_unlocked(tool_id)

func _set_status(message: String) -> void:
    status_label.text = message

# --- Inspector & recipe selection ----------------------------------------

func _inspect(building: Dictionary) -> void:
    _clear_recipe_buttons()
    if building.is_empty():
        _selected_tile = Vector2i(-999, -999)
        recipe_header.visible = false
        inspector_label.text = "[b]INSPECTOR[/b]\nSelect a building to inspect its state."
        return
    _selected_tile = Vector2i(int(building.x), int(building.y))
    var definition: Dictionary = DataRegistry.buildings.get(building.type, {})
    var lines: Array[String] = []
    lines.append("[b]%s[/b]" % definition.get("name", building.type))
    lines.append("Facing: %s" % ["North", "East", "South", "West"][int(building.direction)])
    var recipe_id := String(building.get("recipe", ""))
    if recipe_id != "" and DataRegistry.recipes.has(recipe_id):
        var recipe: Dictionary = DataRegistry.recipes[recipe_id]
        lines.append("Recipe: %s" % _item_name(recipe.output))
    if int(definition.get("power", 0)) > 0:
        lines.append("Power draw: %d" % int(definition.get("power", 0)))
    if building.type == "belt":
        var ids: Array = []
        for entry: Dictionary in building.get("items", []):
            ids.append(String(entry.id))
        lines.append("Cargo: %s" % _format_items_list(ids))
    else:
        lines.append("Stored: %s" % _format_items(building.inventory))
        lines.append("Buffer: %s" % _format_items_list(building.output))
    if building.type in ["miner", "furnace", "assembler"]:
        lines.append("Progress: %d%%" % roundi(float(building.progress) * 100.0))
    inspector_label.text = "\n".join(lines)
    _populate_recipe_buttons(building)

func _populate_recipe_buttons(building: Dictionary) -> void:
    var options := world.recipes_for_machine(String(building.type))
    recipe_header.visible = not options.is_empty()
    var current := String(building.get("recipe", ""))
    for recipe_id: String in options:
        var button := Button.new()
        var marker := "● " if recipe_id == current else "○ "
        button.text = marker + _item_name(DataRegistry.recipes[recipe_id].output)
        button.pressed.connect(_on_recipe_pressed.bind(recipe_id))
        recipe_buttons.add_child(button)

func _on_recipe_pressed(recipe_id: String) -> void:
    world.set_recipe(_selected_tile, recipe_id)

func _clear_recipe_buttons() -> void:
    for child in recipe_buttons.get_children():
        child.queue_free()

# --- Technology tree ------------------------------------------------------

func _build_tech_panel() -> void:
    for tech_id: String in DataRegistry.technology:
        var button := Button.new()
        button.pressed.connect(GameState.research_tech.bind(tech_id))
        tech_buttons.add_child(button)
        _tech_button_map[tech_id] = button
    _refresh_tech_panel()

func _refresh_tech_panel() -> void:
    for tech_id: String in _tech_button_map:
        var tech: Dictionary = DataRegistry.technology[tech_id]
        var button: Button = _tech_button_map[tech_id]
        var tech_name := String(tech.get("name", tech_id))
        if tech_id in GameState.unlocked_tech:
            button.text = "✓ %s" % tech_name
            button.disabled = true
        elif GameState.can_research(tech_id):
            button.text = "%s  (◈%d)" % [tech_name, int(tech.get("cost", 0))]
            button.disabled = false
        else:
            button.text = "%s  (◈%d) 🔒" % [tech_name, int(tech.get("cost", 0))]
            button.disabled = true

# --- Missions -------------------------------------------------------------

func _refresh_mission() -> void:
    var mission := GameState.current_mission()
    if mission.is_empty():
        mission_label.text = "All contracts fulfilled — the frontier is secured."
        return
    mission_label.text = "[b]%s[/b]\nDeliver %s ×%d  (%d/%d)\nReward: ₡%d · ◈%d" % [
        mission.get("name", "Contract"),
        _item_name(mission.item),
        int(mission.amount),
        GameState.mission_progress(),
        int(mission.amount),
        int(mission.get("reward_credits", 0)),
        int(mission.get("reward_research", 0)),
    ]

func _on_mission_completed(mission: Dictionary) -> void:
    _set_status("Contract complete: %s  (+₡%d, +◈%d)" % [
        mission.get("name", "Contract"),
        int(mission.get("reward_credits", 0)),
        int(mission.get("reward_research", 0)),
    ])

func _on_tech_unlocked(tech_id: String) -> void:
    _set_status("Researched %s" % DataRegistry.technology.get(tech_id, {}).get("name", tech_id))

# --- Formatting helpers ---------------------------------------------------

func _item_name(item_id: String) -> String:
    return String(DataRegistry.items.get(item_id, {}).get("name", item_id))

func _format_items(inventory: Dictionary) -> String:
    if inventory.is_empty():
        return "empty"
    var parts: Array[String] = []
    for item_id: String in inventory:
        if int(inventory[item_id]) <= 0:
            continue
        parts.append("%s ×%d" % [_item_name(item_id), int(inventory[item_id])])
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
