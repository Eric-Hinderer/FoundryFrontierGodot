extends Node

@onready var world: WorldController = %World
@onready var camera: Camera2D = %Camera2D

const TOOL_HOTKEYS := {
	"build_belt": "belt",
	"build_miner": "miner",
	"build_furnace": "furnace",
	"build_generator": "generator",
	"build_assembler": "assembler",
	"build_storage": "storage",
}

var dragging_camera := false
var placing := false
var last_mouse_position := Vector2.ZERO

func _ready() -> void:
	camera.position = Vector2(WorldController.WORLD_SIZE * WorldController.TILE_SIZE) / 2.0
	var saved := GameState.load_world()
	if not saved.is_empty():
		world.restore(saved)

func _process(delta: float) -> void:
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	camera.position += move * 650.0 * delta / camera.zoom.x
	camera.position.x = clampf(camera.position.x, 0.0, WorldController.WORLD_SIZE.x * WorldController.TILE_SIZE)
	camera.position.y = clampf(camera.position.y, 0.0, WorldController.WORLD_SIZE.y * WorldController.TILE_SIZE)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("rotate_build"):
		world.rotate_build()
	elif event.is_action_pressed("demolish_mode"):
		world.set_tool("demolish")
	elif event.is_action_pressed("cancel_tool"):
		world.set_tool("inspect")
	elif event.is_action_pressed("save_game"):
		GameState.save_world(world.serialize())
	elif _handle_tool_hotkey(event):
		return
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			camera.zoom = (camera.zoom * 1.1).clamp(Vector2(0.55, 0.55), Vector2(2.2, 2.2))
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			camera.zoom = (camera.zoom / 1.1).clamp(Vector2(0.55, 0.55), Vector2(2.2, 2.2))
		elif mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			dragging_camera = mouse_event.pressed
			last_mouse_position = mouse_event.position
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			world.quick_demolish(world.tile_from_world(world.get_global_mouse_position()))
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
			var tile := world.tile_from_world(world.get_global_mouse_position())
			if mouse_event.pressed:
				placing = true
				world.primary_click(tile)
			else:
				placing = false
				world.release_click(tile)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if dragging_camera:
			camera.position -= motion.relative / camera.zoom.x
		var hover_tile := world.tile_from_world(world.get_global_mouse_position())
		world.drag_to(hover_tile)
		if placing:
			world.drag_place(hover_tile)

func _handle_tool_hotkey(event: InputEvent) -> bool:
	for action: String in TOOL_HOTKEYS:
		if event.is_action_pressed(action):
			world.set_tool(TOOL_HOTKEYS[action])
			return true
	return false
