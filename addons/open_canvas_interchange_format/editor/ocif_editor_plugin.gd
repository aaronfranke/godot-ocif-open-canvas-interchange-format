## Most of this file is for exporting OCIF files.
@tool
extends EditorPlugin


var _file_dialog: EditorFileDialog
var _import_plugin: EditorImportPluginOCIF


func _enter_tree() -> void:
	# Register extensions. Note: This only runs in the editor.
	var ext: OCIFDocumentExtension
	ext = AnchoredNodeOCIFDocumentExtension.new()
	OCIFDocument.register_ocif_document_extension(ext)
	if not Engine.is_editor_hint():
		return
	# Set up the editor import plugin.
	_import_plugin = EditorImportPluginOCIF.new()
	add_import_plugin(_import_plugin, true)
	# Set up the editor export file dialog.
	_file_dialog = EditorFileDialog.new()
	_file_dialog.set_file_mode(EditorFileDialog.FILE_MODE_SAVE_FILE)
	_file_dialog.set_access(EditorFileDialog.ACCESS_FILESYSTEM)
	_file_dialog.clear_filters()
	_file_dialog.add_filter("*.ocif")
	_file_dialog.add_filter("*.ocif.json")
	_file_dialog.title = "Export Scene to OCIF File (Open Canvas Interchange Format)"
	_file_dialog.file_selected.connect(_export_scene_as_ocif)
	EditorInterface.get_base_control().add_child(_file_dialog)
	# Add a button to the Scene -> Export menu to pop up the settings dialog.
	var export_menu: PopupMenu = get_export_as_menu()
	var index: int = export_menu.get_item_count()
	export_menu.add_item("Open Canvas Interchange Format...")
	export_menu.set_item_metadata(index, _try_begin_ocif_editor_export)


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		return
	_file_dialog.queue_free()
	remove_import_plugin(_import_plugin)


func _try_begin_ocif_editor_export() -> void:
	_popup_ocif_editor_export_dialog()


func _popup_ocif_editor_export_dialog() -> void:
	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if scene_root == null:
		printerr("OCIF error: Cannot export scene without a root node.")
		return
	# Set the file dialog's file name to the scene name.
	var filename: String = scene_root.get_scene_file_path().get_file().get_basename()
	if filename.is_empty():
		filename = scene_root.get_name()
	_file_dialog.set_current_file(filename + ".ocif")
	# Show the file dialog.
	_file_dialog.popup_centered_ratio()


func _export_scene_as_ocif(file_path: String) -> void:
	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if scene_root == null:
		printerr("OCIF editor export error: Cannot export scene without a root node.")
		return
	var ocif_doc := OCIFDocument.new()
	var ocif_state := OCIFState.new()
	var err: Error = ocif_doc.export_append_from_godot_scene(ocif_state, scene_root)
	if err != OK:
		printerr("OCIF editor export: Error while running export_append_from_godot_scene")
		return
	err = ocif_doc.export_write_to_filesystem(ocif_state, file_path)
	if err != OK:
		printerr("OCIF editor export: Error while running export_write_to_filesystem")
		return
