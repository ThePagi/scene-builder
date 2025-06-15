@tool
extends EditorPlugin
class_name SceneBuilderDock

@onready var config: SceneBuilderConfig = SceneBuilderConfig.new()

# Paths
var data_dir: String = ""
var path_to_collection_names: String

# Constants

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var toolbox: SceneBuilderToolbox = SceneBuilderToolbox.new()
var undo_redo: EditorUndoRedoManager = get_undo_redo()

# Godot controls
var base_control: Control
var btn_use_local_space: Button

# SceneBuilderDock controls
var scene_builder_dock: VBoxContainer
var btns_collection_tabs: Array = [] # set in _enter_tree()
var commands: SceneBuilderCommands
# Options
var btn_use_surface_normal: CheckButton
var btn_surface_normal_x: CheckBox
var btn_surface_normal_y: CheckBox
var btn_surface_normal_z: CheckBox
var btn_parent_node_selector: Button
var btn_group_surface_orientation: ButtonGroup
var btn_find_world_3d: Button
var btn_reload_all_items: Button
var menu_command_popup: MenuButton
var btn_cmd_create_items: Button
var icon_size: HSlider
var btn_replace_overlapping: CheckButton
# Path3D
var spinbox_separation_distance: SpinBox
var spinbox_jitter_x: SpinBox
var spinbox_jitter_y: SpinBox
var spinbox_jitter_z: SpinBox
var spinbox_y_offset: SpinBox
var btn_place_fence: Button

# Indicators
var lbl_indicator_x: Label
var lbl_indicator_y: Label
var lbl_indicator_z: Label
var lbl_indicator_scale: Label

# Updated with update_world_3d()
var editor: EditorInterface
var physics_space: PhysicsDirectSpaceState3D
var world3d: World3D
var viewport: Viewport
var camera: Camera3D
var scene_root: Node3D

# Updated when reloading all collections
var collections: CollectionNames
var collection_names: Array[String] = []
var collection_colors: Array[Color] = []

# Also updated on tab button click
var selected_collection_id: int = 0
var items: Array[SceneBuilderItem] = []
var highlighters: Array[NinePatchRect] = []
# Also updated on item click
var selected_item_id: int = -1
var preview_instance: Node3D = null
var preview_instance_rid_array: Array[RID] = []

enum TransformMode {
	NONE,
	POSITION_X,
	POSITION_Y, 
	POSITION_Z,
	ROTATION_X,
	ROTATION_Y,
	ROTATION_Z,
	SCALE
}

var placement_mode_enabled: bool = false
var current_transform_mode: TransformMode = TransformMode.NONE

func is_transform_mode_enabled() -> bool:
	return current_transform_mode != TransformMode.NONE

# Preview item
var pos_offset_x: float = 0
var pos_offset_y: float = 0
var pos_offset_z: float = 0
var original_preview_position: Vector3 = Vector3.ZERO
var original_preview_basis: Basis = Basis.IDENTITY
var original_mouse_position: Vector2 = Vector2.ONE
var random_offset_y: float = 0
var original_preview_scale: Vector3 = Vector3.ONE
var scene_builder_temp: Node # Used as a parent to the preview item

var prev_parent: Node3D = null

func snap(pos: Vector3) -> Vector3:
	return (pos).snapped(items[selected_item_id].snap_to_grid)
func snap_rot(euler: Vector3) -> Vector3:
	return euler.snapped(Vector3.ONE*deg_to_rad(items[selected_item_id].snap_rotation))
func selected_parent()->Node3D:
	var sel = EditorInterface.get_selection().get_selected_nodes()
	#if len(sel) == 0:
	#	EditorInterface.get_selection().add_node(EditorInterface.get_edited_scene_root())
	#	sel = EditorInterface.get_selection().get_selected_nodes()
	if len(sel) == 1:
		if sel[0] is not Node3D:
			btn_parent_node_selector.set_node_info("A Node3D must be selected!", null)
			return null
		var node = sel[0]
		var node_name := node.get_class().split(".")[-1]
		var node_icon := get_editor_interface().get_base_control().get_theme_icon(node_name, "EditorIcons")
		
		if node_icon == get_editor_interface().get_base_control().get_theme_icon("invalid icon", "EditorIcons"):
			node_icon = get_editor_interface().get_base_control().get_theme_icon("Node", "EditorIcons")
		
		btn_parent_node_selector.set_node_info(node.name, node_icon)
		return node
	else:
		btn_parent_node_selector.set_node_info("A Node3D must be selected!", null)
		return null

func set_commands(cmd: SceneBuilderCommands):
	commands = cmd
	
# ---- Notifications -----------------------------------------------------------

func _enter_tree() -> void:
	path_to_collection_names = config.root_dir + "collection_names.tres"
	
	editor = get_editor_interface()
	base_control = EditorInterface.get_base_control()

	# Found using: https://github.com/Zylann/godot_editor_debugger_plugin
	var _panel : Panel = get_editor_interface().get_base_control()
	var _vboxcontainer15 : VBoxContainer = _panel.get_child(0)
	var _vboxcontainer26 : VBoxContainer = _vboxcontainer15.get_child(1).get_child(1).get_child(1).get_child(0)
	var _main_screen : VBoxContainer = _vboxcontainer26.get_child(0).get_child(0).get_child(0).get_child(1).get_child(0)
	var _hboxcontainer11486 : HBoxContainer = _main_screen.get_child(1).get_child(0).get_child(0).get_child(0)
	
	btn_use_local_space = _hboxcontainer11486.get_child(13)
	if !btn_use_local_space:
		printerr("[SceneBuilderDock] Unable to find use local space button")

	#region Initialize controls for the SceneBuilderDock
	
	var path : String = SceneBuilderToolbox.find_resource_with_dynamic_path("scene_builder_dock.tscn")
	if path == "":
		printerr("[SceneBuilderDock] scene_builder_dock.tscn was not found")
		return
	
	scene_builder_dock = load(path).instantiate()
	
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, scene_builder_dock)

	# Options tab
	btn_use_surface_normal = scene_builder_dock.get_node("%UseSurfaceNormal")
	btn_surface_normal_x = scene_builder_dock.get_node("%Orientation/X")
	btn_surface_normal_y = scene_builder_dock.get_node("%Orientation/Y")
	btn_surface_normal_z = scene_builder_dock.get_node("%Orientation/Z")
	
	btn_parent_node_selector = scene_builder_dock.get_node("%ParentNodeSelector")
	var script_path = SceneBuilderToolbox.find_resource_with_dynamic_path("scene_builder_node_path_selector.gd")
	if script_path != "":
		btn_parent_node_selector.set_script(load(script_path))
		#btn_parent_node_selector.path_selected.connect(set_parent_node)
	else:
		printerr("[SceneBuilderDock] Failed to find scene_builder_node_path_selector.gd")
	
	#
	btn_group_surface_orientation = ButtonGroup.new()
	btn_surface_normal_x.button_group = btn_group_surface_orientation
	btn_surface_normal_y.button_group = btn_group_surface_orientation
	btn_surface_normal_z.button_group = btn_group_surface_orientation
	#
	btn_find_world_3d = scene_builder_dock.get_node("Settings/Tab/Options/Bottom/FindWorld3D")
	btn_reload_all_items = scene_builder_dock.get_node("Settings/Tab/Options/Bottom/ReloadAllItems")
	btn_find_world_3d.pressed.connect(update_world_3d)
	btn_reload_all_items.pressed.connect(reload_all_items)
	menu_command_popup = scene_builder_dock.get_node("Settings/Tab/Options/Bottom/CommandsPopup")
	commands.fill_popup(menu_command_popup.get_popup())
	btn_cmd_create_items = scene_builder_dock.get_node("Settings/Tab/Options/QuickCommands/CreateItems")
	btn_cmd_create_items.pressed.connect(commands.create_scene_builder_items)
	icon_size = scene_builder_dock.get_node("Settings/Tab/Options/FirstRow/HBox/IconSize")
	icon_size.value_changed.connect(resize_icons)
	btn_replace_overlapping = scene_builder_dock.get_node("Settings/Tab/Options/FirstRow/HBox/ReplaceOverlapping")
	# Path3D tab
	spinbox_separation_distance = scene_builder_dock.get_node("Settings/Tab/Path3D/Separation/SpinBox")
	spinbox_jitter_x = scene_builder_dock.get_node("Settings/Tab/Path3D/Jitter/X")
	spinbox_jitter_y = scene_builder_dock.get_node("Settings/Tab/Path3D/Jitter/Y")
	spinbox_jitter_z = scene_builder_dock.get_node("Settings/Tab/Path3D/Jitter/Z")
	spinbox_y_offset = scene_builder_dock.get_node("Settings/Tab/Path3D/YOffset/Value")
	btn_place_fence = scene_builder_dock.get_node("Settings/Tab/Path3D/PlaceFence")
	btn_place_fence.pressed.connect(place_fence)

	# Indicators
	lbl_indicator_x = scene_builder_dock.get_node("Settings/Indicators/1")
	lbl_indicator_y = scene_builder_dock.get_node("Settings/Indicators/2")
	lbl_indicator_z = scene_builder_dock.get_node("Settings/Indicators/3")
	lbl_indicator_scale = scene_builder_dock.get_node("Settings/Indicators/4")

	#endregion

	# Collection tabs
	load_or_make_collections()
	#
	update_world_3d()

func resize_icons(value: float):
	for c in scene_builder_dock.get_node("Collection/Scroll/Grid").get_children():
		(c as Control).custom_minimum_size = Vector2(value, value)

func _exit_tree() -> void:
	remove_control_from_docks(scene_builder_dock)
	scene_builder_dock.queue_free()

func _process(_delta: float) -> void:
	var sel_parent = selected_parent()
	if prev_parent != sel_parent:
		end_placement_mode()
		if sel_parent:
			prev_parent = sel_parent
	# Update preview item position
	if placement_mode_enabled:
		#selected_parent()
		if not scene_root or not scene_root is Node3D or not scene_root.is_inside_tree():
			print("[SceneBuilderDock] Scene root invalid, ending placement mode")
			end_placement_mode()
			return
		
		if !is_transform_mode_enabled():
			if preview_instance:
				populate_preview_instance_rid_array(preview_instance)
			var result = perform_raycast_with_exclusion(preview_instance_rid_array)
			if result and result.collider:
				var _preview_item = scene_root.get_node_or_null("_SceneBuilderTemp")
				if _preview_item and _preview_item.get_child_count() > 0:
					var _instance: Node3D = _preview_item.get_child(0)

					var new_position: Vector3 = snap(result.position)
					new_position += items[selected_item_id].snap_offset
					new_position += Vector3(pos_offset_x, pos_offset_y, pos_offset_z)
					# This offset prevents z-fighting when placing overlapping quads
					if items[selected_item_id].use_random_vertical_offset:
						new_position.y += random_offset_y

					_instance.global_transform.origin = new_position
					if btn_use_surface_normal.button_pressed:
						_instance.basis = align_up(_instance.global_transform.basis, result.normal)
						var quaternion = Quaternion(_instance.basis.orthonormalized())
						if btn_surface_normal_x.button_pressed:
							quaternion = quaternion * Quaternion(Vector3(1, 0, 0), deg_to_rad(90))
						elif btn_surface_normal_z.button_pressed:
							quaternion = quaternion * Quaternion(Vector3(0, 0, 1), deg_to_rad(90))

func forward_3d_gui_input(_camera: Camera3D, event: InputEvent) -> AfterGUIInput:
	if event is InputEventMouseMotion:
		if placement_mode_enabled:
			var relative_motion: float
			if abs(event.relative.x) > abs(event.relative.y):
				relative_motion = event.relative.x
			else:
				relative_motion = -event.relative.y
			relative_motion *= 0.01 # Sensitivity factor

			match current_transform_mode:
				TransformMode.POSITION_X:
					pos_offset_x += relative_motion
					preview_instance.position.x = original_preview_position.x + pos_offset_x
				TransformMode.POSITION_Y:
					pos_offset_y += relative_motion
					preview_instance.position.y = original_preview_position.y + pos_offset_y
				TransformMode.POSITION_Z:
					pos_offset_z += relative_motion
					preview_instance.position.z = original_preview_position.z + pos_offset_z
				TransformMode.ROTATION_X:
					if btn_use_local_space.button_pressed:
						preview_instance.rotate_object_local(Vector3(1, 0, 0), relative_motion)
					else:
						preview_instance.rotate_x(relative_motion)
				TransformMode.ROTATION_Y:
					if btn_use_local_space.button_pressed:
						preview_instance.rotate_object_local(Vector3(0, 1, 0), relative_motion)
					else:
						preview_instance.rotate_y(relative_motion)
				TransformMode.ROTATION_Z:
					if btn_use_local_space.button_pressed:
						preview_instance.rotate_object_local(Vector3(0, 0, 1), relative_motion)
					else:
						preview_instance.rotate_z(relative_motion)
				TransformMode.SCALE:
					var new_scale: Vector3 = preview_instance.scale * (1 + relative_motion)
					if is_zero_approx(new_scale.x) or is_zero_approx(new_scale.y) or is_zero_approx(new_scale.z):
						new_scale = original_preview_scale
					preview_instance.scale = new_scale

	if event is InputEventMouseButton:
		if event.is_pressed() and !event.is_echo():
			if placement_mode_enabled:
				var mouse_pos = viewport.get_mouse_position()
				if mouse_pos.x >= 0 and mouse_pos.y >= 0:
					if mouse_pos.x <= viewport.size.x and mouse_pos.y <= viewport.size.y:
						if event.button_index == MOUSE_BUTTON_LEFT:
							if is_transform_mode_enabled():
								# Confirm changes
								#original_preview_basis = preview_instance.basis
								original_preview_scale = preview_instance.scale
								original_preview_basis = Basis.from_euler(snap_rot(preview_instance.basis.get_euler()))
								original_preview_basis = original_preview_basis.scaled(preview_instance.basis.get_scale())
								preview_instance.basis = original_preview_basis
								end_transform_mode()
								viewport.warp_mouse(original_mouse_position)
							else:
								instantiate_selected_item_at_position()
							return EditorPlugin.AFTER_GUI_INPUT_STOP

						elif event.button_index == MOUSE_BUTTON_RIGHT:
							if is_transform_mode_enabled():
								# Revert preview transformations
								print("[SceneBuilderDock] warping to: ", original_mouse_position)
								preview_instance.basis = original_preview_basis
								preview_instance.scale = original_preview_scale
								end_transform_mode()
								viewport.warp_mouse(original_mouse_position)
								return EditorPlugin.AFTER_GUI_INPUT_STOP
							else:
								end_placement_mode()
								return EditorPlugin.AFTER_GUI_INPUT_STOP

	elif event is InputEventKey:
		if event.is_pressed() and !event.is_echo():
			if !event.alt_pressed and !event.ctrl_pressed:
				if event.shift_pressed:
					if event.keycode == config.x_axis:
						if is_transform_mode_enabled():
							if current_transform_mode == TransformMode.POSITION_X:
								end_transform_mode()
							else:
								end_transform_mode()
								start_transform_mode(TransformMode.POSITION_X)
						else:
							start_transform_mode(TransformMode.POSITION_X)
						return EditorPlugin.AFTER_GUI_INPUT_STOP
					elif event.keycode == config.y_axis:
						if is_transform_mode_enabled():
							if current_transform_mode == TransformMode.POSITION_Y:
								end_transform_mode()
							else:
								end_transform_mode()
								start_transform_mode(TransformMode.POSITION_Y)
						else:
							start_transform_mode(TransformMode.POSITION_Y)
						return EditorPlugin.AFTER_GUI_INPUT_STOP
					elif event.keycode == config.z_axis:
						if is_transform_mode_enabled():
							if current_transform_mode == TransformMode.POSITION_Z:
								end_transform_mode()
							else:
								end_transform_mode()
								start_transform_mode(TransformMode.POSITION_Z)
						else:
							start_transform_mode(TransformMode.POSITION_Z)
						return EditorPlugin.AFTER_GUI_INPUT_STOP
				else:
					if event.keycode == config.x_axis:
						if is_transform_mode_enabled():
							if current_transform_mode == TransformMode.ROTATION_X:
								end_transform_mode()
							else:
								end_transform_mode()
								start_transform_mode(TransformMode.ROTATION_X)
						else:
							start_transform_mode(TransformMode.ROTATION_X)
						return EditorPlugin.AFTER_GUI_INPUT_STOP
					elif event.keycode == config.y_axis:
						if is_transform_mode_enabled():
							if current_transform_mode == TransformMode.ROTATION_Y:
								end_transform_mode()
							else:
								end_transform_mode()
								start_transform_mode(TransformMode.ROTATION_Y)
						else:
							start_transform_mode(TransformMode.ROTATION_Y)
						return EditorPlugin.AFTER_GUI_INPUT_STOP
					elif event.keycode == config.z_axis:
						if is_transform_mode_enabled():
							if current_transform_mode == TransformMode.ROTATION_Z:
								end_transform_mode()
							else:
								end_transform_mode()
								start_transform_mode(TransformMode.ROTATION_Z)
						else:
							start_transform_mode(TransformMode.ROTATION_Z)
						return EditorPlugin.AFTER_GUI_INPUT_STOP
					elif event.keycode == KEY_4:
						if is_transform_mode_enabled():
							if current_transform_mode == TransformMode.SCALE:
								end_transform_mode()
							else:
								end_transform_mode()
								start_transform_mode(TransformMode.SCALE)
						else:
							start_transform_mode(TransformMode.SCALE)
						return EditorPlugin.AFTER_GUI_INPUT_STOP
					elif event.keycode == KEY_5:
						if is_transform_mode_enabled():
							end_transform_mode()
						reroll_preview_instance_transform()
						return EditorPlugin.AFTER_GUI_INPUT_STOP
					elif event.keycode == config.rotate_90:
						preview_instance.rotate_y(deg_to_rad(90))
						return EditorPlugin.AFTER_GUI_INPUT_STOP
				if event.keycode == KEY_ESCAPE:
					end_placement_mode()
					return EditorPlugin.AFTER_GUI_INPUT_STOP

			if placement_mode_enabled:
				if event.shift_pressed:
					if event.keycode == KEY_LEFT:
						select_previous_item()
						return EditorPlugin.AFTER_GUI_INPUT_STOP
					elif event.keycode == KEY_RIGHT:
						select_next_item()
						return EditorPlugin.AFTER_GUI_INPUT_STOP

				if event.alt_pressed:
					if event.keycode == KEY_LEFT:
						select_previous_collection()
						return EditorPlugin.AFTER_GUI_INPUT_STOP
					elif event.keycode == KEY_RIGHT:
						select_next_collection()
						return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS

# ---- Buttons -----------------------------------------------------------------


func select_collection(tab_index: int) -> void:
	end_placement_mode()
	for c in scene_builder_dock.get_node("Collection/Panel/Cats").get_children():
		(c as Button).modulate = Color.WHITE
	if tab_index < 0 or tab_index >= len(collection_names):
		print("Selected collection out of bounds")
		return
	scene_builder_dock.get_node("Collection/Panel/Cats").get_child(tab_index).modulate = Color.AQUAMARINE
	selected_collection_id = tab_index
	reload_all_items()
	select_first_item()

func on_item_icon_clicked(_button_id: int) -> void:
	if !update_world_3d():
		return

	if selected_item_id != _button_id:
		select_item(_button_id)
	elif placement_mode_enabled:
		end_placement_mode()

func reload_all_items() -> void:
	var grid = scene_builder_dock.get_node("Collection/Scroll/Grid")
	for c in grid.get_children():
		c.queue_free()
	if selected_collection_id >= len(collection_names):
		print("Collection doesn't exist!")
		return
	if DirAccess.dir_exists_absolute(config.root_dir + "/%s" % collection_names[selected_collection_id]):
		load_items_from_collection_folder_on_disk(collection_names[selected_collection_id])
		for i in len(items):
			var item = items[i]
			var texture_button: TextureButton = TextureButton.new()
			texture_button.toggle_mode = true
			texture_button.texture_normal = item.texture
			texture_button.tooltip_text = item.item_name
			texture_button.ignore_texture_size = true
			texture_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT
			texture_button.custom_minimum_size = Vector2(icon_size.value, icon_size.value)
			texture_button.pressed.connect(on_item_icon_clicked.bind(i))
			grid.add_child(texture_button)

			var nine_patch: NinePatchRect = NinePatchRect.new()
			nine_patch.texture = CanvasTexture.new()
			nine_patch.draw_center = false
			nine_patch.set_anchors_preset(Control.PRESET_FULL_RECT)
			nine_patch.patch_margin_left = 4
			nine_patch.patch_margin_top = 4
			nine_patch.patch_margin_right = 4
			nine_patch.patch_margin_bottom = 4
			nine_patch.modulate.a = 0.5
			nine_patch.self_modulate = Color("000000") # black  # 6a9d2e green
			highlighters.push_back(nine_patch)
			texture_button.add_child(nine_patch)

func update_world_3d() -> bool:
	var new_scene_root = EditorInterface.get_edited_scene_root()
	if new_scene_root != null and new_scene_root is Node3D:
		if scene_root == new_scene_root:
			return true
		end_placement_mode()
		scene_root = new_scene_root
		viewport = EditorInterface.get_editor_viewport_3d()
		world3d = viewport.find_world_3d()
		physics_space = world3d.direct_space_state
		camera = viewport.get_camera_3d()
		return true
	else:
		print("[SceneBuilderDock] Failed to update world 3d")
		end_placement_mode()
		scene_root = null
		viewport = null
		world3d = null
		physics_space = null
		camera = null
		return false

# ---- Helpers -----------------------------------------------------------------

func align_up(node_basis, normal) -> Basis:
	var result: Basis = Basis()
	var scale: Vector3 = node_basis.get_scale()
	var orientation: String = btn_group_surface_orientation.get_pressed_button().name

	var arbitrary_vector: Vector3 = Vector3(1, 0, 0) if abs(normal.dot(Vector3(1, 0, 0))) < 0.999 else Vector3(0, 1, 0)
	var cross1: Vector3
	var cross2: Vector3

	match orientation:
		"X":
			cross1 = normal.cross(node_basis.y).normalized()
			if cross1.length_squared() < 0.001:
				cross1 = normal.cross(arbitrary_vector).normalized()
			cross2 = cross1.cross(normal).normalized()
			result = Basis(normal, cross2, cross1)
		"Y":
			cross1 = normal.cross(node_basis.z).normalized()
			if cross1.length_squared() < 0.001:
				cross1 = normal.cross(arbitrary_vector).normalized()
			cross2 = cross1.cross(normal).normalized()
			result = Basis(cross1, normal, cross2)
		"Z":
			arbitrary_vector = Vector3(0, 0, 1) if abs(normal.dot(Vector3(0, 0, -1))) < 0.99 else Vector3(-1, 0, 0)
			cross1 = normal.cross(node_basis.x).normalized()
			if cross1.length_squared() < 0.001:
				cross1 = normal.cross(arbitrary_vector).normalized()
			cross2 = cross1.cross(normal).normalized()
			result = Basis(cross2, cross1, normal)

	result = result.orthonormalized()
	result.x *= scale.x
	result.y *= scale.y
	result.z *= scale.z

	return result

func clear_preview_instance() -> void:
	preview_instance = null
	preview_instance_rid_array = []

	if scene_root != null:
		scene_builder_temp = scene_root.get_node_or_null("_SceneBuilderTemp")
		if scene_builder_temp:
			for child in scene_builder_temp.get_children():
				child.queue_free()

func create_preview_instance() -> void:
	if scene_root == null:
		printerr("[SceneBuilderDock] scene_root is null inside create_preview_item_instance")
		return

	clear_preview_instance()

	scene_builder_temp = scene_root.get_node_or_null("_SceneBuilderTemp")
	if not scene_builder_temp:
		scene_builder_temp = Node.new()
		scene_builder_temp.name = "_SceneBuilderTemp"
		scene_root.add_child(scene_builder_temp, false, INTERNAL_MODE_FRONT)
		scene_builder_temp.owner = scene_root
	var orig_parent = selected_parent()
	preview_instance = get_instance_from_path(items[selected_item_id].uid)
	scene_builder_temp.add_child(preview_instance)
	preview_instance.owner = scene_root

	reroll_preview_instance_transform()

	# Instantiating a node automatically selects it, which is annoying.
	# Let's re-select scene_root instead,
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(orig_parent)

func end_placement_mode() -> void:
	clear_preview_instance()
	end_transform_mode()
	if prev_parent:
		prev_parent.remove_meta("_edit_lock_")
	placement_mode_enabled = false

	if selected_item_id >= 0 and selected_item_id < len(items):
		var selected_nine_path: NinePatchRect = highlighters[selected_item_id]
		selected_nine_path.self_modulate = Color.BLACK
	selected_item_id = -1

func end_transform_mode() -> void:
	current_transform_mode = TransformMode.NONE
	reset_indicators()

func load_items_from_collection_folder_on_disk(_collection_name: String):
	print("[SceneBuilderDock] Collecting items from collection folder")
	items.clear()
	highlighters.clear()
	var dir = DirAccess.open(config.root_dir + _collection_name)
	if dir:
		dir.list_dir_begin()
		var item_filename = dir.get_next()
		while item_filename != "":
			var item_path = config.root_dir + _collection_name + "/" + item_filename
			var resource = ResourceLoader.load(item_path, "Resource", 0)
			if resource and resource is SceneBuilderItem:
				var scene_builder_item: SceneBuilderItem = resource

				#print("[SceneBuilderDock] Loaded item: ", item_filename)
				items.push_back(scene_builder_item)
			else:
				print("[SceneBuilderDock] The resource is not a SceneBuilderItem or failed to load, item_path: ", item_path)
			
			item_filename = dir.get_next()	
		dir.list_dir_end()

func get_all_node_names(_node) -> Array[String]:
	var _all_node_names = []
	for _child in _node.get_children():
		_all_node_names.append(_child.name)
		if _child.get_child_count() > 0:
			var _result = get_all_node_names(_child)
			for _item in _result:
				_all_node_names.append(_item)
	return _all_node_names

func _get_merged_aabb(node: Node, node_depth: int) -> AABB:
	var aabb := AABB()
	
	if node is GeometryInstance3D:
		aabb = node.global_transform * node.get_aabb()
	
	if node_depth > 0:
		for child in node.get_children():
			var child_aabb = _get_merged_aabb(child, node_depth - 1)
			if aabb == AABB():
				aabb = child_aabb
			elif child_aabb != AABB(): # this was fucking with the volume for some reason
				aabb = aabb.merge(child_aabb)
	
	return aabb

func _get_root_ancestor(child: Node, anc: Node) -> Node:
	var p = child.get_parent()
	if p:
		if p == anc:
			return child
		return _get_root_ancestor(p, anc)
	else:
		return null

func instantiate_selected_item_at_position() -> void:
	if preview_instance == null or selected_item_id < 0 or selected_item_id >= len(items):
		printerr("[SceneBuilderDock] Preview instance or selected item is null")
		return

	populate_preview_instance_rid_array(preview_instance)
	var result = perform_raycast_with_exclusion(preview_instance_rid_array)

	if result and result.collider:
		print(result.collider)
		var instance = get_instance_from_path(items[selected_item_id].uid)
		var parent = selected_parent()
		if not parent:
			printerr("Valid parent not selected.")
			return
		parent.add_child(instance)
		instance.owner = scene_root
		initialize_node_name(instance, items[selected_item_id].item_name)

		var new_position: Vector3 = result.position
		new_position = snap(new_position)
		new_position += items[selected_item_id].snap_offset
		
		if items[selected_item_id].use_random_vertical_offset:
			new_position.y += random_offset_y

		instance.global_transform.origin = new_position
		instance.position += Vector3(pos_offset_x, pos_offset_y, pos_offset_z)
		#print("[SceneBuilderDock] pos_offset_y: ", pos_offset_y)
		instance.basis = preview_instance.basis
		instance.basis = Basis.from_euler(snap_rot(preview_instance.basis.get_euler()))
		instance.basis = instance.basis.scaled(preview_instance.basis.get_scale())
		undo_redo.create_action("Instantiate selected item")
		undo_redo.add_undo_method(parent, "remove_child", instance)
		var hit_ancestor = _get_root_ancestor(result.collider, parent)
		if btn_replace_overlapping.button_pressed and hit_ancestor:
			var old_aabb = _get_merged_aabb(result.collider, 5)
			var new_aabb = _get_merged_aabb(instance, 5)
			var cross = old_aabb.intersection(new_aabb)
			if cross.get_volume()/new_aabb.get_volume() > 0.85\
				and (old_aabb.size-new_aabb.size).length_squared() < 1:
				parent.remove_child(hit_ancestor)
				undo_redo.add_undo_method(parent, "add_child", hit_ancestor)
		undo_redo.add_do_reference(instance)
		undo_redo.commit_action()
		reroll_preview_instance_transform()
	else:
		print("[SceneBuilderDock] Raycast missed, items must be instantiated on a StaticBody with a CollisionShape")

func initialize_node_name(node: Node3D, new_name: String) -> void:
	var all_names = toolbox.get_all_node_names(scene_root)
	node.name = toolbox.increment_name_until_unique(new_name, all_names)

func perform_raycast_with_exclusion(exclude_rids: Array = []) -> Dictionary:
	if viewport == null:
		update_world_3d()
		if viewport == null:
			print("[SceneBuilderDock] The editor's root scene must be of type Node3D, deselecting item")
			end_placement_mode()
			return {}

	var mouse_pos = viewport.get_mouse_position()
	var origin = camera.project_ray_origin(mouse_pos)
	var end = origin + camera.project_ray_normal(mouse_pos) * 1000
	var query = PhysicsRayQueryParameters3D.new()
	query.from = origin
	query.to = end
	query.exclude = exclude_rids
	return physics_space.intersect_ray(query)

## This function prevents us from trying to raycast against our preview item.
func populate_preview_instance_rid_array(instance: Node) -> void:
	if instance is PhysicsBody3D:
		preview_instance_rid_array.append(instance.get_rid())

	for child in instance.get_children():
		populate_preview_instance_rid_array(child)

func load_or_make_collections() -> void:
	print("[SceneBuilderDock] Refreshing collection names")

	if !DirAccess.dir_exists_absolute(config.root_dir):
		DirAccess.make_dir_recursive_absolute(config.root_dir)
		print("[SceneBuilderDock] Creating a new data folder: ", config.root_dir)

	if !ResourceLoader.exists(path_to_collection_names):
		var _collection_names: CollectionNames = CollectionNames.new()
		print("[SceneBuilderDock] path_to_collection_names: ", path_to_collection_names)
		var save_result = ResourceSaver.save(_collection_names, path_to_collection_names)
		print("[SceneBuilderDock] A CollectionNames resource has been created at location: ", path_to_collection_names)

		if save_result != OK:
			printerr("[SceneBuilderDock] We were unable to create a CollectionNames resource at location: ", path_to_collection_names)
			return
	var _cols: CollectionNames = load(path_to_collection_names)
	if _cols == null:
		printerr("Collection names can't be loaded")
		return
	collections = _cols
	collection_names.clear()
	collection_colors.clear()
	var cat_parent = scene_builder_dock.get_node("Collection/Panel/Cats")
	for c in cat_parent.get_children():
		c.queue_free()
	var names = collections.names_and_colors.keys().duplicate()
	names.sort()
	for n in names:
		var i = len(collection_names)
		collection_names.push_back(n)
		collection_colors.push_back(collections.names_and_colors[n])
		var butt = Button.new()
		butt.name = n
		butt.text = n
		butt.add_theme_color_override("font_color", collection_colors[i])
		butt.pressed.connect(select_collection.bind(i))
		cat_parent.add_child(butt)
	select_collection(0)
	#endregion

# ---- Shortcut ----------------------------------------------------------------

func place_fence():
	var selection: EditorSelection = EditorInterface.get_selection()
	var selected_nodes: Array[Node] = selection.get_selected_nodes()

	if scene_root == null:
		print("[SceneBuilderDock] Scene root is null")
		return

	if selected_nodes.size() != 1:
		printerr("[SceneBuilderDock] Exactly one node sould be selected in the scene")
		return

	if not selected_nodes[0] is Path3D:
		printerr("[SceneBuilderDock] The selected node should be of type Node3D")
		return

	undo_redo.create_action("Make a fence")

	var path: Path3D = selected_nodes[0]

	var path_length: float = path.curve.get_baked_length()

	for distance in range(0, path_length, spinbox_separation_distance.value):

		var transform: Transform3D = path.curve.sample_baked_with_rotation(distance)
		var position: Vector3 = transform.origin
		var basis: Basis = transform.basis.rotated(Vector3(0, 1, 0), deg_to_rad(spinbox_y_offset.value))

		var chosen_item: SceneBuilderItem = items.pick_random()
		var instance = get_instance_from_path(chosen_item.uid)

		undo_redo.add_do_method(scene_root, "add_child", instance)
		undo_redo.add_do_method(instance, "set_owner", scene_root)
		undo_redo.add_do_method(instance, "set_global_transform", Transform3D(
			basis.rotated(Vector3(1, 0, 0), randf() * deg_to_rad(spinbox_jitter_x.value))
				 .rotated(Vector3(0, 1, 0), randf() * deg_to_rad(spinbox_jitter_y.value))
				 .rotated(Vector3(0, 0, 1), randf() * deg_to_rad(spinbox_jitter_z.value)),
			position
		))

		undo_redo.add_undo_method(scene_root, "remove_child", instance)

	print("[SceneBuilderDock] Commiting action")
	undo_redo.commit_action()

func reroll_preview_instance_transform() -> void:
	if preview_instance == null:
		printerr("[SceneBuilderDock] preview_instance is null inside reroll_preview_instance_transform()")
		return

	random_offset_y = rng.randf_range(items[selected_item_id].random_offset_y_min, items[selected_item_id].random_offset_y_max)

	if items[selected_item_id].use_random_scale:
		var random_scale: float = rng.randf_range(items[selected_item_id].random_scale_min, items[selected_item_id].random_scale_max)
		original_preview_scale = Vector3(random_scale, random_scale, random_scale)
	else:
		original_preview_scale = Vector3(1, 1, 1)

	preview_instance.scale = original_preview_scale

	if items[selected_item_id].use_random_rotation:
		var x_rot: float = rng.randf_range(0, items[selected_item_id].random_rot_x)
		var y_rot: float = rng.randf_range(0, items[selected_item_id].random_rot_y)
		var z_rot: float = rng.randf_range(0, items[selected_item_id].random_rot_z)
		preview_instance.rotation = snap_rot(Vector3(deg_to_rad(x_rot), deg_to_rad(y_rot), deg_to_rad(z_rot)))
		original_preview_basis = preview_instance.basis
	else:
		preview_instance.rotation = Vector3(0, 0, 0)
		original_preview_basis = preview_instance.basis

	original_preview_basis = preview_instance.basis

	pos_offset_x = 0
	pos_offset_y = 0
	pos_offset_z = 0

func select_item(item_id: int) -> void:
	end_placement_mode()
	if len(EditorInterface.get_selection().get_selected_nodes()) == 0:
		EditorInterface.get_selection().add_node(EditorInterface.get_edited_scene_root())
	if not selected_parent():
		return
	selected_parent().set_meta("_edit_lock_", true)
	if item_id < 0 or item_id >= len(items):
		print("Item ", item_id, " doesn't exist, can't select.")
		return
	var nine_path: NinePatchRect = highlighters[item_id]
	nine_path.self_modulate = Color.GREEN
	selected_item_id = item_id
	placement_mode_enabled = true;
	create_preview_instance()

func select_first_item() -> void:
	select_item(0)

func select_next_collection() -> void:
	var new_col = (selected_collection_id + 1) % len(collection_names)
	select_collection(new_col)
	select_first_item()

func select_next_item() -> void:
	var id = (selected_item_id + 1) % len(items)
	select_item(id)

func select_previous_item() -> void:
	var id = (len(items) + selected_item_id - 1) % len(items)
	select_item(id)

func select_previous_collection() -> void:
	end_placement_mode()
	var id = (len(collection_names) + selected_collection_id - 1) % len(collection_names)
	select_collection(id)
	select_first_item()

func start_transform_mode(mode: TransformMode) -> void:
	original_mouse_position = viewport.get_mouse_position()
	current_transform_mode = mode
	
	match mode:
		TransformMode.POSITION_X, TransformMode.POSITION_Y, TransformMode.POSITION_Z:
			original_preview_position = preview_instance.position
		TransformMode.ROTATION_X, TransformMode.ROTATION_Y, TransformMode.ROTATION_Z:
			original_preview_basis = preview_instance.basis
		TransformMode.SCALE:
			original_preview_scale = preview_instance.scale
	
	reset_indicators()
	match mode:
		TransformMode.POSITION_X, TransformMode.ROTATION_X:
			lbl_indicator_x.self_modulate = Color.GREEN
		TransformMode.POSITION_Y, TransformMode.ROTATION_Y:
			lbl_indicator_y.self_modulate = Color.GREEN
		TransformMode.POSITION_Z, TransformMode.ROTATION_Z:
			lbl_indicator_z.self_modulate = Color.GREEN
		TransformMode.SCALE:
			lbl_indicator_scale.self_modulate = Color.GREEN

func get_icon(collection_name: String, item_name: String) -> Texture:
	var icon_path: String = "res://Data/scene-builder/%s/Thumbnail/%s.png" % [collection_name, item_name]
	var tex: Texture = load(icon_path) as Texture
	if tex == null:
		printerr("[SceneBuilderDock] Icon not found: ", icon_path)
		return null
	return tex

func get_instance_from_path(_uid: String) -> Node3D:
	var uid: int = ResourceUID.text_to_id(_uid)

	var path: String = ""
	if ResourceUID.has_id(uid):
		path = ResourceUID.get_id_path(uid)
	else:
		printerr("[SceneBuilderDock] Does not have uid: ", ResourceUID.id_to_text(uid))
		return

	if ResourceLoader.exists(path):
		var loaded = load(path)
		if loaded is PackedScene:
			var instance = loaded.instantiate()
			if instance is Node3D:
				return instance
			else:
				printerr("[SceneBuilderDock] The instantiated scene's root is not a Node3D: ", loaded.name)
		else:
			printerr("[SceneBuilderDock] Loaded resource is not a PackedScene: ", path)
	else:
		printerr("[SceneBuilderDock] Path does not exist: ", path)
	return null

# --

func update_config(_config: SceneBuilderConfig) -> void:
	config = _config


func reset_indicators() -> void:
	lbl_indicator_x.self_modulate = Color.WHITE
	lbl_indicator_y.self_modulate = Color.WHITE
	lbl_indicator_z.self_modulate = Color.WHITE
	lbl_indicator_scale.self_modulate = Color.WHITE
