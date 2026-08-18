extends Node2D
class_name BattleMap

## 战斗地图加载器：读取 data/maps/*.json，把地形铺到 TileMap、把单位实例化为 Unit。
## 用法：建一个 Node2D 场景，挂本脚本；在检查器里把 tile_map 指向子 TileMap、
## unit_scene 指向 res://scenes/Unit.tscn；再调用 load_map("prologue_01")。

const Unit = preload("res://src/Unit.gd")

@export var tile_map: TileMap
@export var unit_scene: PackedScene
@export var tile_size: int = 64

func load_map(map_id: String) -> void:
	if tile_map == null or unit_scene == null:
		push_error("BattleMap: 请在检查器设置 tile_map 与 unit_scene")
		return

	var map: Dictionary = DataManager.get_map(map_id)
	if map.is_empty():
		push_error("BattleMap: 找不到地图 %s" % map_id)
		return

	# 1) 铺设地形瓦片
	var grid: Array = map.get("grid", [])
	for y in grid.size():
		for x in grid[y].size():
			var tid: String = grid[y][x]
			var t: Dictionary = DataManager.get_terrain(tid)
			var atlas: Array = t.get("atlas", [0, 0])
			# 参数：格坐标、图集 source_id(默认0)、图集内坐标、替代瓦片(默认-1)
			tile_map.set_cell(0, Vector2i(x, y), 0, Vector2i(int(atlas[0]), int(atlas[1])))

	# 2) 生成单位
	for u in map.get("units", []):
		var unit: Unit = unit_scene.instantiate()
		unit.setup(u)
		unit.position = Vector2(unit.grid_pos.x, unit.grid_pos.y) * tile_size \
			+ Vector2(tile_size / 2, tile_size / 2)
		add_child(unit)

	print("[BattleMap] 已加载地图 %s，单位数 %d" % [map_id, map.get("units", []).size()])
