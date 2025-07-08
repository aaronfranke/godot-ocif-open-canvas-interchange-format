## Class for nodes found within an OCIF file, the Open Canvas Interchange Format.
## See OCIFDocument and OCIFState for importing and exporting OCIF files.
@tool
class_name OCIFNode
extends OCIFItem


# Relation properties.
@export var parent_id: String = ""
@export var child_ids := PackedStringArray()

# Misc properties.
@export var additional_data: Dictionary[String, Variant] = {}
@export var resource: String = ""
@export var visible: bool = true

# Global transform properties (relative to the document root).
@export var global_position: Vector3 = Vector3()
@export var global_scale: Vector3 = Vector3.ONE
@export var global_rotation_degrees: float = 0.0
@export var size: Vector2 = Vector2()


func apply_to_godot_node(ocif_state: OCIFState, godot_node: Node) -> void:
	godot_node.name = id
	if godot_node is CanvasItem:
		godot_node.z_index = global_position.z
		godot_node.visible = visible
		var local_transform: Transform3D = get_local_transform(ocif_state.ocif_nodes)
		if godot_node is Control or godot_node is Node2D:
			godot_node.position = Vector2(local_transform.origin.x, local_transform.origin.y)
			var scale_3d: Vector3 = local_transform.basis.get_scale()
			godot_node.scale = Vector2(scale_3d.x, scale_3d.y)
			godot_node.rotation_degrees = rad_to_deg(local_transform.basis.get_euler().z)
			if godot_node is Control:
				godot_node.size = size


static func from_godot_node(node: Node, scene_root: Node) -> OCIFNode:
	var ret := OCIFNode.new()
	ret.id = node.name
	if node is CanvasItem:
		if node != scene_root:
			# The scene root is always visible and not transformed relative to itself.
			ret.visible = node.visible
			var global_transform: Transform3D = _node_scene_global_transform_3d(node, scene_root)
			ret.global_position = global_transform.origin
			ret.global_scale = global_transform.basis.get_scale()
			ret.global_rotation_degrees = rad_to_deg(global_transform.basis.get_euler().z)
		if node is Control:
			ret.size = node.size
	return ret


func to_godot_node(ocif_state: OCIFState) -> CanvasItem:
	var ret := Control.new()
	apply_to_godot_node(ocif_state, ret)
	return ret


static func from_dictionary(json: Dictionary) -> OCIFNode:
	var ret := OCIFNode.new()
	if json.has("id"):
		ret.id = json["id"]
	if json.has("data"):
		ret.ocif_data = json["data"]
	if json.has("resource"):
		ret.resource = json["resource"]
	if json.has("visible"):
		ret.visible = json["visible"]
	# Read transform properties.
	if json.has("position"):
		var pos_array: Array = json["position"]
		if pos_array.size() == 2:
			ret.global_position = Vector3(pos_array[0], pos_array[1], 0.0)
		elif pos_array.size() >= 3:
			ret.global_position = Vector3(pos_array[0], pos_array[1], pos_array[2])
	if json.has("scale"):
		var scale_array: Array = json["scale"]
		if scale_array.size() == 1:
			ret.global_scale = Vector3(scale_array[0], scale_array[0], scale_array[0])
		elif scale_array.size() == 2:
			ret.global_scale = Vector3(scale_array[0], scale_array[1], 1.0)
		elif scale_array.size() >= 3:
			ret.global_scale = Vector3(scale_array[0], scale_array[1], scale_array[2])
	if json.has("size"):
		var size_array: Array = json["size"]
		if size_array.size() == 1:
			ret.size = Vector2(size_array[0], size_array[0])
		elif size_array.size() >= 2:
			ret.size = Vector2(size_array[0], size_array[1])
	if json.has("rotation"):
		ret.global_rotation_degrees = json["rotation"]
	return ret


func to_dictionary(ocif_state: OCIFState, data_key: String = "data") -> Dictionary:
	assert(data_key == "data", "OCIFNode's data key should be `data`.")
	var ret: Dictionary = super.to_dictionary(ocif_state, data_key)
	if resource != "":
		ret["resource"] = resource
	if not visible:
		ret["visible"] = visible
	# Write transform properties.
	if global_position != Vector3():
		if global_position.z == 0.0:
			ret["position"] = [global_position.x, global_position.y]
		else:
			ret["position"] = [global_position.x, global_position.y, global_position.z]
	if global_scale != Vector3.ONE:
		ret["scale"] = [global_scale.x, global_scale.y, global_scale.z]
	ret["size"] = [size.x, size.y]
	if global_rotation_degrees != 0.0:
		ret["rotation"] = global_rotation_degrees
	return ret


# Transform functions. Note that these use Transform3D but the units are
# still in 2D space, logical pixels, Y-down, rotations are clockwise.
func get_global_transform() -> Transform3D:
	var basis := Basis.from_scale(global_scale)
	basis = basis.rotated(Vector3(0.0, 0.0, 1.0), deg_to_rad(global_rotation_degrees))
	return Transform3D(basis, global_position)


func get_local_transform(ocif_nodes: Dictionary[String, OCIFNode]) -> Transform3D:
	var global_transform: Transform3D = get_global_transform()
	if parent_id.is_empty():
		return global_transform
	var parent_node: OCIFNode = ocif_nodes[parent_id]
	var parent_transform: Transform3D = parent_node.get_global_transform()
	return parent_transform.affine_inverse() * global_transform


# Private helper functions.
static func _node_local_transform_3d(current_node: CanvasItem) -> Transform3D:
	var ret := Transform3D.IDENTITY
	# CanvasItem directly has a Transform2D getter, so use that for robustness.
	var transform_2d: Transform2D = current_node.get_transform()
	ret.origin = Vector3(transform_2d.origin.x, transform_2d.origin.y, current_node.z_index)
	var scale_2d: Vector2 = transform_2d.get_scale()
	var basis_3d := Basis.from_scale(Vector3(scale_2d.x, scale_2d.y, 1.0))
	basis_3d = basis_3d.rotated(Vector3.BACK, transform_2d.get_rotation())
	ret.basis = basis_3d
	return ret


static func _node_scene_global_transform_3d(current_node: CanvasItem, scene_root: Node) -> Transform3D:
	if current_node == scene_root:
		return Transform3D.IDENTITY # The scene root cannot be transformed relative to itself.
	var ret: Transform3D = _node_local_transform_3d(current_node)
	var parent: Node = current_node.get_parent()
	if parent != scene_root and parent is CanvasItem:
		var parent_transform: Transform3D = _node_scene_global_transform_3d(parent, scene_root)
		ret = parent_transform * ret
		if not current_node.z_as_relative:
			ret.origin.z = current_node.z_index
	return ret


static func _vector_2d_to_3d(vec2d: Vector2) -> Vector3:
	return Vector3(vec2d.x, vec2d.y, 0.0)
