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
    _bind_buttons()
    _refresh()

func _process(_delta: float) -> void:
    var power := world.grid_power()
    power_label.text = "⚡ %d / %d (%d%%)" % [power.demand, power.generation, roundi(float(power.efficiency) * 100.0)]

func _bind_buttons() -> void:
    for button: Button in %BuildButtons.get_children():
        button.pressed.connect(func() -> void: world.set_tool(String(button.get_meta("tool"))))
    %SaveButton.pressed.connect(_save)
    %LoadButton.pressed.connect(_load)

func _refresh() -> void:
    credits_label.text = "₡ %d" % GameState.credits
    research_label.text = "◈ %d" % GameState.research_points

func _set_status(message: String) -> void:
    status_label.text = message

func _inspect(building: Dictionary) -> void:
    var definition: Dictionary = DataRegistry.buildings.get(building.type, {})
    inspector_label.text = "[b]%s[/b]\nDirection: %s\nInventory: %s\nOutput: %s\nProgress: %d%%" % [
        definition.get("name", building.type),
        ["North", "East", "South", "West"][int(building.direction)],
        str(building.inventory),
        str(building.output),
        roundi(float(building.progress) * 100.0)
    ]

func _save() -> void:
    _set_status("Game saved" if GameState.save_world(world.serialize()) else "Save failed")

func _load() -> void:
    world.restore(GameState.load_world())
    _refresh()
    _set_status("Game loaded")
