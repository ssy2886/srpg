extends Node

## SaveManager —— 低层存档读写（Autoload，名称 SaveManager）。
## 只负责把一份 Dictionary 序列化到 user://save.json，以及读回/删除。
## 具体要存什么由 Campaign.serialize() / Campaign.deserialize() 决定，本类不关心业务字段。

const SAVE_PATH := "user://save.json"

## 写入存档。成功返回 true。
func save(data: Dictionary) -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: 无法打开存档文件 %s" % SAVE_PATH)
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	print("[SaveManager] 已保存存档 -> %s" % SAVE_PATH)
	return true

## 读取存档，缺失或损坏返回空字典 {}。
func load_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveManager: 存档解析失败，已忽略")
		return {}
	return parsed

## 是否存在可用存档。
func has_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	return load_save().size() > 0

## 删除存档（新游戏时调用，避免脏档干扰）。
func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
		print("[SaveManager] 已删除旧存档")
