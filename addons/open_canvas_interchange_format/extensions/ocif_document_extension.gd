## Class for extending the Godot OCIF importer and exporter, the Open Canvas Interchange Format.
## See OCIFDocument and OCIFState for importing and exporting OCIF files.
@tool
class_name OCIFDocumentExtension
extends Resource


@export var include_schema: bool = true


func import_preflight(ocif_state: OCIFState, ocif_json: Dictionary) -> Error:
	return OK


func import_parse_ocif_node(ocif_state: OCIFState, ocif_node: OCIFNode) -> Error:
	return OK


func import_parse_ocif_relation(ocif_state: OCIFState, ocif_relation: OCIFItem) -> Error:
	return OK


func import_parse_ocif_resource(ocif_state: OCIFState, ocif_resource: OCIFItem) -> Error:
	return OK


func import_generate_scene_node(ocif_state: OCIFState, ocif_node: OCIFNode, scene_parent: CanvasItem) -> CanvasItem:
	return null


func import_modify_scene_node(ocif_state: OCIFState, ocif_node: OCIFNode, godot_scene_node: CanvasItem) -> Error:
	return OK


func import_post(ocif_state: OCIFState, scene_root: CanvasItem) -> Error:
	return OK


func export_preflight(ocif_state: OCIFState, scene_root: Node) -> Error:
	return OK


func export_convert_scene_node(ocif_state: OCIFState, ocif_node: OCIFNode, scene_node: Node, scene_root: Node) -> Error:
	return OK


func export_post(ocif_state: OCIFState, ocif_json: Dictionary) -> Error:
	return OK
