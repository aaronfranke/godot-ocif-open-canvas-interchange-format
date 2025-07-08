@tool
class_name OCIFState
extends Resource


# OCIF data.
@export var ocif_nodes: Dictionary[String, OCIFNode] = {}
@export var ocif_node_groups: Dictionary[String, Array] = {} # Array[String]
@export var root_node_id: String = ""
@export var relations: Dictionary[String, OCIFItem] = {}
@export var resources: Dictionary[String, OCIFItem] = {}
# Godot data.
@export var additional_data: Dictionary[String, Variant] = {}
var godot_nodes: Dictionary[String, Node] = {}
# Metadata.
@export var filename: String = "":
	set(value):
		filename = value
		resource_name = value
## The folder path associated with the OCIF data. This is used to find other files the OCIF file references, like images or binary buffers. This will be set during import when appending from a file, and will be set during export when writing to a file.
@export var base_path: String = ""
# Export-only flag for determining if we need a subfolder or not.
@export var export_needs_subfolder: bool = false
# Use a Dictionary as a Set for unique IDs. The values are unused.
@export var unique_ids: Dictionary[String, bool] = {}


func add_ocif_node_to_group(ocif_node: OCIFNode, group_name: String) -> void:
	if not ocif_nodes.has(ocif_node.id):
		push_warning("OCIF: Adding node '" + ocif_node.id + "' to a group, but is not in the list of nodes.")
	var node_group: Array = ocif_node_groups.get_or_add(group_name, [])
	node_group.append(ocif_node.id)


func append_ocif_node(ocif_node: OCIFNode) -> void:
	var uid: String = reserve_unique_id(ocif_node.id)
	ocif_node.id = uid
	ocif_nodes[uid] = ocif_node


func append_ocif_relation(ocif_item: OCIFItem) -> void:
	var uid: String = reserve_unique_id(ocif_item.id)
	ocif_item.id = uid
	relations[uid] = ocif_item


func append_ocif_resource(ocif_item: OCIFItem) -> void:
	var uid: String = reserve_unique_id(ocif_item.id)
	ocif_item.id = uid
	resources[uid] = ocif_item


func reserve_unique_id(requested: String) -> String:
	var id: String = requested
	if unique_ids.has(id):
		var discriminator: int = 2
		while unique_ids.has(id):
			id = requested + str(discriminator)
			discriminator += 1
		push_warning("OCIF: The requested ID " + requested + " is already in use. The ID " + id + " will be used instead.")
	unique_ids[id] = true
	return id
