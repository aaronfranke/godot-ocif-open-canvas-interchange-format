## Godot editor integration for importing OCIF files. See OCIFDocument.
@tool
class_name EditorSceneFormatImporterOCIF
extends EditorSceneFormatImporter


func _get_extensions() -> PackedStringArray:
	return ["ocif.json", "ocif"]


func _get_import_flags() -> int:
	return IMPORT_SCENE


func _import_scene(path: String, flags: int, options: Dictionary) -> Node:
	var ocif_doc := OCIFDocument.new()
	var ocif_state := OCIFState.new()
	ocif_doc.import_append_from_file(ocif_state, path)
	return ocif_doc.import_generate_godot_scene(ocif_state)
