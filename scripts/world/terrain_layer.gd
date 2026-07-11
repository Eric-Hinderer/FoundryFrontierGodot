extends Node2D
# Static terrain is drawn once instead of every frame, so belt/machine
# animation no longer pays the cost of re-rendering ~1,500 tiles per frame.

const TILE_SIZE := 64

var _terrain: Dictionary = {}

func render(terrain: Dictionary) -> void:
	_terrain = terrain
	queue_redraw()

func _draw() -> void:
	for tile: Vector2i in _terrain:
		var info: Dictionary = _terrain[tile]
		var shade := float(info.shade)
		var checker := 0.03 if (tile.x + tile.y) % 2 == 0 else 0.0
		var base := Color("#0f171d").lerp(Color("#182530"), shade * 0.6 + checker)
		var origin := Vector2(tile * TILE_SIZE)
		draw_rect(Rect2(origin, Vector2(TILE_SIZE, TILE_SIZE)), base)
		draw_rect(Rect2(origin, Vector2(TILE_SIZE, TILE_SIZE)), Color(0.30, 0.44, 0.50, 0.05), false, 1.0)
		if info.has("resource"):
			var color := Color(DataRegistry.items.get(info.resource, {}).get("color", "#ffffff"))
			var center := Vector2(tile * TILE_SIZE) + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
			for rock: Dictionary in info.get("rocks", []):
				var p: Vector2 = center + rock.offset
				draw_circle(p, float(rock.radius) + 1.5, Color(0, 0, 0, 0.25))
				draw_circle(p, float(rock.radius), color.darkened(0.25))
				draw_circle(p - Vector2(1.5, 2.0), float(rock.radius) * 0.45, color.lightened(0.25))
