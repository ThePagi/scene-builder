@tool
extends Resource
class_name CollectionNames

@export var names_and_colors: Dictionary[String, Color] = {}

func check_new_collections():
	var base_dir = resource_path.get_base_dir()
	if not base_dir or base_dir.is_empty():
		return
	var dirs = DirAccess.open(base_dir).get_directories()
	for dir in dirs:
		if dir not in names_and_colors:
			if len(DirAccess.get_files_at(base_dir + "/" + dir)) == 0:
				DirAccess.remove_absolute(base_dir + "/" + dir)
			else:
				names_and_colors[dir] = Color.WHITE
			notify_property_list_changed()
	for n in names_and_colors.keys():
		if n not in dirs:
			DirAccess.open(resource_path.get_base_dir()).make_dir_recursive(n)

func _validate_property(property: Dictionary) -> void:
	if property["name"] == "names_and_colors":
		check_new_collections()
