extends Node2D
class_name WorldController

signal selection_changed(building: Dictionary)
signal status_changed(message: String)
signal tool_changed(tool_id: String)

const TILE_SIZE := 64
const WORLD_SIZE := Vector2i(48, 32)
const DIRECTIONS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const NO_TILE := Vector2i(-999, -999)
const INPUT_BUFFER_LIMIT := 10

var terrain: Dictionary = {}
var buildings: Dictionary = {}
var cargo: Array[Dictionary] = []
var selected_tool := "inspect"
var build_direction := 1
var demolish_start := Vector2i(-1, -1)
var demolish_end := Vector2i(-1, -1)
var hovered_tile := Vector2i.ZERO
var simulation_accumulator := 0.0
var rng := RandomNumberGenerator.new()
var _last_placed_tile := NO_TILE
var _received_this_step: Dictionary = {}

func _ready() -> void:
    rng.seed = 1701
    _generate_terrain()
    _place_initial_hub()
    queue_redraw()

func _process(delta: float) -> void:
    GameState.played_seconds += delta
    simulation_accumulator += delta
    while simulation_accumulator >= 0.1:
        simulation_accumulator -= 0.1
        _simulation_step(0.1)
    queue_redraw()

func set_tool(tool_id: String) -> void:
    selected_tool = tool_id
    if tool_id == "demolish":
        demolish_start = Vector2i(-1, -1)
        demolish_end = Vector2i(-1, -1)
    tool_changed.emit(tool_id)
    match tool_id:
        "inspect": status_changed.emit("Inspect mode — click a structure to view it")
        "demolish": status_changed.emit("Area dismantle — drag across structures to remove them")
        _: status_changed.emit("Selected %s — drag to build, right click to remove" % tool_id.capitalize())

func rotate_build() -> void:
    build_direction = (build_direction + 1) % 4
    status_changed.emit("Direction: %s" % ["North", "East", "South", "West"][build_direction])

func tile_from_world(world_position: Vector2) -> Vector2i:
    return Vector2i(floori(world_position.x / TILE_SIZE), floori(world_position.y / TILE_SIZE))

func is_in_bounds(tile: Vector2i) -> bool:
    return tile.x >= 0 and tile.y >= 0 and tile.x < WORLD_SIZE.x and tile.y < WORLD_SIZE.y

func primary_click(tile: Vector2i) -> void:
    _last_placed_tile = NO_TILE
    if not is_in_bounds(tile):
        return
    if selected_tool == "demolish":
        demolish_start = tile
        demolish_end = tile
        return
    if buildings.has(tile):
        selection_changed.emit(buildings[tile])
        return
    if selected_tool == "inspect":
        status_changed.emit("Empty tile — pick a structure to build here")
        return
    if place_building(selected_tool, tile, build_direction) and selected_tool == "belt":
        _last_placed_tile = tile

func drag_place(tile: Vector2i) -> void:
    # Continuous belt laying: dragging with the belt tool paints an oriented line.
    if selected_tool != "belt" or _last_placed_tile == NO_TILE:
        return
    if not is_in_bounds(tile) or tile == _last_placed_tile:
        return
    var delta := tile - _last_placed_tile
    if absi(delta.x) + absi(delta.y) != 1:
        return
    var direction := _direction_from_delta(delta)
    build_direction = direction
    # Re-aim the previous belt so the chain flows toward the new segment.
    if buildings.has(_last_placed_tile) and buildings[_last_placed_tile].type == "belt":
        buildings[_last_placed_tile].direction = direction
    if buildings.has(tile):
        _last_placed_tile = tile if buildings[tile].type == "belt" else NO_TILE
        return
    if place_building("belt", tile, direction, true):
        _last_placed_tile = tile

func quick_demolish(tile: Vector2i) -> void:
    if not is_in_bounds(tile) or not buildings.has(tile):
        return
    var building: Dictionary = buildings[tile]
    if building.type == "hub":
        status_changed.emit("The Command Core cannot be dismantled")
        return
    var definition: Dictionary = DataRegistry.buildings.get(building.type, {})
    var refund := roundi(int(definition.get("cost", 0)) * 0.65)
    buildings.erase(tile)
    GameState.credits += refund
    GameState.changed.emit()
    status_changed.emit("Removed %s; recovered ₡%d" % [definition.get("name", building.type), refund])

func _direction_from_delta(delta: Vector2i) -> int:
    if delta == Vector2i.UP: return 0
    if delta == Vector2i.RIGHT: return 1
    if delta == Vector2i.DOWN: return 2
    return 3

func drag_to(tile: Vector2i) -> void:
    hovered_tile = tile
    if demolish_start.x >= 0:
        demolish_end = Vector2i(clampi(tile.x, 0, WORLD_SIZE.x - 1), clampi(tile.y, 0, WORLD_SIZE.y - 1))

func release_click(tile: Vector2i) -> void:
    if demolish_start.x >= 0:
        demolish_end = Vector2i(clampi(tile.x, 0, WORLD_SIZE.x - 1), clampi(tile.y, 0, WORLD_SIZE.y - 1))
        _commit_demolish()
        demolish_start = Vector2i(-1, -1)
        demolish_end = Vector2i(-1, -1)

func place_building(type_id: String, tile: Vector2i, direction: int, quiet := false) -> bool:
    if not DataRegistry.buildings.has(type_id) or buildings.has(tile):
        return false
    if type_id == "miner" and not terrain.get(tile, {}).has("resource"):
        if not quiet:
            status_changed.emit("Miners must be placed on a resource field")
        return false
    var definition: Dictionary = DataRegistry.buildings[type_id]
    var cost := int(definition.get("cost", 0))
    if GameState.credits < cost:
        if not quiet:
            status_changed.emit("Not enough credits")
        return false
    GameState.credits -= cost
    buildings[tile] = {
        "type": type_id,
        "x": tile.x,
        "y": tile.y,
        "direction": direction,
        "inventory": {},
        "output": [],
        "progress": 0.0,
        "recipe": _default_recipe(type_id),
        "fuel": 0.0
    }
    GameState.changed.emit()
    if not quiet:
        status_changed.emit("Built %s" % definition.get("name", type_id))
    return true

func serialize() -> Dictionary:
    var building_rows: Array[Dictionary] = []
    for tile: Vector2i in buildings:
        var row: Dictionary = buildings[tile].duplicate(true)
        building_rows.append(row)
    return {"buildings": building_rows, "cargo": cargo.duplicate(true)}

func restore(payload: Dictionary) -> void:
    if payload.is_empty():
        return
    buildings.clear()
    for row: Dictionary in payload.get("buildings", []):
        var tile := Vector2i(int(row.get("x", 0)), int(row.get("y", 0)))
        buildings[tile] = row
    cargo.assign(payload.get("cargo", []))
    if not _has_hub():
        _place_initial_hub()

func grid_power() -> Dictionary:
    var generation := 20
    var demand := 0
    for building: Dictionary in buildings.values():
        var definition: Dictionary = DataRegistry.buildings.get(building.type, {})
        demand += int(definition.get("power", 0))
        if building.type == "generator" and float(building.get("fuel", 0.0)) > 0.0:
            generation += int(definition.get("generation", 0))
    var efficiency := 1.0 if demand <= generation or demand == 0 else maxf(0.15, float(generation) / demand)
    return {"generation": generation, "demand": demand, "efficiency": efficiency}

func _generate_terrain() -> void:
    for y in WORLD_SIZE.y:
        for x in WORLD_SIZE.x:
            var tile := Vector2i(x, y)
            var noise := sin(float(x) * 0.42) + cos(float(y) * 0.37) + rng.randf_range(-0.35, 0.35)
            var resource := ""
            if noise > 1.15:
                resource = "iron_ore"
            elif noise < -1.15:
                resource = "copper_ore"
            elif absf(noise) < 0.08 and (x + y) % 4 == 0:
                resource = "coal"
            terrain[tile] = {"shade": rng.randf_range(0.0, 1.0), "resource": resource} if resource != "" else {"shade": rng.randf_range(0.0, 1.0)}

func _place_initial_hub() -> void:
    var tile := Vector2i(WORLD_SIZE.x / 2, WORLD_SIZE.y / 2)
    buildings[tile] = {"type":"hub","x":tile.x,"y":tile.y,"direction":0,"inventory":{},"output":[],"progress":0.0,"recipe":"","fuel":0.0}

func _has_hub() -> bool:
    for building: Dictionary in buildings.values():
        if building.type == "hub":
            return true
    return false

func _default_recipe(type_id: String) -> String:
    if type_id == "furnace": return "iron_plate"
    if type_id == "assembler": return "gear"
    return ""

func _simulation_step(dt: float) -> void:
    _received_this_step.clear()
    var power := grid_power()
    for tile: Vector2i in buildings.keys():
        var building: Dictionary = buildings[tile]
        match building.type:
            "miner": _update_miner(building, dt * float(power.efficiency))
            "belt": _update_belt(building, dt)
            "storage": _update_storage(building)
            "furnace", "assembler": _update_processor(building, dt * float(power.efficiency))
            "generator": _update_generator(building, dt)
        buildings[tile] = building
    _update_cargo(dt)

func _update_miner(building: Dictionary, dt: float) -> void:
    var tile := Vector2i(building.x, building.y)
    var resource := String(terrain.get(tile, {}).get("resource", ""))
    if resource == "" or building.output.size() >= 2:
        return
    building.progress += dt / 1.2
    if building.progress >= 1.0:
        building.progress = 0.0
        building.output.append(resource)
        _try_emit_output(building)

func _update_belt(building: Dictionary, _dt: float) -> void:
    # Belts push their leading item forward. Items received this step stay at the
    # back of the buffer, so we only forward an item that was already waiting —
    # this keeps flow to one tile per tick without deadlocking a fed belt.
    if building.output.is_empty():
        return
    var tile := Vector2i(building.x, building.y)
    if building.output.size() > int(_received_this_step.get(tile, 0)):
        _try_emit_output(building)

func _update_storage(building: Dictionary) -> void:
    # Storage acts as a buffer: it forwards buffered items and refills the buffer
    # from its stored inventory, so goods no longer vanish inside it.
    if not building.output.is_empty():
        _try_emit_output(building)
    if building.output.size() >= 4:
        return
    for item_id: String in building.inventory.keys():
        if int(building.inventory[item_id]) > 0:
            building.inventory[item_id] = int(building.inventory[item_id]) - 1
            if int(building.inventory[item_id]) <= 0:
                building.inventory.erase(item_id)
            building.output.append(item_id)
            return

func _update_processor(building: Dictionary, dt: float) -> void:
    if building.output.size() > 0:
        _try_emit_output(building)
        return
    var recipe: Dictionary = DataRegistry.recipes.get(building.recipe, {})
    if recipe.is_empty():
        return
    var inventory: Dictionary = building.inventory
    if not _has_recipe_inputs(inventory, recipe.inputs):
        return
    building.progress += dt / float(recipe.time)
    if building.progress >= 1.0:
        building.progress = 0.0
        for item_id: String in recipe.inputs:
            inventory[item_id] = int(inventory.get(item_id, 0)) - int(recipe.inputs[item_id])
        for _index in int(recipe.get("count", 1)):
            building.output.append(String(recipe.output))
        building.inventory = inventory
        _try_emit_output(building)

func _update_generator(building: Dictionary, dt: float) -> void:
    if building.fuel > 0.0:
        building.fuel = maxf(0.0, float(building.fuel) - dt)
    elif int(building.inventory.get("coal", 0)) > 0:
        building.inventory.coal = int(building.inventory.coal) - 1
        building.fuel = 12.0

func _try_emit_output(building: Dictionary) -> void:
    if building.output.is_empty():
        return
    var next_tile := Vector2i(building.x, building.y) + DIRECTIONS[int(building.direction)]
    if not buildings.has(next_tile):
        return
    var item_id := String(building.output[0])
    if _receive_item(buildings[next_tile], item_id):
        building.output.pop_front()

func _receive_item(building: Dictionary, item_id: String) -> bool:
    if building.type == "hub":
        var value := int(DataRegistry.items.get(item_id, {}).get("value", 0))
        GameState.add_delivery(item_id, 1, value)
        return true
    if building.type == "belt":
        if building.output.size() >= 3: return false
        building.output.append(item_id)
        _mark_received(building)
        return true
    if building.type == "generator":
        if item_id != "coal": return false
        building.inventory.coal = int(building.inventory.get("coal", 0)) + 1
        return true
    if building.type == "storage":
        if building.output.size() + _total_inventory(building) >= 40: return false
        building.inventory[item_id] = int(building.inventory.get(item_id, 0)) + 1
        return true
    if building.type in ["furnace", "assembler"]:
        var recipe: Dictionary = DataRegistry.recipes.get(building.recipe, {})
        if not recipe.is_empty() and not recipe.inputs.has(item_id):
            return false
        if int(building.inventory.get(item_id, 0)) >= INPUT_BUFFER_LIMIT:
            return false
        building.inventory[item_id] = int(building.inventory.get(item_id, 0)) + 1
        return true
    return false

func _mark_received(building: Dictionary) -> void:
    var tile := Vector2i(building.x, building.y)
    _received_this_step[tile] = int(_received_this_step.get(tile, 0)) + 1

func _total_inventory(building: Dictionary) -> int:
    var total := 0
    for amount: Variant in building.inventory.values():
        total += int(amount)
    return total

func _has_recipe_inputs(inventory: Dictionary, inputs: Dictionary) -> bool:
    for item_id: String in inputs:
        if int(inventory.get(item_id, 0)) < int(inputs[item_id]):
            return false
    return true

func _update_cargo(_dt: float) -> void:
    # Cargo is represented in building output buffers in this first vertical slice.
    pass

func _commit_demolish() -> void:
    var min_x := mini(demolish_start.x, demolish_end.x)
    var max_x := maxi(demolish_start.x, demolish_end.x)
    var min_y := mini(demolish_start.y, demolish_end.y)
    var max_y := maxi(demolish_start.y, demolish_end.y)
    var removed := 0
    var refund := 0
    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            var tile := Vector2i(x, y)
            if not buildings.has(tile) or buildings[tile].type == "hub":
                continue
            refund += roundi(int(DataRegistry.buildings.get(buildings[tile].type, {}).get("cost", 0)) * 0.65)
            buildings.erase(tile)
            removed += 1
    GameState.credits += refund
    GameState.changed.emit()
    status_changed.emit("Removed %d structures; recovered ₡%d" % [removed, refund])

func _draw() -> void:
    _draw_terrain()
    _draw_buildings()
    _draw_previews()

func _draw_terrain() -> void:
    for tile: Vector2i in terrain:
        var info: Dictionary = terrain[tile]
        var shade := float(info.shade)
        var base := Color("#121b21").lerp(Color("#1a262d"), shade)
        draw_rect(Rect2(Vector2(tile * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE)), base)
        draw_rect(Rect2(Vector2(tile * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE)), Color(0.18, 0.28, 0.32, 0.18), false, 1.0)
        var resource := String(info.get("resource", ""))
        if resource != "":
            var color := Color(DataRegistry.items.get(resource, {}).get("color", "#ffffff"))
            draw_circle(Vector2(tile * TILE_SIZE) + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0), 15.0, color.darkened(0.18))
            draw_circle(Vector2(tile * TILE_SIZE) + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0), 7.0, color.lightened(0.2))

func _draw_buildings() -> void:
    for tile: Vector2i in buildings:
        var building: Dictionary = buildings[tile]
        var definition: Dictionary = DataRegistry.buildings.get(building.type, {})
        var center := Vector2(tile * TILE_SIZE) + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
        var body_color := Color(definition.get("color", "#667783"))
        draw_rect(Rect2(center - Vector2(25, 25), Vector2(50, 50)), body_color.darkened(0.25), true)
        draw_rect(Rect2(center - Vector2(22, 22), Vector2(44, 44)), body_color, true)
        if building.type == "belt":
            draw_line(center - Vector2(20, 0), center + Vector2(20, 0), Color("#9bc6d0"), 9.0)
        if building.type != "hub" and building.type != "generator":
            _draw_arrow(center, int(building.direction), Color("#75e4f3"))
        if building.type == "generator" and float(building.fuel) > 0.0:
            draw_circle(center, 10.0 + sin(Time.get_ticks_msec() * 0.008) * 2.0, Color(1.0, 0.72, 0.25, 0.35))
        if building.output.size() > 0:
            var item_id := String(building.output[0])
            draw_circle(center, 8.0, Color(DataRegistry.items.get(item_id, {}).get("color", "#ffffff")))

func _draw_arrow(center: Vector2, direction: int, color: Color) -> void:
    var vector := Vector2(DIRECTIONS[direction])
    var perpendicular := Vector2(-vector.y, vector.x)
    var tip := center + vector * 30.0
    draw_line(center + vector * 7.0, tip, color, 4.0)
    draw_line(tip, tip - vector * 10.0 + perpendicular * 7.0, color, 4.0)
    draw_line(tip, tip - vector * 10.0 - perpendicular * 7.0, color, 4.0)

func _draw_previews() -> void:
    if demolish_start.x >= 0:
        var min_tile := Vector2i(mini(demolish_start.x, demolish_end.x), mini(demolish_start.y, demolish_end.y))
        var max_tile := Vector2i(maxi(demolish_start.x, demolish_end.x), maxi(demolish_start.y, demolish_end.y))
        var rect := Rect2(Vector2(min_tile * TILE_SIZE), Vector2((max_tile - min_tile + Vector2i.ONE) * TILE_SIZE))
        draw_rect(rect, Color(0.9, 0.2, 0.25, 0.18), true)
        draw_rect(rect, Color(1.0, 0.35, 0.4, 0.95), false, 3.0)
    elif is_in_bounds(hovered_tile) and not buildings.has(hovered_tile):
        var center := Vector2(hovered_tile * TILE_SIZE) + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
        if selected_tool == "inspect" or selected_tool == "demolish":
            draw_rect(Rect2(center - Vector2(27, 27), Vector2(54, 54)), Color(0.4, 0.9, 1.0, 0.10), false, 2.0)
            return
        var valid := _can_place_preview(hovered_tile)
        var tint := Color(0.4, 0.9, 1.0, 0.18) if valid else Color(1.0, 0.35, 0.35, 0.20)
        draw_rect(Rect2(center - Vector2(27, 27), Vector2(54, 54)), tint, true)
        _draw_arrow(center, build_direction, Color("#75e4f3") if valid else Color("#ff6b6b"))

func _can_place_preview(tile: Vector2i) -> bool:
    var definition: Dictionary = DataRegistry.buildings.get(selected_tool, {})
    if GameState.credits < int(definition.get("cost", 0)):
        return false
    if selected_tool == "miner" and not terrain.get(tile, {}).has("resource"):
        return false
    return true
