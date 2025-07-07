@tool
class_name OCIFDocument
extends RefCounted


static var _all_ocif_document_extensions: Array[OCIFDocumentExtension] = []
var _active_ocif_document_extensions: Array[OCIFDocumentExtension] = []


# Public functions: registering extensions and the 4 main import/export functions.
static func register_ocif_document_extension(ext: OCIFDocumentExtension, high_priority: bool = false) -> void:
	if high_priority:
		_all_ocif_document_extensions.push_front(ext)
	else:
		_all_ocif_document_extensions.append(ext)


func import_append_from_file(ocif_state: OCIFState, file_path: String) -> Error:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		printerr("OCIF import: Failed to open the file, does it exist? File path: " + file_path)
		return ERR_CANT_OPEN
	var ocif_json = JSON.parse_string(file.get_as_text(true))
	if not ocif_json is Dictionary:
		printerr("OCIF import: Failed to read JSON data from disk. Does the file contain UTF-8 text representing a valid JSON object? File path: " + file_path)
		return ERR_INVALID_DATA
	ocif_state.base_path = file_path.get_base_dir()
	ocif_state.filename = file_path.get_file()
	return _import_parse_ocif_data(ocif_state, ocif_json)


func import_generate_godot_scene(ocif_state: OCIFState) -> Node:
	var root := Control.new()
	root.name = ocif_state.filename.get_basename()
	# Generate nodes.
	for ocif_node in ocif_state.ocif_nodes.values():
		if ocif_node.parent_id.is_empty():
			_import_generate_scene_node(ocif_state, ocif_node, root, root)
	# Modify generated nodes.
	for ocif_node in ocif_state.ocif_nodes.values():
		_import_modify_scene_node(ocif_state, ocif_node)
	# Run import post for extensions.
	for ext in _active_ocif_document_extensions:
		var error: Error = ext.import_post(ocif_state, root)
		if error != OK:
			printerr("OCIF import: Encountered error " + str(error) + " while running import post for an extension.")
	return root


func export_append_from_godot_scene(ocif_state: OCIFState, scene_root: Node) -> Error:
	var root_class_name: String = scene_root.get_class()
	if root_class_name not in ["Node", "CanvasItem", "Node2D", "Control"]:
		push_warning("OCIF export: Expected the root node to be a plain node. The root node will not be exported, so the data in your " + root_class_name + " root will not be included in the OCIF file.")
	# Extension export preflight.
	_active_ocif_document_extensions.clear()
	for ext in _all_ocif_document_extensions:
		var error: Error = ext.export_preflight(ocif_state, scene_root)
		if error == OK:
			_active_ocif_document_extensions.append(ext)
		elif error != ERR_SKIP:
			printerr("OCIF export: Encountered error " + str(error) + " while running export preflight for an extension.")
	return _export_convert_godot_scene(ocif_state, scene_root)


func export_write_to_filesystem(ocif_state: OCIFState, file_path: String) -> Error:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		printerr("OCIF export: Failed to open the file for writing. File path: " + file_path)
		return ERR_CANT_OPEN
	var ocif_json: Dictionary = _export_serialize_ocif_data(ocif_state)
	var json_string: String = JSON.stringify(ocif_json, "\t")
	file.store_string(json_string + "\n")
	file.close()
	return OK


# Import process.
func _import_parse_ocif_data(ocif_state: OCIFState, ocif_json: Dictionary) -> Error:
	# OCIF header.
	if not ocif_json.has("ocif"):
		printerr("OCIF import: The OCIF file does not contain the required 'ocif' key in the root object.")
	else:
		var ocif_version_string: String = String(ocif_json["ocif"]).split("/")[-1].trim_prefix("v")
		var ocif_version: PackedStringArray = ocif_version_string.split(".")
		if ocif_version[0].to_int() > 0:
			printerr("OCIF import: Unsupported version " + ocif_version_string)
	# Extension import preflight.
	_active_ocif_document_extensions.clear()
	for ext in _all_ocif_document_extensions:
		var error: Error = ext.import_preflight(ocif_state, ocif_json)
		if error == OK:
			_active_ocif_document_extensions.append(ext)
		elif error != ERR_SKIP:
			printerr("OCIF import: Encountered error " + str(error) + " while running import preflight for an extension.")
	# Parse parts.
	_import_parse_resources(ocif_state, ocif_json)
	_import_parse_nodes(ocif_state, ocif_json)
	_import_parse_relations(ocif_state, ocif_json)
	return OK


func _import_parse_resources(ocif_state: OCIFState, ocif_json: Dictionary) -> void:
	if not ocif_json.has("resources"):
		return
	var resources_json: Array = ocif_json["resources"]
	for resource_json in resources_json:
		var ocif_resource := OCIFItem.from_dictionary(resource_json)
		ocif_state.append_ocif_resource(ocif_resource)
		for ext in _active_ocif_document_extensions:
			ext.import_parse_ocif_resource(ocif_state, ocif_resource)


func _import_parse_nodes(ocif_state: OCIFState, ocif_json: Dictionary) -> void:
	if not ocif_json.has("nodes"):
		return
	var nodes_json: Array = ocif_json["nodes"]
	for node_json in nodes_json:
		var ocif_node := OCIFNode.from_dictionary(node_json)
		ocif_state.append_ocif_node(ocif_node)
		for ext in _active_ocif_document_extensions:
			ext.import_parse_ocif_node(ocif_state, ocif_node)


func _import_parse_relations(ocif_state: OCIFState, ocif_json: Dictionary) -> void:
	if not ocif_json.has("relations"):
		return
	var relations_json: Array = ocif_json["relations"]
	for relation_json in relations_json:
		var ocif_relation := OCIFItem.from_dictionary(relation_json)
		ocif_state.append_ocif_relation(ocif_relation)
		# Import relations built into OCIFDocument.
		for relation_data in ocif_relation.ocif_data:
			if relation_data is Dictionary and relation_data.has("type"):
				if relation_data["type"] == "@ocif/rel/parent-child":
					var parent: OCIFNode = ocif_state.ocif_nodes.get(relation_data.get("parent"))
					var child: OCIFNode = ocif_state.ocif_nodes.get(relation_data.get("child"))
					if parent != null and child != null:
						parent.child_ids.append(relation_data["child"])
						child.parent_id = relation_data["parent"]
				elif relation_data["type"] == "@ocif/rel/group":
					ocif_state.ocif_node_groups[ocif_relation.id] = relation_data["members"]
		# Run import parse relations for extensions.
		for ext in _active_ocif_document_extensions:
			ext.import_parse_ocif_relation(ocif_state, ocif_relation)


func _import_generate_scene_node(ocif_state: OCIFState, ocif_node: OCIFNode, scene_parent: CanvasItem, scene_root: CanvasItem) -> void:
	# Generate a node, checking extensions first.
	var current_node: CanvasItem = null
	for ext in _active_ocif_document_extensions:
		current_node = ext.import_generate_scene_node(ocif_state, ocif_node, scene_parent)
		if current_node != null:
			break
	if current_node == null:
		current_node = ocif_node.to_godot_node(ocif_state.ocif_nodes)
	ocif_state.godot_nodes[ocif_node.id] = current_node
	# If the node is in any OCIF groups, add the node to Godot groups.
	for group_name in ocif_state.ocif_node_groups:
		for node_id in ocif_state.ocif_node_groups[group_name]:
			if node_id == ocif_node.id:
				current_node.add_to_group(group_name, true)
				break
	# Add the node to the generated scene.
	scene_parent.add_child(current_node)
	current_node.propagate_call(&"set_owner", [scene_root], true)
	# Check if any child nodes need to be generated.
	if ocif_node.child_ids.size() > 0:
		for child_id in ocif_node.child_ids:
			var child_node: OCIFNode = ocif_state.ocif_nodes[child_id]
			_import_generate_scene_node(ocif_state, child_node, current_node, scene_root)


func _import_modify_scene_node(ocif_state: OCIFState, ocif_node: OCIFNode) -> void:
	var godot_scene_node: CanvasItem = ocif_state.godot_nodes[ocif_node.id]
	for ext in _active_ocif_document_extensions:
		var error: Error = ext.import_modify_scene_node(ocif_state, ocif_node, godot_scene_node)
		if error != OK:
			break


# Export process.
func _export_convert_godot_scene(ocif_state: OCIFState, scene_root: Node) -> Error:
	for node in scene_root.get_children():
		var error: Error = _export_convert_godot_scene_node(ocif_state, node, "", scene_root)
		if error != OK:
			return error
	return OK


func _export_convert_godot_scene_node(ocif_state: OCIFState, current_node: Node, parent_id: String, scene_root: Node) -> Error:
	var ocif_node := OCIFNode.from_godot_node(current_node, scene_root)
	ocif_node.parent_id = parent_id
	ocif_state.append_ocif_node(ocif_node)
	ocif_state.godot_nodes[ocif_node.id] = current_node
	# Is this node in any Godot groups? If so, add it to OCIF groups.
	for group_name in current_node.get_groups():
		if not group_name.begins_with("_"):
			ocif_state.add_ocif_node_to_group(ocif_node, group_name)
	# Check if we need to create a parent/child relation.
	if not parent_id.is_empty():
		var relation := OCIFItem.new()
		relation.id = parent_id + "/" + ocif_node.id
		relation.ocif_data = [{
			"child": ocif_node.id,
			"parent": parent_id,
			"type": "@ocif/rel/parent-child",
		}]
		ocif_state.append_ocif_relation(relation)
		# Also append the relative transform.
		var local_transform: Transform3D = ocif_node.get_local_transform(ocif_state.ocif_nodes)
		var rel_node_ext: Dictionary = {
			"source": parent_id,
			"type": "@ocif/node/relative",
		}
		if not local_transform.origin.is_zero_approx():
			if is_zero_approx(local_transform.origin.z):
				rel_node_ext["position"] = [local_transform.origin.x, local_transform.origin.y]
			else:
				rel_node_ext["position"] = [local_transform.origin.x, local_transform.origin.y, local_transform.origin.z]
		var rot_radians: float = local_transform.basis.get_euler().z
		if not is_zero_approx(rot_radians):
			rel_node_ext["rotation"] = rad_to_deg(rot_radians)
		ocif_node.ocif_data.append(rel_node_ext)
	# Run convert scene node for extensions.
	for ext in _active_ocif_document_extensions:
		var error: Error = ext.export_convert_scene_node(ocif_state, ocif_node, current_node, scene_root)
		if error != OK:
			return error
	# Convert child nodes.
	for node in current_node.get_children():
		var error: Error = _export_convert_godot_scene_node(ocif_state, node, ocif_node.id, scene_root)
		if error != OK:
			return error
	return OK


func _export_serialize_ocif_data(ocif_state: OCIFState) -> Dictionary:
	var ocif_json: Dictionary = {
		"ocif": "https://canvasprotocol.org/ocif/v0.4",
	}
	# Serialize nodes.
	var nodes_json: Array[Dictionary] = []
	for ocif_node in ocif_state.ocif_nodes.values():
		nodes_json.append(ocif_node.to_dictionary())
	if not nodes_json.is_empty():
		ocif_json["nodes"] = nodes_json
	# Serialize relations.
	var relations_json: Array = []
	for ocif_relation in ocif_state.relations.values():
		relations_json.append(ocif_relation.to_dictionary())
	for ocif_group_name in ocif_state.ocif_node_groups:
		relations_json.append({
			"data": [{
				"members": ocif_state.ocif_node_groups[ocif_group_name],
				"type": "@ocif/rel/group",
			}],
			"id": ocif_group_name,
		})
	if not relations_json.is_empty():
		ocif_json["relations"] = relations_json
	# Serialize resources.
	var resources_json: Array = []
	for ocif_resource in ocif_state.resources.values():
		resources_json.append(ocif_resource.to_dictionary("representations"))
	if not resources_json.is_empty():
		ocif_json["resources"] = resources_json
	# Run export post for extensions.
	for ext in _active_ocif_document_extensions:
		ext.export_post(ocif_state, ocif_json)
	return ocif_json
