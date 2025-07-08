## Class for data extensions found within an OCIF file, the Open Canvas Interchange Format.
## See OCIFDocument and OCIFState for importing and exporting OCIF files.
@tool
class_name OCIFDataExtension
extends Resource


func generate_node(ocif_state: OCIFState) -> CanvasItem:
	return null


func get_type() -> String:
	return ""


func to_dictionary(ocif_state: OCIFState) -> Dictionary:
	printerr("OCIFDataExtension: The `to_dictionary()` function must be overridden.")
	assert(false)
	return {}
