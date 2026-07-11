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

# Simulation tuning
const TICK := 0.1
const BELT_SPEED := 1.6      # tiles per second an item travels
const ITEM_GAP := 0.30       # minimum spacing between items along a belt (tile units)

var terrain: Dictionary = {}
var buildings: Dictionary = {}
var selected_tool := "inspect"
var build_direction := 1
var demolish_start := Vector2i(-1, -1)
var demolish_end := Vector2i(-1, -1)
var hovered_tile := Vector2i.ZERO
var simulation_accumulator := 0.0
var rng := RandomNumberGenerator.new()
var _last_placed_tile := NO_TILE

func _ready() -> void:
	rng.seed = 1701
	_generate_terrain()
	_place_initial_hub()
	queue_redraw()

func _process(delta: float) -> void:
	GameState.played_seconds += delta
	simulation_accumulator += delta
	while simulation_accumulator >= TICK:
		simulation_accumulator -= TICK
		_machine_step(TICK)
	_belt_step(delta)
	queue_redraw()

# --- Tools & input --------------------------------------------------------

func set_tool(tool_id: String) -> void:
	if DataRegistry.buildings.has(tool_id) and not GameState.is_building_unlocked(tool_id):
		status_changed.emit("%s is locked — research it first" % DataRegistry.buildings[tool_id].get("name", tool_id))
		return
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
	if selected_tool != "belt" or _last_placed_tile == NO_TILE:
		return
	if not is_in_bounds(tile) or tile == _last_placed_tile:
		return
	var delta := tile - _last_placed_tile
	if absi(delta.x) + absi(delta.y) != 1:
		return
	var direction := _direction_from_delta(delta)
	build_direction = direction
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

func release_click(_tile: Vector2i) -> void:
	if demolish_start.x >= 0:
		_commit_demolish()
		demolish_start = Vector2i(-1, -1)
		demolish_end = Vector2i(-1, -1)

# --- Placement ------------------------------------------------------------

func place_building(type_id: String, tile: Vector2i, direction: int, quiet := false) -> bool:
	if not DataRegistry.buildings.has(type_id) or buildings.has(tile):
		return false
	if type_id != "hub" and not GameState.is_building_unlocked(type_id):
		if not quiet:
			status_changed.emit("%s is locked — research it first" % DataRegistry.buildings[type_id].get("name", type_id))
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
	buildings[tile] = _new_building(type_id, tile, direction)
	GameState.changed.emit()
	if not quiet:
		status_changed.emit("Built %s" % definition.get("name", type_id))
	return true

func _new_building(type_id: String, tile: Vector2i, direction: int) -> Dictionary:
	return {
		"type": type_id,
		"x": tile.x,
		"y": tile.y,
		"direction": direction,
		"inventory": {},
		"output": [],
		"items": [],
		"progress": 0.0,
		"recipe": _default_recipe(type_id),
		"fuel": 0.0
	}

func _place_initial_hub() -> void:
	var tile := Vector2i(WORLD_SIZE.x / 2, WORLD_SIZE.y / 2)
	buildings[tile] = _new_building("hub", tile, 0)

func _has_hub() -> bool:
	for building: Dictionary in buildings.values():
		if building.type == "hub":
			return true
	return false

# --- Persistence ----------------------------------------------------------

func serialize() -> Dictionary:
	var building_rows: Array[Dictionary] = []
	for tile: Vector2i in buildings:
		building_rows.append(buildings[tile].duplicate(true))
	return {"buildings": building_rows}

func restore(payload: Dictionary) -> void:
	if payload.is_empty():
		return
	buildings.clear()
	for row: Dictionary in payload.get("buildings", []):
		var tile := Vector2i(int(row.get("x", 0)), int(row.get("y", 0)))
		if not row.has("items"):
			row["items"] = []
			for legacy in row.get("output", []):
				row["items"].append({"id": String(legacy), "pos": 0.0})
			if row.get("type", "") == "belt":
				row["output"] = []
		buildings[tile] = row
	if not _has_hub():
		_place_initial_hub()

# --- Power ----------------------------------------------------------------

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

# --- Recipes --------------------------------------------------------------

func _default_recipe(type_id: String) -> String:
	var options := recipes_for_machine(type_id)
	return options[0] if not options.is_empty() else ""

func recipes_for_machine(machine: String) -> Array[String]:
	var out: Array[String] = []
	for recipe_id: String in DataRegistry.recipes:
		if String(DataRegistry.recipes[recipe_id].get("machine", "")) != machine:
			continue
		if GameState.is_recipe_unlocked(recipe_id):
			out.append(recipe_id)
	return out

func set_recipe(tile: Vector2i, recipe_id: String) -> void:
	if not buildings.has(tile):
		return
	if not GameState.is_recipe_unlocked(recipe_id):
		status_changed.emit("That recipe is locked")
		return
	var building: Dictionary = buildings[tile]
	building.recipe = recipe_id
	building.progress = 0.0
	building.inventory = {}
	building.output = []
	var output_name := String(DataRegistry.items.get(DataRegistry.recipes[recipe_id].output, {}).get("name", recipe_id))
	status_changed.emit("Now producing %s" % output_name)
	selection_changed.emit(building)

# --- Machine simulation (fixed tick) --------------------------------------

func _machine_step(dt: float) -> void:
	var power := grid_power()
	var efficiency := float(power.efficiency)
	for tile: Vector2i in buildings.keys():
		var building: Dictionary = buildings[tile]
		match building.type:
			"miner": _update_miner(building, dt * efficiency)
			"storage": _update_storage(building)
			"furnace", "assembler": _update_processor(building, dt * efficiency)
			"generator": _update_generator(building, dt)

func _update_miner(building: Dictionary, dt: float) -> void:
	var tile := Vector2i(building.x, building.y)
	var resource := String(terrain.get(tile, {}).get("resource", ""))
	if resource == "":
		return
	if building.output.size() >= 1:
		_emit_output(building)
		return
	building.progress += dt / 1.2
	if building.progress >= 1.0:
		building.progress = 0.0
		building.output.append(resource)
	_emit_output(building)

func _update_processor(building: Dictionary, dt: float) -> void:
	if building.output.size() > 0:
		_emit_output(building)
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
		_emit_output(building)

func _update_storage(building: Dictionary) -> void:
	if not building.output.is_empty():
		_emit_output(building)
	if building.output.size() >= 2:
		return
	for item_id: String in building.inventory.keys():
		if int(building.inventory[item_id]) > 0:
			building.inventory[item_id] = int(building.inventory[item_id]) - 1
			if int(building.inventory[item_id]) <= 0:
				building.inventory.erase(item_id)
			building.output.append(item_id)
			return

func _update_generator(building: Dictionary, dt: float) -> void:
	if building.fuel > 0.0:
		building.fuel = maxf(0.0, float(building.fuel) - dt)
	elif int(building.inventory.get("coal", 0)) > 0:
		building.inventory.coal = int(building.inventory.coal) - 1
		building.fuel = 12.0

func _emit_output(building: Dictionary) -> void:
	if building.output.is_empty():
		return
	var tile := Vector2i(building.x, building.y)
	if _push_to(tile, int(building.direction), String(building.output[0])):
		building.output.pop_front()

# --- Belt simulation (per frame, smooth) ----------------------------------

func _belt_step(delta: float) -> void:
	for tile: Vector2i in buildings.keys():
		var building: Dictionary = buildings[tile]
		if building.type == "belt":
			_advance_belt(tile, building, delta)

func _advance_belt(tile: Vector2i, belt: Dictionary, delta: float) -> void:
	var items: Array = belt.items
	if items.is_empty():
		return
	var step := BELT_SPEED * delta
	# Advance from the front (highest pos) to the back so items never overlap.
	for i in range(items.size() - 1, -1, -1):
		var ceiling := 1.0
		if i < items.size() - 1:
			ceiling = float(items[i + 1].pos) - ITEM_GAP
		var target: float = minf(float(items[i].pos) + step, minf(ceiling, 1.0))
		if target > float(items[i].pos):
			items[i].pos = target
	# Hand the leading item to the next tile once it reaches the exit.
	var lead: Dictionary = items[items.size() - 1]
	if float(lead.pos) >= 0.999 and _push_to(tile, int(belt.direction), String(lead.id)):
		items.remove_at(items.size() - 1)

func _push_to(from_tile: Vector2i, direction: int, item_id: String) -> bool:
	var next_tile: Vector2i = from_tile + DIRECTIONS[direction]
	if not buildings.has(next_tile):
		return false
	var target: Dictionary = buildings[next_tile]
	if target.type == "belt":
		return _belt_accept(target, item_id)
	return _receive_item(target, item_id)

func _belt_accept(belt: Dictionary, item_id: String) -> bool:
	var items: Array = belt.items
	if not items.is_empty() and float(items[0].pos) < ITEM_GAP:
		return false
	items.insert(0, {"id": item_id, "pos": 0.0})
	return true

func _receive_item(building: Dictionary, item_id: String) -> bool:
	if building.type == "hub":
		var value := int(DataRegistry.items.get(item_id, {}).get("value", 0))
		GameState.add_delivery(item_id, 1, value)
		return true
	if building.type == "generator":
		if item_id != "coal":
			return false
		building.inventory.coal = int(building.inventory.get("coal", 0)) + 1
		return true
	if building.type == "storage":
		if building.output.size() + _total_inventory(building) >= 40:
			return false
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

# --- Terrain --------------------------------------------------------------

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
			var cell := {"shade": rng.randf_range(0.0, 1.0)}
			if resource != "":
				cell["resource"] = resource
				cell["rocks"] = _make_rocks(tile)
			terrain[tile] = cell

func _make_rocks(tile: Vector2i) -> Array:
	var local := RandomNumberGenerator.new()
	local.seed = int(tile.x) * 73856093 ^ int(tile.y) * 19349663
	var rocks: Array = []
	for _i in 5:
		rocks.append({
			"offset": Vector2(local.randf_range(-18.0, 18.0), local.randf_range(-18.0, 18.0)),
			"radius": local.randf_range(4.0, 8.0)
		})
	return rocks

# =========================================================================
# Rendering
# =========================================================================

func _dir_vec(direction: int) -> Vector2:
	return Vector2(DIRECTIONS[direction])

func _tile_center(tile: Vector2i) -> Vector2:
	return Vector2(tile * TILE_SIZE) + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)

func _draw() -> void:
	_draw_terrain()
	for tile: Vector2i in buildings:
		if buildings[tile].type == "belt":
			_draw_belt(tile, buildings[tile])
	for tile: Vector2i in buildings:
		if buildings[tile].type != "belt":
			_draw_machine(tile, buildings[tile])
	for tile: Vector2i in buildings:
		if buildings[tile].type == "belt":
			_draw_belt_items(tile, buildings[tile])
	_draw_previews()

func _draw_terrain() -> void:
	for tile: Vector2i in terrain:
		var info: Dictionary = terrain[tile]
		var shade := float(info.shade)
		var checker := 0.03 if (tile.x + tile.y) % 2 == 0 else 0.0
		var base := Color("#0f171d").lerp(Color("#182530"), shade * 0.6 + checker)
		var origin := Vector2(tile * TILE_SIZE)
		draw_rect(Rect2(origin, Vector2(TILE_SIZE, TILE_SIZE)), base)
		draw_rect(Rect2(origin, Vector2(TILE_SIZE, TILE_SIZE)), Color(0.30, 0.44, 0.50, 0.06), false, 1.0)
		if info.has("resource"):
			var color := Color(DataRegistry.items.get(info.resource, {}).get("color", "#ffffff"))
			var center := _tile_center(tile)
			for rock: Dictionary in info.get("rocks", []):
				var p: Vector2 = center + rock.offset
				draw_circle(p, float(rock.radius) + 1.5, Color(0, 0, 0, 0.25))
				draw_circle(p, float(rock.radius), color.darkened(0.25))
				draw_circle(p - Vector2(1.5, 2.0), float(rock.radius) * 0.45, color.lightened(0.25))

func _draw_belt(tile: Vector2i, belt: Dictionary) -> void:
	var center := _tile_center(tile)
	var dir := _dir_vec(int(belt.direction))
	var perp := Vector2(-dir.y, dir.x)
	draw_rect(Rect2(center - Vector2(28, 28), Vector2(56, 56)), Color("#1c262d"))
	draw_rect(Rect2(center - Vector2(26, 26), Vector2(52, 52)), Color("#242f38"))
	draw_rect(Rect2(center - Vector2(26, 26), Vector2(52, 52)), Color("#31434e"), false, 1.5)
	var phase := fmod(Time.get_ticks_msec() / 1000.0 * BELT_SPEED, 1.0)
	for k in 3:
		var f := fmod(phase + float(k) / 3.0, 1.0)
		var p := center + dir * ((f - 0.5) * 50.0)
		var tip := p + dir * 5.0
		var back := p - dir * 4.0
		draw_polyline(PackedVector2Array([back + perp * 7.0, tip, back - perp * 7.0]), Color("#4f6f7d", 0.85), 2.5, true)

func _draw_belt_items(tile: Vector2i, belt: Dictionary) -> void:
	var center := _tile_center(tile)
	var dir := _dir_vec(int(belt.direction))
	for item: Dictionary in belt.items:
		var p: Vector2 = center + dir * ((float(item.pos) - 0.5) * 52.0)
		_draw_item(p, String(item.id))

func _draw_item(p: Vector2, item_id: String) -> void:
	var col := Color(DataRegistry.items.get(item_id, {}).get("color", "#ffffff"))
	draw_circle(p + Vector2(1, 2), 9.0, Color(0, 0, 0, 0.35))
	draw_circle(p, 8.5, col.darkened(0.30))
	draw_circle(p, 7.0, col)
	draw_circle(p - Vector2(2, 2.5), 2.5, col.lightened(0.45))

func _draw_machine(tile: Vector2i, building: Dictionary) -> void:
	var definition: Dictionary = DataRegistry.buildings.get(building.type, {})
	var center := _tile_center(tile)
	var base := Color(definition.get("color", "#667783"))
	var working := _is_working(building)
	if working:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		draw_circle(center, 34.0, Color(1.0, 0.75, 0.35, 0.10 + 0.10 * pulse))
	# shadow + beveled body
	draw_rect(Rect2(center - Vector2(24, 22) + Vector2(3, 5), Vector2(48, 48)), Color(0, 0, 0, 0.30))
	draw_rect(Rect2(center - Vector2(24, 24), Vector2(48, 48)), base.darkened(0.40))
	draw_rect(Rect2(center - Vector2(21, 21), Vector2(42, 42)), base)
	draw_rect(Rect2(center - Vector2(21, 21), Vector2(42, 10)), base.lightened(0.16))
	draw_rect(Rect2(center - Vector2(21, 21), Vector2(42, 42)), base.lightened(0.25), false, 1.5)
	_draw_glyph(center, building, working)
	if building.type != "hub" and building.type != "generator":
		_draw_arrow(center + _dir_vec(int(building.direction)) * 20.0, int(building.direction), Color("#8fe6f3"))
	if building.output.size() > 0:
		_draw_item(center + Vector2(14, -14), String(building.output[0]))

func _is_working(building: Dictionary) -> bool:
	match building.type:
		"miner", "furnace", "assembler": return float(building.progress) > 0.001
		"generator": return float(building.fuel) > 0.0
	return false

func _draw_glyph(center: Vector2, building: Dictionary, working: bool) -> void:
	match building.type:
		"miner":
			draw_colored_polygon(PackedVector2Array([center + Vector2(-10, -8), center + Vector2(10, -8), center + Vector2(0, 12)]), Color("#d7e7ee"))
			draw_rect(Rect2(center + Vector2(-3, -16), Vector2(6, 8)), Color("#d7e7ee"))
		"furnace":
			var mouth := Color("#ff8a3c") if working else Color("#3a2519")
			draw_rect(Rect2(center + Vector2(-11, -2), Vector2(22, 12)), mouth)
			draw_rect(Rect2(center + Vector2(-11, -12), Vector2(22, 6)), Color("#e8d2c2"))
		"assembler":
			draw_arc(center, 12.0, 0.0, TAU, 20, Color("#d3e2ea"), 3.0, true)
			draw_circle(center, 4.0, Color("#d3e2ea"))
			for a in 6:
				var ang := TAU * float(a) / 6.0
				var d := Vector2(cos(ang), sin(ang))
				draw_line(center + d * 12.0, center + d * 16.0, Color("#d3e2ea"), 3.0, true)
		"generator":
			var glow := Color("#ffb347") if working else Color("#6b5d3a")
			draw_circle(center, 12.0, glow.darkened(0.2))
			draw_circle(center, 7.0, glow.lightened(0.2))
		"storage":
			draw_rect(Rect2(center - Vector2(13, 13), Vector2(26, 26)), Color("#8f9aa5"), false, 2.0)
			draw_line(center + Vector2(-13, 0), center + Vector2(13, 0), Color("#8f9aa5"), 2.0)
			draw_line(center + Vector2(0, -13), center + Vector2(0, 13), Color("#8f9aa5"), 2.0)
		"hub":
			draw_arc(center, 15.0, 0.0, TAU, 24, Color("#a9ecf7"), 3.0, true)
			draw_colored_polygon(PackedVector2Array([center + Vector2(0, -9), center + Vector2(9, 0), center + Vector2(0, 9), center + Vector2(-9, 0)]), Color("#d7f6fb"))

func _draw_arrow(tip: Vector2, direction: int, color: Color) -> void:
	var vector := _dir_vec(direction)
	var perpendicular := Vector2(-vector.y, vector.x)
	draw_line(tip - vector * 12.0, tip, color, 3.0, true)
	draw_line(tip, tip - vector * 8.0 + perpendicular * 6.0, color, 3.0, true)
	draw_line(tip, tip - vector * 8.0 - perpendicular * 6.0, color, 3.0, true)

func _draw_previews() -> void:
	if demolish_start.x >= 0:
		var min_tile := Vector2i(mini(demolish_start.x, demolish_end.x), mini(demolish_start.y, demolish_end.y))
		var max_tile := Vector2i(maxi(demolish_start.x, demolish_end.x), maxi(demolish_start.y, demolish_end.y))
		var rect := Rect2(Vector2(min_tile * TILE_SIZE), Vector2((max_tile - min_tile + Vector2i.ONE) * TILE_SIZE))
		draw_rect(rect, Color(0.9, 0.2, 0.25, 0.16), true)
		draw_rect(rect, Color(1.0, 0.4, 0.45, 0.9), false, 2.5)
		return
	if not is_in_bounds(hovered_tile) or buildings.has(hovered_tile):
		return
	var center := _tile_center(hovered_tile)
	if selected_tool == "inspect" or selected_tool == "demolish":
		draw_rect(Rect2(center - Vector2(27, 27), Vector2(54, 54)), Color(0.5, 0.9, 1.0, 0.10), false, 2.0)
		return
	var valid := _can_place_preview(hovered_tile)
	var tint := Color(0.4, 0.9, 1.0, 0.16) if valid else Color(1.0, 0.4, 0.4, 0.18)
	draw_rect(Rect2(center - Vector2(26, 26), Vector2(52, 52)), tint, true)
	draw_rect(Rect2(center - Vector2(26, 26), Vector2(52, 52)), (Color("#8fe6f3") if valid else Color("#ff7070")), false, 2.0)
	_draw_arrow(center + _dir_vec(build_direction) * 20.0, build_direction, Color("#8fe6f3") if valid else Color("#ff7070"))

func _can_place_preview(tile: Vector2i) -> bool:
	var definition: Dictionary = DataRegistry.buildings.get(selected_tool, {})
	if GameState.credits < int(definition.get("cost", 0)):
		return false
	if not GameState.is_building_unlocked(selected_tool):
		return false
	if selected_tool == "miner" and not terrain.get(tile, {}).has("resource"):
		return false
	return true
