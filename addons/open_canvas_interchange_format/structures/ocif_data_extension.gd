## Class for data extensions found within an OCIF file, the Open Canvas Interchange Format.
## See OCIFDocument and OCIFState for importing and exporting OCIF files.
@tool
class_name OCIFDataExtension
extends Resource


func get_type() -> String:
	printerr("OCIFDataExtension: The `get_type()` function must be overridden.")
	assert(false)
	return ""


func to_dictionary() -> Dictionary:
	printerr("OCIFDataExtension: The `to_dictionary()` function must be overridden.")
	assert(false)
	return {}
