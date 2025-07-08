## OCIF resource class for nesting OCIF files within an OCIF file.
## See OCIFDocument and OCIFState for importing and exporting OCIF files.
@tool
class_name OCIFNested
extends OCIFDataExtension


@export var nested_ocif_document := OCIFDocument.new()
@export var nested_ocif_state := OCIFState.new()
@export var ocif_file_extension: String = ".ocif"
@export var source_file_path: String = ""


static func import_looks_like_ocif_nested(ocif_representation: Dictionary) -> bool:
	if ocif_representation.has("mimeType"):
		return ocif_representation["mimeType"] == "application/ocif+json"
	if ocif_representation.has("location"):
		var location: String = ocif_representation["location"]
		# Since we are importing, we don't know where this came from, so we need to handle both extensions.
		return location.ends_with(".ocif") or location.ends_with(".ocif.json")
	if ocif_representation.has("content"):
		var content: String = ocif_representation["content"]
		return content.begins_with("data:application/ocif+json;")
	return false


static func from_dictionary(parent_ocif_state: OCIFState, ocif_representation: Dictionary) -> OCIFNested:
	var ret := OCIFNested.new()
	if ocif_representation.has("location"):
		var path: String = parent_ocif_state.base_path.path_join(ocif_representation["location"])
		ret.source_file_path = path
		ret.nested_ocif_state.base_path = path.get_base_dir()
		ret.nested_ocif_state.filename = path.get_file()
		var err: Error = ret.nested_ocif_document.import_append_from_file(ret.nested_ocif_state, path)
		if err != OK:
			printerr("OCIF import: OCIFNested: Error while importing nested OCIF document from file '" + path + "': Error " + str(err) + ".")
			return null
	return ret


func generate_node(ocif_state: OCIFState) -> CanvasItem:
	var node: CanvasItem = nested_ocif_document.import_generate_godot_scene(nested_ocif_state)
	node.scene_file_path = source_file_path
	return node


func export_set_source_file_path(parent_ocif_state: OCIFState, scene_file_path: String) -> void:
	source_file_path = scene_file_path
	var requested_base_name: String = scene_file_path.get_file().get_basename().to_lower()
	var requested_id: String = requested_base_name + ocif_file_extension
	# While OCIFState.reserve_unique_id() will reserve a unique ID, it doesn't quite do what we want, so we need our own reserve logic here.
	# Example: If the ID "something.ocif" is already taken, reserving will give us "something.ocif2", but we want "something2.ocif" instead.
	var discriminator: int = 2
	while parent_ocif_state.unique_ids.has(requested_id):
		requested_id = requested_base_name + str(discriminator) + ocif_file_extension
		discriminator += 1
	resource_name = parent_ocif_state.reserve_unique_id(requested_id)
	nested_ocif_state.filename = resource_name
	# Prevent "something.ocif" from containing another OCIF file named "something.ocif" to avoid confusion.
	nested_ocif_state.unique_ids[resource_name] = true


func export_append_from_godot_scene(scene_root: Node) -> Error:
	if not resource_name.ends_with(ocif_file_extension):
		printerr("OCIF export: OCIFNested: The unique ID is not set properly. It should end with '" + ocif_file_extension + "'.")
	return nested_ocif_document.export_append_from_godot_scene(nested_ocif_state, scene_root)


func export_change_root_node_id(desired_root_id: String) -> void:
	var root_ocif_node: OCIFNode = nested_ocif_state.ocif_nodes[nested_ocif_state.root_node_id]
	nested_ocif_state.ocif_nodes.erase(nested_ocif_state.root_node_id)
	root_ocif_node.id = desired_root_id
	var new_ocif_nodes: Dictionary[String, OCIFNode] = {}
	new_ocif_nodes[desired_root_id] = root_ocif_node
	for ocif_node_id in nested_ocif_state.ocif_nodes:
		var ocif_node: OCIFNode = nested_ocif_state.ocif_nodes[ocif_node_id]
		if ocif_node.parent_id == nested_ocif_state.root_node_id:
			ocif_node.parent_id = desired_root_id
		new_ocif_nodes[ocif_node.id] = ocif_node
	nested_ocif_state.ocif_nodes = new_ocif_nodes
	nested_ocif_state.root_node_id = desired_root_id


func to_dictionary(parent_ocif_state: OCIFState) -> Dictionary:
	var relative_path: String = parent_ocif_state.filename.get_basename().path_join(resource_name)
	var absolute_path: String = parent_ocif_state.base_path.path_join(relative_path)
	var err: Error = nested_ocif_document.export_write_to_filesystem(nested_ocif_state, absolute_path)
	if err != OK:
		printerr("OCIF export: OCIFNested: Error while exporting nested OCIF document to filesystem: Error " + str(err) + ".")
		return {}
	return {
		"location": relative_path,
		"mimeType": "application/ocif+json",
	}
