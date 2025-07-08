## Godot editor integration for importing OCIF files. See OCIFDocument.
@tool
class_name EditorImportPluginOCIF
extends EditorImportPlugin


func _get_format_version() -> int:
	return 0


func _get_import_options(path: String, preset_index: int) -> Array[Dictionary]:
	# Work-around for https://github.com/godotengine/godot/issues/105456
	return [{
		"name": "scene",
		"default_value": true
	}]


func _get_import_order() -> int:
	return 100


func _get_importer_name():
	return "ocif.scene"


func _get_option_visibility(path: String, option_name: StringName, options: Dictionary) -> bool:
	return false


func _get_preset_count() -> int:
	return 0


func _get_priority() -> float:
	return 10.0


func _get_recognized_extensions() -> PackedStringArray:
	return ["ocif.json", "ocif"]


func _get_resource_type():
	return "PackedScene"


func _get_save_extension():
	return "scn"


func _get_visible_name():
	return "OCIF Scene"


func _import(source_file: String, save_path: String, options: Dictionary, platform_variants: Array[String], gen_files: Array[String]) -> Error:
	var ocif_doc := OCIFDocument.new()
	var ocif_state := OCIFState.new()
	var err: Error = ocif_doc.import_append_from_file(ocif_state, source_file)
	if err != OK:
		return err
	var scene_root: Node = ocif_doc.import_generate_godot_scene(ocif_state)
	if scene_root == null:
		return ERR_INVALID_DATA
	var packed_scene := PackedScene.new()
	err = packed_scene.pack(scene_root)
	if err != OK:
		return err
	return ResourceSaver.save(packed_scene, save_path + ".scn")
