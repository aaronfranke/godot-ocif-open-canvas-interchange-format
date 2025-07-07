## OCIF extension for Godot anchors and offsets.
@tool
class_name AnchoredNodeOCIFDocumentExtension
extends OCIFDocumentExtension


const SCHEMA: Dictionary[String, Variant] = {
	"$schema": "https://json-schema.org/draft/2020-12/schema",
	"$id": "https://spec.canvasprotocol.org/v0.6/extensions/anchored-node.json",
	"title": "@ocif/node/anchored",
	"description": "Anchored node extension for relative positioning anchored to a parent item",
	"type": "object",
	"properties": {
		"type": {
			"type": "string",
			"const": "@ocif/node/anchored"
		},
		"topLeftAnchor": {
			"description": "Top left anchor as percentage coordinates",
			"oneOf": [
				{
					"type": "array",
					"items": {
						"type": "number"
					},
					"minItems": 2,
					"maxItems": 2
				},
				{
					"type": "array",
					"items": {
						"type": "number"
					},
					"minItems": 3,
					"maxItems": 3
				}
			],
			"default": [0.0, 0.0]
		},
		"bottomRightAnchor": {
			"description": "Bottom-right anchor as percentage coordinates",
			"oneOf": [
				{
					"type": "array",
					"items": {
						"type": "number"
					},
					"minItems": 2,
					"maxItems": 2
				},
				{
					"type": "array",
					"items": {
						"type": "number"
					},
					"minItems": 3,
					"maxItems": 3
				}
			],
			"default": [1.0, 1.0]
		},
		"topLeftOffset": {
			"description": "Top left offset as absolute coordinates",
			"oneOf": [
				{
					"type": "array",
					"items": {
						"type": "number"
					},
					"minItems": 2,
					"maxItems": 2
				},
				{
					"type": "array",
					"items": {
						"type": "number"
					},
					"minItems": 3,
					"maxItems": 3
				}
			],
			"default": [0.0, 0.0]
		},
		"bottomRightOffset": {
			"description": "Bottom-right offset as absolute coordinates",
			"oneOf": [
				{
					"type": "array",
					"items": {
						"type": "number"
					},
					"minItems": 2,
					"maxItems": 2
				},
				{
					"type": "array",
					"items": {
						"type": "number"
					},
					"minItems": 3,
					"maxItems": 3
				}
			],
			"default": [0.0, 0.0]
		}
	},
	"required": ["type"]
}


func import_modify_scene_node(ocif_state: OCIFState, ocif_node: OCIFNode, godot_scene_node: CanvasItem) -> Error:
	if not godot_scene_node is Control:
		return OK
	var control_node: Control = godot_scene_node
	for data_json in ocif_node.ocif_data:
		if not data_json.has("type"):
			return ERR_INVALID_DATA
		if data_json["type"] == "@ocif/node/anchored":
			if data_json.has("topLeftAnchor"):
				var top_left_anchor = data_json["topLeftAnchor"]
				if not top_left_anchor is Array or top_left_anchor.size() < 2:
					return ERR_INVALID_DATA
				control_node.anchor_left = top_left_anchor[0]
				control_node.anchor_top = top_left_anchor[1]
			else:
				control_node.anchor_left = 0.0
				control_node.anchor_top = 0.0
			if data_json.has("bottomRightAnchor"):
				var bottom_right_anchor = data_json["bottomRightAnchor"]
				if not bottom_right_anchor is Array or bottom_right_anchor.size() < 2:
					return ERR_INVALID_DATA
				control_node.anchor_right = bottom_right_anchor[0]
				control_node.anchor_bottom = bottom_right_anchor[1]
			else:
				control_node.anchor_right = 1.0
				control_node.anchor_bottom = 1.0
			if data_json.has("topLeftOffset"):
				var top_left_offset = data_json["topLeftOffset"]
				if not top_left_offset is Array or top_left_offset.size() < 2:
					return ERR_INVALID_DATA
				control_node.offset_left = top_left_offset[0]
				control_node.offset_top = top_left_offset[1]
			else:
				control_node.offset_left = 0.0
				control_node.offset_top = 0.0
			if data_json.has("bottomRightOffset"):
				var bottom_right_offset = data_json["bottomRightOffset"]
				if not bottom_right_offset is Array or bottom_right_offset.size() < 2:
					return ERR_INVALID_DATA
				control_node.offset_right = bottom_right_offset[0]
				control_node.offset_bottom = bottom_right_offset[1]
			else:
				control_node.offset_right = 0.0
				control_node.offset_bottom = 0.0
	return OK


func export_preflight(ocif_state: OCIFState, scene_root: Node) -> Error:
	# This extension is an official OCIF extension, so exclude the schema by default.
	# If the schema is desired, other code can re-enable this boolean, or this line can be removed.
	include_schema = false
	return OK


func export_convert_scene_node(ocif_state: OCIFState, ocif_node: OCIFNode, scene_node: Node, scene_root: Node) -> Error:
	if not scene_node is Control:
		return OK # Anchors only exist on Control nodes, not Node2D or other nodes.
	var scene_control: Control = scene_node
	if (scene_control.anchor_left == 0.0
			and scene_control.anchor_top == 0.0
			and scene_control.anchor_right == 0.0
			and scene_control.anchor_bottom == 0.0):
		return OK # If anchoring to 0.0 only, then it's the same as regular positioning.
	var parent_node: Node = scene_node.get_parent()
	if parent_node == scene_root:
		return OK # Since OCIF files have no size, anchoring to the document makes no sense.
	if parent_node is Control and parent_node.size == Vector2.ZERO:
		return OK # Anchoring to a parent with zero size makes no sense.
	ocif_state.additional_data["HasAnchoredNodes"] = true
	var anchored_node_data: Dictionary = {}
	if scene_control.anchor_right != 1.0 or scene_control.anchor_bottom != 1.0:
		anchored_node_data["bottomRightAnchor"] = [scene_control.anchor_right, scene_control.anchor_bottom]
	if scene_control.offset_right != 0.0 or scene_control.offset_bottom != 0.0:
		anchored_node_data["bottomRightOffset"] = [scene_control.offset_right, scene_control.offset_bottom]
	if scene_control.anchor_left != 0.0 or scene_control.anchor_top != 0.0:
		anchored_node_data["topLeftAnchor"] = [scene_control.anchor_left, scene_control.anchor_top]
	if scene_control.offset_left != 0.0 or scene_control.offset_top != 0.0:
		anchored_node_data["topLeftOffset"] = [scene_control.offset_left, scene_control.offset_top]
	anchored_node_data["type"] = "@ocif/node/anchored"
	ocif_node.ocif_data.append(anchored_node_data)
	return OK


func export_post(ocif_state: OCIFState, ocif_json: Dictionary) -> Error:
	if not ocif_state.additional_data.has("HasAnchoredNodes"):
		return OK
	var godot_anchors: Dictionary = {
		"name": "@ocif/node/anchored",
		"uri": "https://spec.canvasprotocol.org/v0.6/extensions/anchored-node.json",
	}
	if include_schema:
		godot_anchors["schema"] = SCHEMA
	var schemas: Array = ocif_json.get_or_add("schemas", [])
	schemas.append(godot_anchors)
	return OK
