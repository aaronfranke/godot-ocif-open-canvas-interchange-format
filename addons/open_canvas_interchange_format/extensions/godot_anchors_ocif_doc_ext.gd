## OCIF extension for Godot anchors and offsets.
@tool
class_name GodotAnchorsOCIFDocumentExtension
extends OCIFDocumentExtension


const SCHEMA: Dictionary[String, Variant] = {
	"$schema": "https://json-schema.org/draft/2020-12/schema",
	"title": "@godot/node/anchors",
	"description": "Anchor points and offsets, which determine how a node is placed and resized relative to a parent with a finite non-zero size.",
	"type": "object",
	"properties": {
		"anchors": {
			"type": "array",
			"description": "The anchor points of the node, as a percentage of the parent's size. An anchor of 0.0 is relative to the parent's left or top edge, an anchor of 1.0 is relative to the parent's right or bottom edge, and an anchor of 0.5 is relative to the parent's center. Values are stored in clockwise [-X, -Y, +X, +Y] order.",
			"items": {
				"type": "number"
			},
			"minItems": 4,
			"maxItems": 4
		},
		"offsets": {
			"type": "array",
			"description": "The offsets from the anchor points, in logical pixels. Positive values move to the right or down. An offset of 0.0 is at the anchor point. Values are stored in clockwise [-X, -Y, +X, +Y] order.",
			"items": {
				"type": "number"
			},
			"minItems": 4,
			"maxItems": 4
		}
	}
}


func import_modify_scene_node(ocif_state: OCIFState, ocif_node: OCIFNode, godot_scene_node: CanvasItem) -> Error:
	if not godot_scene_node is Control:
		return OK
	var control_node: Control = godot_scene_node
	for data_json in ocif_node.ocif_data:
		if not data_json.has("type"):
			return ERR_INVALID_DATA
		if data_json["type"] == "@godot/node/anchors":
			if data_json.has("anchors"):
				var anchors = data_json["anchors"]
				if not anchors is Array or anchors.size() != 4:
					return ERR_INVALID_DATA
				control_node.anchor_left = anchors[0]
				control_node.anchor_top = anchors[1]
				control_node.anchor_right = anchors[2]
				control_node.anchor_bottom = anchors[3]
			if data_json.has("offsets"):
				var offsets = data_json["offsets"]
				if not offsets is Array or offsets.size() != 4:
					return ERR_INVALID_DATA
				control_node.offset_left = offsets[0]
				control_node.offset_top = offsets[1]
				control_node.offset_right = offsets[2]
				control_node.offset_bottom = offsets[3]
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
	ocif_state.additional_data["GodotAnchors"] = true
	ocif_node.ocif_data.append({
		"anchors": [scene_control.anchor_left, scene_control.anchor_top, scene_control.anchor_right, scene_control.anchor_bottom],
		"offsets": [scene_control.offset_left, scene_control.offset_top, scene_control.offset_right, scene_control.offset_bottom],
		"type": "@godot/node/anchors",
	})
	return OK


func export_post(ocif_state: OCIFState, ocif_json: Dictionary) -> Error:
	if not ocif_state.additional_data.has("GodotAnchors"):
		return OK
	var godot_anchors: Dictionary = {
		"name": "@godot/node/anchors",
		"uri": "TODO",
	}
	if include_schema:
		godot_anchors["schema"] = SCHEMA
	var schemas: Array = ocif_json.get_or_add("schemas", [])
	schemas.append(godot_anchors)
	return OK
