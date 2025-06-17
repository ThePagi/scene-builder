@tool
extends Resource
class_name CollectionNames

@export var names_and_colors: Dictionary[String, Color] = {}

func check_new_collections():
	var dirs = DirAccess.open(resource_path.get_base_dir()).get_directories()
	for dir in dirs:
		print("Dir ", dir)
		if dir not in names_and_colors:
			names_and_colors[dir] = Color.WHITE
			notify_property_list_changed()
	for n in names_and_colors.keys():
		print("N ", n)
		if n not in dirs:
			DirAccess.open(resource_path.get_base_dir()).make_dir_recursive(n)
	
func _init() -> void:
	check_new_collections()

func _validate_property(property: Dictionary) -> void:
	if property["name"] == "names_and_colors":
		check_new_collections()
