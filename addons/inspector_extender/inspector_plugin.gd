extends EditorInspectorPlugin

const scene_dir := "res://addons/inspector_extender/attributes/"
const attr_template := "# @@%s("

var attribute_scenes := {
	StringName(attr_template % "message") : load(scene_dir + "inspector_message.tscn"),
	StringName(attr_template % "message_info") : load(scene_dir + "inspector_message.tscn"),
	StringName(attr_template % "message_warning") : load(scene_dir + "inspector_message.tscn"),
	StringName(attr_template % "message_error") : load(scene_dir + "inspector_message.tscn"),
}

var attribute_data := {}
var attribute_nodes := []
var original_edited_object : Object
var edited_object : Object

var plugin : EditorPlugin
var inspector : EditorInspector


func _init(plugin : EditorPlugin):
	self.plugin = plugin
	inspector = plugin.get_editor_interface().get_inspector()
	inspector.property_edited.connect(_on_edited_object_changed)


func _can_handle(object):
	return object.get_script() != null


func _parse_begin(object):
	original_edited_object = object
	if is_instance_valid(edited_object) && edited_object is Node && !edited_object.is_inside_tree():
		edited_object.free()

	if !object.get_script().is_tool():
		object = create_editable_copy(object)

	var source = object.get_script().source_code
	edited_object = object

	var parse_found_prop := ""
	var parse_found_comments := []
	var illegal_starts = ["#".unicode_at(0), " ".unicode_at(0), "\t".unicode_at(0)]
	attribute_data.clear()
	attribute_nodes.clear()

	for x in source.split("\n"):
		if x == "": continue
		if !x.unicode_at(0) in illegal_starts && ("@export " in x || "@export_" in x):
			var prop_name = get_suffix(" var ", x)
			if prop_name == "": continue

			parse_found_prop = prop_name
			attribute_data[prop_name] = parse_found_comments
			parse_found_comments = []

		for k in attribute_scenes:
			if x.begins_with(k):
				parse_found_comments.append([k, get_params(x.substr(x.find("(")))])


func create_editable_copy(object):
	var new_object = object.get_script().new()
	for x in object.get_property_list():
		if x["usage"] == 0:
			continue

		if x["usage"] & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP) != 0:
			continue

		new_object[x["name"]] = object[x["name"]]

	return new_object


func get_suffix(to_find : String, line : String):
	var unclosed_quote := 0
	var unclosed_paren := 0
	var unclosed_brackets := 0
	var unclosed_stache := 0

	var string_chars_matched := 0

	for i in line.length():
		match line.unicode_at(i):
			34, 39: unclosed_quote = 1 - unclosed_quote
			40: unclosed_paren += 1
			41: unclosed_paren -= 1
			91: unclosed_brackets += 1
			93: unclosed_brackets -= 1
			123: unclosed_stache += 1
			125: unclosed_stache -= 1
			var other:
				if unclosed_quote == 0 && unclosed_paren == 0 && unclosed_brackets == 0 && unclosed_stache == 0 && other == to_find.unicode_at(string_chars_matched):
					string_chars_matched += 1
					if string_chars_matched == to_find.length():
						return line.substr(i + 1, line.find(" ", i + to_find.length()) - i - 1)

				else:
					string_chars_matched = 0

	return ""


func get_params(string : String):
	var param_start = 0
	var param_started = false
	var params = []
	for i in string.length():
		match string.unicode_at(i):
			40:  # opening paren
				param_started

			44:  # comma
				if param_started:
					params.append(string.substr(param_start, i - param_start))

				param_started = false

			41:  # closing paren
				params.append(string.substr(param_start, i - param_start))
				return params

			32:  # space
				pass

			_:
				if !param_started:
					param_start = i
					param_started = true

	return params


func _parse_property(object, type, name, hint_type, hint_string, usage_flags, wide):
	if !attribute_data.has(name): return false
	var prop_hidden := false
	for x in attribute_data[name]:
		var new_node = attribute_scenes[x[0]].instantiate()
		var attr_name = x[0].substr(x[0].find("@@") + 2)
		attr_name = attr_name.left(attr_name.find("("))
		var custom_add = new_node._initialize(edited_object, name, attr_name, x[1], attribute_nodes)
		attribute_nodes.append(new_node)
		if new_node.has_method("_hides_property"):
			prop_hidden = prop_hidden || new_node._hides_property()

		if !custom_add:
			add_custom_control(new_node)

	_on_edited_object_changed()
	return prop_hidden


func _on_edited_object_changed(prop = ""):
	if prop != "":
		edited_object.set(prop, original_edited_object[prop])

	for x in attribute_nodes:
		if is_instance_valid(x):
			x._update_view()


func _on_object_tree_exited():
	edited_object.free()