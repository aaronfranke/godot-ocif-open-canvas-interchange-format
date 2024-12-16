## Base class for items found within an OCIF file, the Open Canvas Interchange Format.
## See OCIFDocument and OCIFState for importing and exporting OCIF files.
@tool
class_name OCIFItem
extends Resource


## The unique ID of the OCIF item. This uses Godot's built-in resource name as the backing field for the ID.
@export var id: String:
	get:
		return resource_name
	set(value):
		resource_name = value

## The data contained in this OCIF item. Can be node data, relation data, resource data, or more.
@export var ocif_data: Array = []


func to_dictionary(data_key: String = "data") -> Dictionary:
	var ret: Dictionary = {
		"id": id,
	}
	if not ocif_data.is_empty():
		var json_data: Array = []
		for data in ocif_data:
			if data is OCIFDataExtension or data is OCIFItem:
				json_data.append(data.to_dictionary())
			else:
				json_data.append(data)
		ret[data_key] = json_data
	return ret


static func from_dictionary(json: Dictionary) -> OCIFItem:
	var ret := OCIFItem.new()
	if json.has("id"):
		ret.id = json["id"]
	if json.has("data"):
		ret.ocif_data = json["data"]
	elif json.has("representations"):
		ret.ocif_data = json["representations"]
	return ret
