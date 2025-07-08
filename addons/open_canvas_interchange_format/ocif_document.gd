@tool
class_name OCIFDocument
extends Resource


static var _all_ocif_document_extensions: Array[OCIFDocumentExtension] = []
var _active_ocif_document_extensions: Array[OCIFDocumentExtension] = []


enum ExportNestedScenes {
	## Allow nested OCIF files if a scene is purely referencing other Godot scenes, allowing for a deep hierarchy.
	ALLOW_NESTED_FILES = 0,
	## Merge the nested scenes into the main OCIF file, guaranteeing a single self-contained OCIF file (depth = 0).
	MERGE_INTO_SINGLE_FILE = 1,
	## Merge the nested scenes into one layer of leaf OCIF files, giving at most a flat hierarchy (depth = 0 or 1).
	MERGE_INTO_FLAT_HIERARCHY = 2,
}
## The OCIF format usually has all nodes contained in one file (depth = 0) but also allows for a hierarchy of files (depth > 0).
## This option only affects exporting. It controls how nested Godot scenes are exported to OCIF files.
@export var export_nested_scenes: ExportNestedScenes = ExportNestedScenes.ALLOW_NESTED_FILES


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


func import_generate_godot_scene(ocif_state: OCIFState) -> CanvasItem:
	# Generate nodes.
	var root: CanvasItem
	if ocif_state.ocif_nodes.has(ocif_state.root_node_id):
		# If the OCIF file has an explicit scene root node, use it.
		var ocif_root_node: OCIFNode = ocif_state.ocif_nodes[ocif_state.root_node_id]
		root = _import_generate_scene_node(ocif_state, ocif_root_node, null, null)
	else:
		# If this OCIF file does not have an explicit scene root node, create one implicitly.
		root = Control.new()
		root.name = ocif_state.filename.get_basename()
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
	file_path = ProjectSettings.globalize_path(file_path)
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		printerr("OCIF export: Failed to open the file for writing. File path: " + file_path)
		return ERR_CANT_OPEN
	ocif_state.base_path = file_path.get_base_dir()
	ocif_state.filename = file_path.get_file()
	_export_prepare_for_serialization(ocif_state)
	# Actually export the OCIF data.
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
	_import_resolve_implicit_relations(ocif_state)
	return OK


func _import_parse_resources(ocif_state: OCIFState, ocif_json: Dictionary) -> void:
	if not ocif_json.has("resources"):
		return
	var resources_json: Array = ocif_json["resources"]
	for resource_json in resources_json:
		var ocif_resource := OCIFItem.from_dictionary(resource_json)
		for i in range(ocif_resource.ocif_data.size()):
			# Parse OCIF representations which we have built-in support for.
			var representation_dict: Dictionary = ocif_resource.ocif_data[i]
			if OCIFNested.import_looks_like_ocif_nested(representation_dict):
				var ocif_nested := OCIFNested.from_dictionary(ocif_state, representation_dict)
				if ocif_nested != null:
					ocif_resource.ocif_data[i] = ocif_nested
		ocif_state.append_ocif_resource(ocif_resource)
		# Extensions can also provide code for parsing resources.
		for ext in _active_ocif_document_extensions:
			ext.import_parse_ocif_resource(ocif_state, ocif_resource)


func _import_parse_nodes(ocif_state: OCIFState, ocif_json: Dictionary) -> void:
	if ocif_json.has("rootNode"):
		ocif_state.root_node_id = ocif_json["rootNode"]
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


func _import_resolve_implicit_relations(ocif_state: OCIFState) -> void:
	# Nodes are implicitly parented to the scene root, so we need to set the parent ID for all nodes that do not have one.
	if ocif_state.ocif_nodes.has(ocif_state.root_node_id):
		var ocif_root_node: OCIFNode = ocif_state.ocif_nodes[ocif_state.root_node_id]
		for ocif_node in ocif_state.ocif_nodes.values():
			if ocif_node.parent_id.is_empty() and ocif_node.id != ocif_state.root_node_id:
				ocif_node.parent_id = ocif_state.root_node_id
				ocif_root_node.child_ids.append(ocif_node.id)


func _import_generate_scene_node(ocif_state: OCIFState, ocif_node: OCIFNode, scene_parent: CanvasItem, scene_root: CanvasItem) -> CanvasItem:
	# Generate a node, checking extensions first.
	var current_node: CanvasItem = null
	for ext in _active_ocif_document_extensions:
		current_node = ext.import_generate_scene_node(ocif_state, ocif_node, scene_parent)
		if current_node != null:
			break
	# If no extension generated the node directly, try using a resource representation.
	if current_node == null and not ocif_node.resource.is_empty():
		if not ocif_state.resources.has(ocif_node.resource):
			printerr("OCIF import: Node '" + ocif_node.id + "' uses resource '" + ocif_node.resource + "' but it is not defined in the OCIF file.")
		else:
			var resource: OCIFItem = ocif_state.resources[ocif_node.resource]
			for representation in resource.ocif_data:
				if representation is OCIFDataExtension:
					current_node = representation.generate_node(ocif_state)
					if current_node != null:
						ocif_node.apply_to_godot_node(ocif_state, current_node)
						break
	# If no extension or resource representation generated the node, use the default OCIFNode to Godot node conversion.
	if current_node == null:
		current_node = ocif_node.to_godot_node(ocif_state)
	ocif_state.godot_nodes[ocif_node.id] = current_node
	# If the node is in any OCIF groups, add the node to Godot groups.
	for group_name in ocif_state.ocif_node_groups:
		for node_id in ocif_state.ocif_node_groups[group_name]:
			if node_id == ocif_node.id:
				current_node.add_to_group(group_name, true)
				break
	# Note: scene_parent and scene_root will both be null if this is the root node, otherwise both will be non-null.
	if scene_parent == null:
		scene_root = current_node
	else:
		# Add the node to the generated scene.
		scene_parent.add_child(current_node)
		_import_propagate_owner(current_node, scene_root)
	# Check if any child nodes need to be generated.
	if ocif_node.child_ids.size() > 0:
		for child_id in ocif_node.child_ids:
			var child_node: OCIFNode = ocif_state.ocif_nodes[child_id]
			_import_generate_scene_node(ocif_state, child_node, current_node, scene_root)
	return current_node


func _import_propagate_owner(current_node: Node, scene_root: Node) -> void:
	current_node.set_owner(scene_root)
	if not current_node.scene_file_path.is_empty():
		return
	for child in current_node.get_children():
		_import_propagate_owner(child, scene_root)


func _import_modify_scene_node(ocif_state: OCIFState, ocif_node: OCIFNode) -> void:
	var godot_scene_node: CanvasItem = ocif_state.godot_nodes[ocif_node.id]
	for ext in _active_ocif_document_extensions:
		var error: Error = ext.import_modify_scene_node(ocif_state, ocif_node, godot_scene_node)
		if error != OK:
			break


# Export process.
func _export_convert_godot_scene(ocif_state: OCIFState, scene_root: Node) -> Error:
	ocif_state.root_node_id = scene_root.name
	var error: Error = _export_convert_godot_scene_node(ocif_state, scene_root, "", scene_root)
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
	# Most nodes are implicitly parented to the scene root, so this is only needed if the parent is not the scene root.
	if not parent_id.is_empty() and parent_id != scene_root.name:
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
	# Does this node need to be exported as a separate OCIF file?
	if export_nested_scenes != ExportNestedScenes.MERGE_INTO_SINGLE_FILE:
		if current_node != scene_root and not current_node.scene_file_path.is_empty():
			# In this case, this is a nested scene which needs to go into its own OCIF file.
			var ocif_nested_resource_id: String = _export_get_or_create_ocif_nested(ocif_state, current_node)
			if ocif_nested_resource_id.is_empty():
				return ERR_INVALID_DATA
			ocif_node.resource = ocif_nested_resource_id
			# Return here, don't run extension logic or act on child nodes. Those are handled by the nested OCIF file.
			return OK
	# By this point, we've determined that this node goes in the current OCIF file.
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


func _export_get_or_create_ocif_nested(ocif_state: OCIFState, current_node: Node) -> String:
	# We need an OCIFNested resource, but first, check if we already have one to avoid creating duplicates.
	for resource in ocif_state.resources.values():
		var repesentations: Array = resource.ocif_data
		if repesentations.size() == 1 and repesentations[0] is OCIFNested:
			var ocif_nested: OCIFNested = repesentations[0] as OCIFNested
			if ocif_nested.source_file_path == current_node.scene_file_path:
				# We already have an OCIFNested resource for this scene, so we can reuse it.
				# But first... if we have two instances of the same OCIFNested, ensure its root node's ID is based on the file name.
				var desired_root_id: String = current_node.scene_file_path.get_file().get_basename().capitalize()
				if ocif_nested.nested_ocif_state.root_node_id != desired_root_id:
					ocif_nested.export_change_root_node_id(desired_root_id)
				return resource.id
	# If we reach here, we need to create a new OCIFNested resource.
	var ocif_nested := OCIFNested.new()
	ocif_nested.export_set_source_file_path(ocif_state, current_node.scene_file_path)
	if export_nested_scenes == ExportNestedScenes.MERGE_INTO_FLAT_HIERARCHY:
		ocif_nested.nested_ocif_document.export_nested_scenes = ExportNestedScenes.MERGE_INTO_SINGLE_FILE
	var err: Error = ocif_nested.export_append_from_godot_scene(current_node)
	if err != OK:
		printerr("OCIF export: Failed to convert nested scene from node '" + current_node.name + "'. Error: " + str(err))
		return ""
	# Append the resource containing the OCIFNested to the OCIFState. Don't use `append_ocif_resource` because we've already reserved the unique ID.
	var ocif_nested_resource := OCIFItem.new()
	var id: String = ocif_nested.resource_name
	ocif_nested_resource.id = id
	ocif_nested_resource.ocif_data = [ocif_nested]
	ocif_state.resources[id] = ocif_nested_resource
	ocif_state.export_needs_subfolder = true
	return id


func _export_prepare_for_serialization(ocif_state: OCIFState) -> Error:
	if ocif_state.export_needs_subfolder:
		# If we need a subfolder, create it.
		var subfolder_path: String = ocif_state.base_path.path_join(ocif_state.filename.get_basename())
		if not DirAccess.dir_exists_absolute(subfolder_path):
			var err: Error = DirAccess.make_dir_absolute(subfolder_path)
			if err != OK:
				printerr("OCIF export: Failed to create subfolder for OCIF file at path: " + subfolder_path)
				return err
	return OK


func _export_serialize_ocif_data(ocif_state: OCIFState) -> Dictionary:
	var ocif_json: Dictionary = {
		"ocif": "https://canvasprotocol.org/ocif/v0.6",
	}
	# Serialize nodes.
	if not ocif_state.root_node_id.is_empty():
		ocif_json["rootNode"] = ocif_state.root_node_id
	var nodes_json: Array[Dictionary] = []
	for ocif_node in ocif_state.ocif_nodes.values():
		nodes_json.append(ocif_node.to_dictionary(ocif_state))
	if not nodes_json.is_empty():
		ocif_json["nodes"] = nodes_json
	# Serialize relations.
	var relations_json: Array = []
	for ocif_relation in ocif_state.relations.values():
		relations_json.append(ocif_relation.to_dictionary(ocif_state))
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
		resources_json.append(ocif_resource.to_dictionary(ocif_state, "representations"))
	if not resources_json.is_empty():
		ocif_json["resources"] = resources_json
	# Run export post for extensions.
	for ext in _active_ocif_document_extensions:
		ext.export_post(ocif_state, ocif_json)
	return ocif_json
