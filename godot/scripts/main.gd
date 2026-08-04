extends Node3D

const PROFILE_PATH := "res://profiles/local.json"
const CLUSTER := Vector2(260.0, 301.0)
const CLUSTER_RADIUS := 85.0
const PROP_RADIUS := 55.0
const CHANTRY_AREA_FILE := "D:/code/opendao-poc/cache/interiors/chantry/lak106d/lak106d.havenarea"
const CHANTRY_AREA_ROOT := "D:/code/opendao-poc/cache/interiors/chantry/lak106d"
const INTERIOR_EXPORT_ROOT := "D:/code/opendao-poc/cache/interiors/all-v2"
const CASTLE_INTERIOR_ROOT := "D:/code/opendao-poc/cache/interiors/lak200d-v6/lak200d"
const PORTAL_TARGETS := {
	"arl100ip_door_general_store": {"level": "lak101d", "area": "arl170ar_general_store"},
	"arl100ip_door_kaitlyn": {"level": "lak102d", "area": "arl140ar_kaitlyn_home"},
	"arl100ip_door_tavern": {"level": "lak103d", "area": "arl150ar_tavern"},
	"arl100ip_door_wilhelm": {"level": "lak104d", "area": "arl160ar_wilhelms_cottage"},
	"arl100ip_door_owen": {"level": "lak105d", "area": "arl120ar_blacksmith"},
	"arl100ip_door_chantry": {"level": "lak106d", "area": "arl110ar_chantry"},
	"arl100ip_door_cottage": {"level": "lak107d", "area": "arl180ar_generic_cottage"},
	"arl100ip_door_dwyn": {"level": "lak108d", "area": "arl130ar_dwyns_home"},
	"arl100ip_door_windmill": {"level": "lak109d", "area": "arl190ar_windmill"},
	"arl100ip_door_castle": {"level": "lak200d", "area": "arl200ar_castle_courtyard"},
}

var prototypes: Dictionary = {}
var loaded_instances := 0
var loaded_actors := 0
var loaded_lights := 0
var loaded_portals := 0
var transitioning := false
var exterior_portal_positions: Dictionary = {}
var current_return_position := Vector3(250.0, 3.0, -307.0)
var current_interior_level := ""
var current_interior_area := ""
var water_tour_points: Array[Dictionary] = []
var tour_cover: Control

func _ready() -> void:
	_configure_runtime_profile()
	print("OPENDAO_BOOT stage=ready")
	await _load_dao_area()
	var requested_start := OS.get_environment("DAOPEN_START_AREA")
	if not requested_start.is_empty() and requested_start != "lak100d":
		var requested_area := ""
		for target_value in PORTAL_TARGETS.values():
			var target: Dictionary = target_value
			if str(target.get("level", "")) == requested_start:
				requested_area = str(target.get("area", ""))
				break
		await _transition_to_interior(requested_start, requested_area)
		if OS.get_environment("DAOPEN_TEST_ROUNDTRIP") == "1":
			await _run_roundtrip_test()
	else:
		# Frame the authored village square and its closest active militia after all
		# imported roots have their final transforms.
		await _frame_camera()
		if not OS.get_environment("DAOPEN_TEST_DOOR_LEVEL").is_empty():
			await _run_door_roundtrip_test(OS.get_environment("DAOPEN_TEST_DOOR_LEVEL"))
		if OS.get_environment("DAOPEN_TEST_PLATFORM") == "1":
			await _run_platform_test()
	print("OPENDAO_READY area=Redcliffe actors=%d instances=%d" % [loaded_actors, loaded_instances])
	if not OS.get_environment("DAOPEN_TOUR").is_empty():
		await _run_shareable_tour(OS.get_environment("DAOPEN_TOUR"))
	else:
		await _capture_if_requested()

func _configure_runtime_profile() -> void:
	var mobile := OS.has_feature("mobile") or OS.get_environment("DAOPEN_MOBILE") == "1"
	if not mobile:
		return
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_create_mobile_controls()
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.directional_shadow_max_distance = 110.0
	print("OPENDAO_MOBILE_PROFILE enabled=true resolution=1280x720 renderer=%s touch=true" % RenderingServer.get_current_rendering_method())

func _create_mobile_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MobileControls"
	add_child(layer)
	var controls := Control.new()
	controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(controls)
	_add_touch_button(controls, "move_left", "◀", Vector2(24, -142), Vector2(92, -74), false)
	_add_touch_button(controls, "move_right", "▶", Vector2(168, -142), Vector2(236, -74), false)
	_add_touch_button(controls, "move_forward", "▲", Vector2(96, -214), Vector2(164, -146), false)
	_add_touch_button(controls, "move_back", "▼", Vector2(96, -70), Vector2(164, -2), false)
	_add_touch_button(controls, "jump", "JUMP / SWIM", Vector2(-190, -118), Vector2(-24, -38), true)

func _add_touch_button(parent: Control, action: String, label: String, top_left: Vector2, bottom_right: Vector2, right_anchor: bool) -> void:
	var button := Button.new()
	button.text = label
	button.modulate = Color(1, 1, 1, 0.72)
	button.add_theme_font_size_override("font_size", 20)
	if right_anchor:
		button.anchor_left = 1.0
		button.anchor_right = 1.0
	button.anchor_top = 1.0
	button.anchor_bottom = 1.0
	button.offset_left = top_left.x
	button.offset_top = top_left.y
	button.offset_right = bottom_right.x
	button.offset_bottom = bottom_right.y
	button.button_down.connect(func(): Input.action_press(action))
	button.button_up.connect(func(): Input.action_release(action))
	parent.add_child(button)

func _frame_camera() -> void:
	var camera_position := Vector3(250.0, 4.1, -307.0)
	var target := Vector3(256.0, 2.5, -300.5)
	var position_override := OS.get_environment("DAOPEN_CAMERA")
	var target_override := OS.get_environment("DAOPEN_TARGET")
	if not position_override.is_empty():
		camera_position = _csv_vec3(position_override, camera_position)
	if not target_override.is_empty():
		target = _csv_vec3(target_override, target)
	await get_tree().physics_frame
	if OS.get_environment("DAOPEN_CAMERA_NO_GROUND") == "1":
		$Player.global_position = camera_position - Vector3(0, 0.65, 0)
		$Player.look_at_target(target)
		print("OPENDAO_CAMERA diagnostic_no_ground position=%s target=%s" % [str(camera_position), str(target)])
		return
	var ray_origin := Vector3(camera_position.x, camera_position.y + 250.0, camera_position.z)
	var ray_end := Vector3(camera_position.x, camera_position.y - 1000.0, camera_position.z)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = [$Player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		$Player.global_position = hit.position + Vector3(0, 0.95, 0)
		camera_position.y = hit.position.y + 1.60
		print("OPENDAO_GROUNDED source=terrain position=%s normal=%s" % [str(hit.position), str(hit.normal)])
	else:
		$Player.global_position = camera_position - Vector3(0, 0.65, 0)
		push_warning("OpenDAO: authored-ground raycast missed; using profile fallback")
	$Player.look_at_target(target)

func _csv_vec3(value: String, fallback: Vector3) -> Vector3:
	var parts := value.split(",")
	if parts.size() != 3:
		return fallback
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))

func _load_dao_area() -> void:
	var profile := _read_json(ProjectSettings.globalize_path(PROFILE_PATH))
	if profile.is_empty():
		push_error("OpenDAO: invalid profile " + PROFILE_PATH)
		return
	var composed_scene := str(profile.get("scene_file", ""))
	if not composed_scene.is_empty() and ResourceLoader.exists(composed_scene):
		print("OPENDAO_BOOT stage=load_composed path=" + composed_scene)
		await _load_composed_scene(composed_scene, str(profile.get("terrain_materials", "")))
		var composed_area: Dictionary = _read_json(str(profile.area_file))
		_apply_authored_environment(composed_area.get("environment", {}), str(profile.get("sky_cloud", "")))
		_load_authored_lights(composed_area.get("lights", []))
		_load_authored_portals(composed_area.get("placeables", []))
		if not composed_area.is_empty():
			var area_root := str(profile.area_root)
			print("OPENDAO_BOOT stage=connected_terrain")
			await _load_instance_table(area_root, composed_area.get("terrain", {}).get("patches", {}), 0.0, true, 85.0)
			print("OPENDAO_BOOT stage=connected_setpieces")
			var prop_table: Dictionary = composed_area.get("props", {})
			var environment_props := _definition_table_without_prefix(prop_table, "plc_")
			await _load_instance_table(area_root, _definition_table_without_water(environment_props), 190.0, true, 85.0, 2)
			print("OPENDAO_BOOT stage=authored_water")
			await _load_authored_water(area_root, environment_props)
			print("OPENDAO_BOOT stage=interactive_placeables")
			await _load_instance_table(area_root, _definition_table_with_prefix(prop_table, "plc_"), 0.0, true, 0.0, 2)
			print("OPENDAO_BOOT stage=vegetation")
			await _load_instance_table(area_root, composed_area.get("trees", {}), 220.0, false)
			_apply_dao_terrain_materials($DAOScene, str(profile.get("terrain_materials", "")))
		var actor_area := _read_json(str(profile.get("actor_file", "")))
		if not actor_area.is_empty():
			for actor in actor_area.get("actors", []):
				if bool(actor.get("active", false)) and not str(actor.get("model", "")).is_empty():
					await _spawn_actor(str(profile.get("actor_root", "")), actor)
		$Status.text = "AEDAN  •  HUMAN WARRIOR  •  LEVEL 1\nRedcliffe Village  •  %d actors active\nWASD move • mouse look • Shift sprint • Esc release" % loaded_actors
		return
	var area: Dictionary = _read_json(str(profile.area_file))
	if area.is_empty():
		push_error("OpenDAO: invalid Haven area " + str(profile.area_file))
		return
	var root := str(profile.area_root)
	$Status.text = "AEDAN  •  HUMAN WARRIOR  •  LEVEL 1\nStreaming Redcliffe Village…"

	# Terrain and authored setpieces are loaded as individual glTF scenes. This
	# avoids monolithic OBJ surface limits and preserves original DAO materials.
	var terrain: Dictionary = area.get("terrain", {}).get("patches", {})
	await _load_instance_table(root, terrain, CLUSTER_RADIUS, true)
	await _load_instance_table(root, area.get("props", {}), PROP_RADIUS, false)

	for actor in area.get("actors", []):
		if not bool(actor.get("active", false)):
			continue
		await _spawn_actor(root, actor)
	_apply_authored_environment(area.get("environment", {}))
	_load_authored_lights(area.get("lights", []))

	$Status.text = "AEDAN  •  HUMAN WARRIOR  •  LEVEL 1\nRedcliffe Village  •  %d actors active\nWASD move • mouse look • Shift sprint • Esc release" % loaded_actors

func _apply_authored_environment(environment: Dictionary, cloud_path: String = "") -> void:
	if environment.is_empty():
		print("OPENDAO_AUTHORED_ENVIRONMENT missing")
		return
	var source_direction := _array_vec3(environment.get("sun_direction", [0.3, 0.5, 1.0])).normalized()
	var godot_to_sun := Vector3(source_direction.x, source_direction.z, -source_direction.y).normalized()
	var source_color := _array_vec3(environment.get("sun_color", [1.0, 1.0, 1.0]))
	var peak: float = maxf(source_color.x, maxf(source_color.y, source_color.z))
	if peak <= 0.0001:
		peak = 1.0
	$Sun.light_color = Color(source_color.x / peak, source_color.y / peak, source_color.z / peak)
	$Sun.light_energy = clampf(peak * 1.55, 0.2, 5.0)
	var sun_up := Vector3.FORWARD if absf(godot_to_sun.dot(Vector3.UP)) > 0.98 else Vector3.UP
	$Sun.look_at($Sun.global_position - godot_to_sun, sun_up)
	$Fill.light_energy = 0.0
	var world_environment := $Environment as WorldEnvironment
	if world_environment.environment != null:
		var fog_color := _array_vec3(environment.get("fog_color", [0.16, 0.19, 0.16]))
		world_environment.environment.ambient_light_color = Color(fog_color.x, fog_color.y, fog_color.z)
		world_environment.environment.ambient_light_energy = 0.65
		var rendering_method := RenderingServer.get_current_rendering_method()
		var sky := Sky.new()
		if rendering_method == "forward_plus":
			var panorama_texture := load("res://assets/sky/redcliffe-cloud-panorama-v3.png") as Texture2D
			if panorama_texture != null:
				var panorama_material := PanoramaSkyMaterial.new()
				panorama_material.panorama = panorama_texture
				panorama_material.energy_multiplier = 0.72
				sky.sky_material = panorama_material
				world_environment.environment.sky_rotation = Vector3(0.0, deg_to_rad(130.0), 0.0)
		else:
			var sky_shader := load("res://shaders/dao_sky.gdshader") as Shader
			if sky_shader != null:
				var sky_material := ShaderMaterial.new()
				sky_material.shader = sky_shader
				sky_material.set_shader_parameter("sun_direction", godot_to_sun)
				sky_material.set_shader_parameter("sun_color", source_color / peak)
				var authored_horizon := Color(fog_color.x, fog_color.y, fog_color.z).lerp(Color(0.34, 0.44, 0.56), 0.68)
				sky_material.set_shader_parameter("horizon_color", authored_horizon)
		if sky.sky_material != null:
			world_environment.environment.sky = sky
			world_environment.environment.background_mode = Environment.BG_SKY
			print("OPENDAO_AUTHORED_SKY mode=%s source_cloud=%s" % [rendering_method, cloud_path])
			if rendering_method == "forward_plus":
				_create_volumetric_clouds(world_environment.environment)
	print("OPENDAO_AUTHORED_ENVIRONMENT sun=%s color=%s sky=%s probe=%s" % [
		str(source_direction), str(source_color), str(environment.get("skydome", "")),
		str(environment.get("probe_loaded", false))])

func _create_volumetric_clouds(environment: Environment) -> void:
	if environment == null or get_node_or_null("DAOCloudVolumes") != null:
		return
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.0
	environment.volumetric_fog_length = 320.0
	environment.volumetric_fog_detail_spread = 1.55
	environment.volumetric_fog_ambient_inject = 0.42
	environment.volumetric_fog_anisotropy = 0.68
	environment.volumetric_fog_sky_affect = 0.82
	environment.volumetric_fog_temporal_reprojection_enabled = true
	environment.volumetric_fog_temporal_reprojection_amount = 0.88
	var cloud_shader := load("res://shaders/dao_cloud_volume.gdshader") as Shader
	if cloud_shader == null:
		push_warning("OpenDAO: volumetric cloud shader unavailable")
		return
	var cloud_material := ShaderMaterial.new()
	cloud_material.shader = cloud_shader
	var cloud_root := Node3D.new()
	cloud_root.name = "DAOCloudVolumes"
	add_child(cloud_root)
	var banks := [
		[Vector3(260.0, 54.0, -382.0), Vector3(118.0, 34.0, 74.0)],
		[Vector3(340.0, 106.0, -405.0), Vector3(190.0, 48.0, 112.0)],
		[Vector3(270.0, 139.0, -525.0), Vector3(250.0, 64.0, 138.0)],
		[Vector3(430.0, 118.0, -305.0), Vector3(168.0, 46.0, 106.0)],
		[Vector3(125.0, 133.0, -265.0), Vector3(184.0, 52.0, 116.0)],
		[Vector3(365.0, 164.0, -180.0), Vector3(230.0, 58.0, 128.0)]
	]
	for index in banks.size():
		var bank: Array = banks[index]
		var cloud_volume := FogVolume.new()
		cloud_volume.name = "CloudBank_%02d" % index
		cloud_volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		cloud_volume.position = bank[0]
		cloud_volume.size = bank[1]
		cloud_volume.material = cloud_material
		cloud_root.add_child(cloud_volume)
	print("OPENDAO_VOLUMETRIC_CLOUDS renderer=forward_plus banks=%d" % banks.size())

func _load_authored_lights(records: Array) -> void:
	for record_value in records:
		var record: Dictionary = record_value
		var source_position := _array_vec3(record.get("position", [0, 0, 0]))
		var light := OmniLight3D.new()
		light.name = str(record.get("name", "DAO_Light"))
		light.position = Vector3(source_position.x, source_position.z, -source_position.y)
		var rgba := _array_vec4(record.get("color", [1, 1, 1, 1]), Vector4.ONE)
		var peak: float = maxf(rgba.x, maxf(rgba.y, rgba.z))
		if peak <= 0.0001:
			light.free()
			continue
		light.light_color = Color(rgba.x / peak, rgba.y / peak, rgba.z / peak)
		light.light_energy = clampf(peak * maxf(rgba.w, 1.0), 0.05, 12.0)
		light.omni_range = maxf(float(record.get("radius", 5.0)), 0.25)
		light.omni_attenuation = 1.0
		# Static DAO lights were baked and should not cast a second realtime shadow.
		light.shadow_enabled = not bool(record.get("static", true)) and bool(record.get("occluded", true))
		$DAOScene.add_child(light)
		loaded_lights += 1
	print("OPENDAO_AUTHORED_LIGHTS loaded=%d exported=%d" % [loaded_lights, records.size()])

func _load_authored_portals(records: Array) -> void:
	for record_value in records:
		var record: Dictionary = record_value
		var tag := str(record.get("tag", record.get("template", ""))).to_lower()
		if not bool(record.get("active", false)) or not PORTAL_TARGETS.has(tag):
			continue
		var source_position := _array_vec3(record.get("position", [0, 0, 0]))
		var target: Dictionary = PORTAL_TARGETS[tag]
		var destination_level := str(target.get("level", ""))
		var destination_area := str(target.get("area", ""))
		var portal := Area3D.new()
		portal.name = "Portal_" + tag
		portal.position = Vector3(source_position.x, source_position.z + 1.1, -source_position.y)
		portal.collision_layer = 0
		portal.collision_mask = 1
		portal.set_meta("dao_tag", tag)
		portal.set_meta("dao_destination_level", destination_level)
		portal.set_meta("dao_destination_area", destination_area)
		exterior_portal_positions[tag] = portal.position
		var collision := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 1.35
		collision.shape = shape
		portal.add_child(collision)
		portal.body_entered.connect(_on_portal_entered.bind(tag, destination_level, destination_area))
		$DAOScene.add_child(portal)
		loaded_portals += 1
	print("OPENDAO_AUTHORED_PORTALS loaded=%d exported_placeables=%d" % [loaded_portals, records.size()])

func _on_portal_entered(body: Node3D, tag: String, destination_level: String, destination_area: String) -> void:
	if body != $Player:
		return
	print("OPENDAO_TRANSITION_REQUEST tag=%s level=%s area=%s" % [tag, destination_level, destination_area])
	var interior_file := _interior_root(destination_level).path_join(destination_level + ".havenarea")
	if FileAccess.file_exists(interior_file) and not transitioning:
		transitioning = true
		var door_position: Vector3 = exterior_portal_positions.get(tag, body.global_position)
		var outward := body.global_position - door_position
		outward.y = 0.0
		if outward.length_squared() < 0.01:
			outward = Vector3.FORWARD
		current_return_position = body.global_position + outward.normalized() * 0.75
		current_return_position.y = body.global_position.y
		$Player.set_physics_process(false)
		_transition_to_interior.call_deferred(destination_level, destination_area)
		return
	$Status.text = "AREA TRANSITION  •  %s → %s\nGameplay area: %s • streaming handoff pending" % [tag, destination_level, destination_area]

func _on_chantry_exit_entered(body: Node3D) -> void:
	if body != $Player or transitioning:
		return
	transitioning = true
	$Player.set_physics_process(false)
	_transition_to_village.call_deferred()

func _clear_streamed_area() -> void:
	for child in $DAOScene.get_children():
		child.queue_free()
	await get_tree().process_frame
	prototypes.clear()
	loaded_instances = 0
	loaded_actors = 0
	loaded_lights = 0
	loaded_portals = 0

func _create_chantry_exit() -> void:
	# arl110wp_from_village is just inside the southern entrance. Keep the
	# trigger behind the spawn point so arriving cannot immediately exit again.
	var portal := Area3D.new()
	portal.name = "Portal_arl110wp_to_village"
	portal.position = Vector3(0.16, 1.1, 29.15)
	portal.collision_layer = 0
	portal.collision_mask = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.8, 2.2, 0.8)
	collision.shape = shape
	portal.add_child(collision)
	portal.body_entered.connect(_on_chantry_exit_entered)
	$DAOScene.add_child(portal)
	loaded_portals += 1

func _transition_to_village() -> void:
	$Status.text = "AREA TRANSITION: %s to Village\nStreaming lak100d..." % current_interior_area
	await _clear_streamed_area()
	await _load_dao_area()
	await get_tree().physics_frame
	# Return to the side of the exact exterior door from which the player entered.
	var outside := current_return_position
	var query := PhysicsRayQueryParameters3D.create(outside + Vector3.UP * 0.2, outside - Vector3.UP * 8.0)
	query.exclude = [$Player.get_rid()]
	query.collision_mask = 3
	query.hit_back_faces = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		outside.y = hit.position.y + 0.95
	$Player.global_position = outside
	$Player.vertical_velocity = 0.0
	$Player.grounded = true
	var return_tag := _portal_tag_for_level(current_interior_level)
	var door_position: Vector3 = exterior_portal_positions.get(return_tag, outside + Vector3.FORWARD)
	$Player.look_at_target(door_position + Vector3.UP * 0.5)
	$Status.text = "AEDAN - HUMAN WARRIOR - LEVEL 1\nRedcliffe Village - %d actors active\nWASD move - Space jump - mouse look" % loaded_actors
	print("OPENDAO_TRANSITION_COMPLETE level=lak100d area=arl100ar_redcliffe from=%s actors=%d" % [current_interior_level, loaded_actors])
	current_interior_level = ""
	current_interior_area = ""
	$Player.set_physics_process(true)
	transitioning = false

func _transition_to_chantry() -> void:
	transitioning = true
	$Player.set_physics_process(false)
	$Status.text = "AREA TRANSITION  •  Village → Chantry\nStreaming lak106d…"
	await _clear_streamed_area()
	var interior := _read_json(CHANTRY_AREA_FILE)
	if interior.is_empty():
		push_error("OpenDAO: missing Chantry interior export")
		$Player.set_physics_process(true)
		transitioning = false
		return
	_apply_authored_environment(interior.get("environment", {}))
	_load_authored_lights(interior.get("lights", []))
	print("OPENDAO_BOOT stage=interior_setpieces area=lak106d")
	await _load_instance_table(CHANTRY_AREA_ROOT, interior.get("props", {}), 0.0, true, 0.0, 3)
	_create_chantry_exit()
	# Original arl110wp_from_village waypoint, converted from DAO Z-up to Godot Y-up.
	$Player.global_position = Vector3(0.161174, 0.972839, 26.977123)
	$Player.vertical_velocity = 0.0
	$Player.grounded = true
	$Player.look_at_target(Vector3(0.0, 1.6, 19.0))
	$Status.text = "AEDAN  •  HUMAN WARRIOR  •  LEVEL 1\nVillage Chantry  •  lak106d / arl110ar_chantry\nWASD move • Space jump • mouse look"
	print("OPENDAO_TRANSITION_COMPLETE level=lak106d area=arl110ar_chantry waypoint=arl110wp_from_village instances=%d lights=%d" % [loaded_instances, loaded_lights])
	$Player.set_physics_process(true)
	transitioning = false

func _transition_to_interior(destination_level: String, destination_area: String) -> void:
	transitioning = true
	$Player.set_physics_process(false)
	current_interior_level = destination_level
	current_interior_area = destination_area
	$Status.text = "AREA TRANSITION: Village to %s\nStreaming %s..." % [destination_area, destination_level]
	await _clear_streamed_area()
	var interior_root := _interior_root(destination_level)
	var interior_file := interior_root.path_join(destination_level + ".havenarea")
	var interior := _read_json(interior_file)
	if interior.is_empty():
		push_error("OpenDAO: missing interior export " + interior_file)
		$Player.set_physics_process(true)
		transitioning = false
		return
	_apply_authored_environment(interior.get("environment", {}))
	_load_authored_lights(interior.get("lights", []))
	print("OPENDAO_BOOT stage=interior_setpieces area=" + destination_level)
	await _load_instance_table(interior_root, interior.get("props", {}), 0.0, true, 0.0, 3)
	var interior_actor_root := INTERIOR_EXPORT_ROOT.path_join(destination_level).path_join("lak100d")
	if destination_level == "lak200d":
		interior_actor_root = CASTLE_INTERIOR_ROOT.get_base_dir().path_join("lak100d")
	for actor_value in interior.get("actors", []):
		var actor: Dictionary = actor_value
		if bool(actor.get("active", false)) and not str(actor.get("model", "")).is_empty():
			await _spawn_actor(interior_actor_root, actor)
	var waypoint := _from_village_waypoint(interior.get("waypoints", []))
	if waypoint.is_empty():
		push_error("OpenDAO: interior has no from-village waypoint " + destination_level)
		$Player.set_physics_process(true)
		transitioning = false
		return
	var source_position := _array_vec3(waypoint.get("position", [0, 0, 0]))
	var spawn_position := Vector3(source_position.x, source_position.z + 0.95, -source_position.y)
	var inward := -_dao_basis(waypoint.get("rotation", [0, 0, 0, 1])).z
	inward.y = 0.0
	if inward.length_squared() < 0.01:
		inward = Vector3.FORWARD
	inward = inward.normalized()
	_create_interior_exit(spawn_position, inward)
	$Player.global_position = spawn_position
	$Player.vertical_velocity = 0.0
	$Player.grounded = true
	$Player.look_at_target(spawn_position + inward * 6.0 + Vector3.UP * 0.5)
	$Status.text = "AEDAN - HUMAN WARRIOR - LEVEL 1\n%s - %s\nWASD move - Space jump - mouse look" % [destination_area, destination_level]
	print("OPENDAO_TRANSITION_COMPLETE level=%s area=%s waypoint=%s instances=%d actors=%d lights=%d" % [destination_level, destination_area, str(waypoint.get("tag", "")), loaded_instances, loaded_actors, loaded_lights])
	$Player.set_physics_process(true)
	transitioning = false

func _create_interior_exit(spawn_position: Vector3, inward: Vector3) -> void:
	var portal := Area3D.new()
	portal.name = "Portal_interior_exit"
	portal.position = spawn_position - inward * 2.15
	portal.collision_layer = 0
	portal.collision_mask = 1
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.15
	collision.shape = shape
	portal.add_child(collision)
	portal.body_entered.connect(_on_chantry_exit_entered)
	$DAOScene.add_child(portal)
	loaded_portals += 1

func _from_village_waypoint(records: Array) -> Dictionary:
	for value in records:
		var record: Dictionary = value
		if str(record.get("tag", "")).to_lower().contains("from_village"):
			return record
	return {}

func _dao_basis(rotation_value: Array) -> Basis:
	if rotation_value.size() < 4:
		return Basis.IDENTITY
	var source_q := Quaternion(float(rotation_value[0]), float(rotation_value[1]), float(rotation_value[2]), float(rotation_value[3]))
	var convert := Basis(Vector3.RIGHT, Vector3(0, 0, -1), Vector3(0, 1, 0))
	return convert * Basis(source_q) * convert.inverse()

func _portal_tag_for_level(level: String) -> String:
	for tag in PORTAL_TARGETS.keys():
		if str(PORTAL_TARGETS[tag].get("level", "")) == level:
			return str(tag)
	return ""

func _interior_root(level: String) -> String:
	if level == "lak200d":
		return CASTLE_INTERIOR_ROOT
	return INTERIOR_EXPORT_ROOT.path_join(level).path_join(level)

func _run_roundtrip_test() -> void:
	for frame in range(30):
		await get_tree().physics_frame
	print("OPENDAO_STABILITY_CHECK area=lak106d position=%s grounded=%s vertical_velocity=%.3f" % [
		str($Player.global_position), str($Player.grounded), $Player.vertical_velocity])
	$Player.global_position = Vector3(0.16, 0.97, 29.15)
	for frame in range(600):
		await get_tree().physics_frame
		if not transitioning and loaded_actors > 0:
			break
	print("OPENDAO_ROUNDTRIP_CHECK area=lak100d position=%s grounded=%s actors=%d" % [
		str($Player.global_position), str($Player.grounded), loaded_actors])

func _run_door_roundtrip_test(level: String) -> void:
	var tag := _portal_tag_for_level(level)
	var portal := $DAOScene.get_node_or_null("Portal_" + tag) as Area3D
	if portal == null:
		push_error("OPENDAO_DOOR_TEST missing exterior portal " + tag)
		return
	var approach: Vector3 = $Player.global_position - portal.global_position
	approach.y = 0.0
	if approach.length_squared() < 0.01:
		approach = Vector3.FORWARD
	$Player.global_position = portal.global_position + approach.normalized()
	for frame in range(900):
		await get_tree().physics_frame
		if current_interior_level == level and not transitioning:
			break
	for frame in range(30):
		await get_tree().physics_frame
	print("OPENDAO_DOOR_ENTER_CHECK level=%s position=%s grounded=%s actors=%d" % [
		level, str($Player.global_position), str($Player.grounded), loaded_actors])
	var exit := $DAOScene.get_node_or_null("Portal_interior_exit") as Area3D
	if exit == null:
		push_error("OPENDAO_DOOR_TEST missing interior exit " + level)
		return
	$Player.global_position = exit.global_position
	for frame in range(900):
		await get_tree().physics_frame
		if current_interior_level.is_empty() and not transitioning and loaded_actors > 0:
			break
	for frame in range(30):
		await get_tree().physics_frame
	print("OPENDAO_DOOR_RETURN_CHECK level=%s position=%s grounded=%s actors=%d" % [
		level, str($Player.global_position), str($Player.grounded), loaded_actors])

func _run_platform_test() -> void:
	# Authored FHE_WalkL02 elevated walkway instance. Its surface is structural
	# layer 2, not terrain layer 1, and reproduces the porch/platform failure.
	var best_hit: Dictionary = {}
	var space := get_world_3d().direct_space_state
	for x_offset in range(-8, 9, 2):
		for z_offset in range(-8, 9, 2):
			var xz := Vector3(282.746246 + x_offset, 0.0, -224.550827 + z_offset)
			var query := PhysicsRayQueryParameters3D.create(xz + Vector3.UP * 6.0, xz - Vector3.UP * 12.0)
			query.collision_mask = 2
			query.hit_back_faces = true
			var hit := space.intersect_ray(query)
			if hit.is_empty() or absf(hit.normal.y) < 0.55:
				continue
			if best_hit.is_empty() or hit.position.y > best_hit.position.y:
				best_hit = hit
	if best_hit.is_empty():
		push_error("OPENDAO_PLATFORM_CHECK no structural walkable face found")
		return
	$Player.global_position = best_hit.position + Vector3.UP * 0.95
	$Player.vertical_velocity = 0.0
	$Player.look_at_target(best_hit.position + Vector3(4.0, 1.0, 4.0))
	for frame in range(90):
		await get_tree().physics_frame
	print("OPENDAO_PLATFORM_CHECK source=%s position=%s grounded=%s vertical_velocity=%.3f" % [
		str(best_hit.collider.name), str($Player.global_position), str($Player.grounded), $Player.vertical_velocity])

func _load_composed_scene(path: String, terrain_materials_path: String) -> void:
	print("OPENDAO_BOOT stage=parse_glb")
	$Status.text = "AEDAN  •  HUMAN WARRIOR  •  LEVEL 1\nStreaming authored Redcliffe scene…"
	var packed := _load_glb(path)
	if packed == null:
		return
	print("OPENDAO_BOOT stage=instantiate_glb")
	var scene := packed.instantiate() as Node3D
	$DAOScene.add_child(scene)
	print("OPENDAO_BOOT stage=terrain_materials")
	_apply_dao_terrain_materials(scene, terrain_materials_path)
	loaded_actors = 0
	loaded_instances = scene.find_children("*", "MeshInstance3D", true, false).size()
	for candidate in scene.find_children("*", "AnimationPlayer", true, false):
		var player := candidate as AnimationPlayer
		for animation_name in player.get_animation_list():
			if animation_name != "RESET":
				var animation := player.get_animation(animation_name)
				animation.loop_mode = Animation.LOOP_LINEAR
				player.play(animation_name)
	# Terrain meshes are the walkable authored surface. Actor skinned meshes and
	# small set dressing intentionally do not become collision bodies.
	for candidate in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance.skin == null and mesh_instance.mesh != null:
			var layers := 1 if mesh_instance.name.to_lower().begins_with("lak100d_") else 2
			_create_mesh_collision(mesh_instance, layers)
	await get_tree().process_frame

func _apply_dao_terrain_materials(scene: Node3D, manifest_path: String) -> void:
	if manifest_path.is_empty() or not FileAccess.file_exists(manifest_path):
		print("OPENDAO_TERRAIN_MATERIALS missing=" + manifest_path)
		return
	var descriptors := _read_json(manifest_path)
	var shader := load("res://shaders/dao_terrain.gdshader") as Shader
	var applied := 0
	for candidate in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
			if source == null:
				continue
			var material_key := _terrain_material_key(source.resource_name, descriptors)
			if material_key.is_empty():
				continue
			var descriptor: Dictionary = descriptors[material_key]
			var mask_a := _load_external_texture(str(descriptor.get("maskA", "")))
			var mask_a2 := _load_external_texture(str(descriptor.get("maskA2", "")))
			if source.albedo_texture == null or source.normal_texture == null or mask_a == null or mask_a2 == null:
				push_warning("OpenDAO: incomplete terrain material " + material_key)
				continue
			var material := ShaderMaterial.new()
			material.shader = shader
			material.set_shader_parameter("palette", source.albedo_texture)
			material.set_shader_parameter("palette_normal", source.normal_texture)
			material.set_shader_parameter("mask_a", mask_a)
			material.set_shader_parameter("mask_a2", mask_a2)
			material.set_shader_parameter("pal_dim", _array_vec4(descriptor.get("palDim", []), Vector4(0.5, 0.25, 2.0, 4.0)))
			material.set_shader_parameter("pal_param", _array_vec4(descriptor.get("palParam", []), Vector4(0.0625, 0.03125, 0.375, 0.1875)))
			var uv_scales: Array = descriptor.get("uvScales", [])
			material.set_shader_parameter("uv_scales0", _array_vec4(uv_scales.slice(0, 4), Vector4(24.0, 24.0, 24.0, 24.0)))
			material.set_shader_parameter("uv_scales1", _array_vec4(uv_scales.slice(4, 8), Vector4(24.0, 24.0, 24.0, 24.0)))
			mesh_instance.set_surface_override_material(surface, material)
			applied += 1
			print("OPENDAO_TERRAIN_MATERIAL mesh=%s surface=%d material=%s" % [mesh_instance.name, surface, material_key])
	print("OPENDAO_TERRAIN_MATERIALS applied=%d" % applied)

func _terrain_material_key(resource_name: String, descriptors: Dictionary) -> String:
	var normalized := resource_name.to_lower()
	for key in descriptors.keys():
		if normalized.contains(str(key).to_lower()):
			return str(key)
	return ""

func _load_external_texture(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

func _load_instance_table(root: String, table: Dictionary, prune_radius: float, create_collision: bool, inner_radius: float = 0.0, collision_layers: int = 1) -> void:
	var model_index := 0
	for definition in table.values():
		var relative := str(definition.get("file", ""))
		if relative.is_empty():
			continue
		var packed: PackedScene
		var seen_transforms: Dictionary = {}
		for instance in definition.get("instances", []):
			var source_position := _array_vec3(instance.get("position", [0, 0, 0]))
			var distance := Vector2(source_position.x, source_position.y).distance_to(CLUSTER)
			if prune_radius > 0.0 and distance > prune_radius:
				continue
			if inner_radius > 0.0 and distance <= inner_radius:
				continue
			var rotation_value: Array = instance.get("rotation", [0, 0, 0, 1])
			var transform_key := "%0.4f,%0.4f,%0.4f|%s" % [source_position.x, source_position.y, source_position.z, str(rotation_value)]
			if seen_transforms.has(transform_key):
				continue
			seen_transforms[transform_key] = true
			if packed == null:
				packed = _load_glb(root.path_join(relative))
				if packed == null:
					break
			var node := packed.instantiate() as Node3D
			_apply_dao_transform(node, instance)
			$DAOScene.add_child(node)
			if create_collision:
				_create_trimesh_collision(node, collision_layers)
			loaded_instances += 1
		model_index += 1
		if model_index % 8 == 0:
			await get_tree().process_frame

func _definition_table_with_prefix(table: Dictionary, prefix: String) -> Dictionary:
	var result: Dictionary = {}
	for key in table.keys():
		if str(key).to_lower().begins_with(prefix):
			result[key] = table[key]
	return result

func _definition_table_without_prefix(table: Dictionary, prefix: String) -> Dictionary:
	var result: Dictionary = {}
	for key in table.keys():
		if not str(key).to_lower().begins_with(prefix):
			result[key] = table[key]
	return result

func _definition_table_without_water(table: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in table.keys():
		var lower := str(key).to_lower()
		if lower.contains("water") or lower.begins_with("hro_"):
			continue
		result[key] = table[key]
	return result

func _load_authored_water(root: String, table: Dictionary) -> void:
	var shader := load("res://shaders/dao_water.gdshader") as Shader
	var water_instances := 0
	for key in table.keys():
		var lower := str(key).to_lower()
		if not (lower == "lak100d_water_12" or lower.begins_with("hro_lak100dwater")):
			continue
		var definition: Dictionary = table[key]
		var relative := str(definition.get("file", ""))
		var packed := _load_glb(root.path_join(relative))
		if packed == null:
			continue
		var seen: Dictionary = {}
		for instance_value in definition.get("instances", []):
			var instance: Dictionary = instance_value
			var transform_key := str(instance.get("position", [])) + str(instance.get("rotation", []))
			if seen.has(transform_key):
				continue
			seen[transform_key] = true
			var node := packed.instantiate() as Node3D
			_apply_dao_transform(node, instance)
			$DAOScene.add_child(node)
			_apply_water_shader(node, shader)
			await get_tree().process_frame
			_create_water_volume(node)
			if lower == "lak100d_water_12":
				_replace_flat_lake_surface(node, shader)
			water_instances += 1
			loaded_instances += 1
	print("OPENDAO_AUTHORED_WATER loaded=%d" % water_instances)

func _replace_flat_lake_surface(source: Node3D, shader: Shader) -> void:
	var bounds := AABB()
	var has_bounds := false
	for child in source.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var world_bounds: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
		bounds = bounds.merge(world_bounds) if has_bounds else world_bounds
		has_bounds = true
	if not has_bounds:
		return
	source.visible = false
	var clean_surface := MeshInstance3D.new()
	clean_surface.name = "CleanDynamicLakeSurface"
	var plane := PlaneMesh.new()
	plane.size = Vector2(bounds.size.x, bounds.size.z)
	var subdivisions := 48 if OS.has_feature("mobile") or OS.get_environment("DAOPEN_MOBILE") == "1" else 128
	plane.subdivide_width = subdivisions
	plane.subdivide_depth = subdivisions
	clean_surface.mesh = plane
	clean_surface.position = Vector3(bounds.get_center().x, bounds.position.y + bounds.size.y + 0.01, bounds.get_center().z)
	var material := ShaderMaterial.new()
	material.shader = shader
	clean_surface.material_override = material
	$DAOScene.add_child(clean_surface)
	print("OPENDAO_WATER_CLEAN_SURFACE size=%s position=%s source_hidden=true" % [str(plane.size), str(clean_surface.position)])

func _create_water_volume(water_root: Node3D) -> void:
	var bounds := AABB()
	var has_bounds := false
	for child in water_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var world_bounds: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
		bounds = bounds.merge(world_bounds) if has_bounds else world_bounds
		has_bounds = true
	if not has_bounds or bounds.size.x < 0.1 or bounds.size.z < 0.1:
		return
	var surface_y := bounds.position.y + bounds.size.y
	var area := Area3D.new()
	area.name = "WaterVolume_%d" % water_tour_points.size()
	area.collision_layer = 4
	area.collision_mask = 1
	area.position = Vector3(bounds.get_center().x, surface_y - 1.5, bounds.get_center().z)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(bounds.size.x, 0.5), 3.2, maxf(bounds.size.z, 0.5))
	collision.shape = shape
	area.add_child(collision)
	area.body_entered.connect(_on_water_entered.bind(surface_y))
	area.body_exited.connect(_on_water_exited)
	$DAOScene.add_child(area)
	var village_water := Vector3(
		clampf(CLUSTER.x, bounds.position.x + 2.0, bounds.end.x - 2.0),
		surface_y,
		clampf(-CLUSTER.y, bounds.position.z + 2.0, bounds.end.z - 2.0))
	water_tour_points.append({"position": village_water, "surface_y": surface_y, "size": bounds.size, "bounds": bounds})
	print("OPENDAO_WATER_VOLUME name=%s surface_y=%.3f bounds=%s tour=%s" % [area.name, surface_y, str(bounds), str(village_water)])

func _on_water_entered(body: Node3D, surface_y: float) -> void:
	if body == $Player:
		$Player.set_water_state(true, surface_y)

func _on_water_exited(body: Node3D) -> void:
	if body == $Player:
		$Player.set_water_state(false, 0.0)

func _run_shareable_tour(kind: String) -> void:
	$Player.set_scripted_motion(true)
	$Status.text = "OpenDAO compatibility proof  |  %s" % kind.to_upper()
	print("OPENDAO_TOUR_BEGIN kind=%s" % kind)
	if kind == "water":
		await _tour_waterfront()
	elif kind == "scout":
		await _tour_water_scout()
	elif kind == "town":
		await _tour_town()
	elif kind == "door":
		await _tour_door()
	else:
		await _tour_waterfront()
	print("OPENDAO_TOUR_COMPLETE kind=%s" % kind)
	get_tree().quit()

func _tour_waterfront() -> void:
	if water_tour_points.is_empty():
		push_error("OPENDAO_TOUR no authored water volume")
		return
	var chosen: Dictionary = water_tour_points[0]
	var best_distance := INF
	for candidate_value in water_tour_points:
		var candidate: Dictionary = candidate_value
		var point: Vector3 = candidate.position
		var distance := Vector2(point.x - CLUSTER.x, point.z + CLUSTER.y).length_squared()
		if distance < best_distance:
			chosen = candidate
			best_distance = distance
	# Visually scouted open-water point: clear of stilt undersides, with the
	# village, windmill, shoreline and sky all readable in one composition.
	var center := Vector3(260.0, float(chosen.surface_y), -150.0)
	$Player.global_position = center + Vector3(0.0, 0.18, 0.0)
	$Player.set_water_state(true, float(chosen.surface_y))
	$Player.look_at_target(Vector3(CLUSTER.x, 4.0, -CLUSTER.y))
	print("OPENDAO_TOUR_SHOT shot=water_float position=%s surface=%.3f" % [str($Player.global_position), float(chosen.surface_y)])
	await _hold_and_pan(7.0, 20.0)

func _tour_water_scout() -> void:
	var candidates := [
		Vector3(260.0, 0.18, -260.0), Vector3(220.0, 0.18, -260.0),
		Vector3(300.0, 0.18, -220.0), Vector3(200.0, 0.18, -210.0),
		Vector3(350.0, 0.18, -250.0), Vector3(150.0, 0.18, -250.0),
		Vector3(260.0, 0.18, -150.0), Vector3(360.0, 0.18, -150.0)]
	for index in candidates.size():
		$Player.global_position = candidates[index]
		$Player.look_at_target(Vector3(CLUSTER.x, 4.0, -CLUSTER.y))
		$Status.text = "OpenDAO water location scout  |  %d" % (index + 1)
		print("OPENDAO_SCOUT index=%d position=%s" % [index + 1, str(candidates[index])])
		for frame in 30:
			await get_tree().process_frame

func _find_open_water_point(water: Dictionary) -> Vector3:
	var bounds: AABB = water.bounds
	var surface_y := float(water.surface_y)
	var best: Vector3 = water.position
	var best_score := INF
	var space := get_world_3d().direct_space_state
	# Search the authored lake for a point where structural/terrain geometry is
	# below the surface, then favor the closest clear water to Redcliffe.
	for x_step in range(1, 20):
		for z_step in range(1, 20):
			var x := lerpf(bounds.position.x, bounds.end.x, float(x_step) / 20.0)
			var z := lerpf(bounds.position.z, bounds.end.z, float(z_step) / 20.0)
			var query := PhysicsRayQueryParameters3D.create(Vector3(x, surface_y + 80.0, z), Vector3(x, surface_y - 20.0, z))
			query.collision_mask = 3
			query.hit_back_faces = true
			query.exclude = [$Player.get_rid()]
			var hit := space.intersect_ray(query)
			if not hit.is_empty() and hit.position.y > surface_y - 0.35:
				continue
			var score := Vector2(x - CLUSTER.x, z + CLUSTER.y).length_squared()
			if score < best_score:
				best_score = score
				best = Vector3(x, surface_y, z)
	print("OPENDAO_WATER_CLEAR_POINT point=%s score=%.3f" % [str(best), best_score])
	return best

func _tour_town() -> void:
	$Player.global_position = Vector3(250.0, 4.0, -307.0)
	$Player.look_at_target(Vector3(260.0, 2.5, -300.0))
	print("OPENDAO_TOUR_SHOT shot=town_people actors=%d" % loaded_actors)
	var duration := 15.0 if OS.get_environment("DAOPEN_XR_CAPTURE") == "1" else 7.0
	await _hold_and_pan(duration, 26.0)

func _tour_door() -> void:
	$Player.global_position = Vector3(250.0, 3.15, -307.0)
	$Player.look_at_target(Vector3(260.0, 2.5, -300.0))
	await _hold_and_pan(1.0, 4.0)
	current_return_position = $Player.global_position
	_set_tour_cover(true, "STREAMING REDCLIFFE TAVERN…")
	await _transition_to_interior("lak103d", "arl150ar_tavern")
	$Player.set_scripted_motion(true)
	var inward: Vector3 = -$Player.global_basis.z
	inward.y = 0.0
	inward = inward.normalized()
	$Player.global_position += inward * 4.2 + Vector3.UP * 0.25
	$Player.look_at_target($Player.global_position + inward * 10.0 + Vector3.UP * 0.4)
	_set_tour_cover(false)
	print("OPENDAO_TOUR_SHOT shot=tavern_interior actors=%d lights=%d position=%s" % [loaded_actors, loaded_lights, str($Player.global_position)])
	await _hold_and_pan(3.5, 12.0)
	_set_tour_cover(true, "RETURNING TO REDCLIFFE VILLAGE…")
	await _transition_to_village()
	$Player.set_scripted_motion(true)
	$Player.global_position = Vector3(250.0, 3.15, -307.0)
	$Player.look_at_target(Vector3(260.0, 2.5, -300.0))
	_set_tour_cover(false)
	print("OPENDAO_TOUR_SHOT shot=door_return actors=%d" % loaded_actors)
	await _hold_and_pan(1.5, 7.0)

func _set_tour_cover(enabled: bool, message: String = "") -> void:
	if tour_cover != null:
		tour_cover.queue_free()
		tour_cover = null
	if not enabled:
		return
	tour_cover = Control.new()
	tour_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tour_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.012, 0.008, 0.01, 1.0)
	tour_cover.add_child(background)
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.offset_left = -300.0
	label.offset_top = -30.0
	label.offset_right = 300.0
	label.offset_bottom = 30.0
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	tour_cover.add_child(label)
	add_child(tour_cover)

func _hold_and_pan(seconds: float, degrees: float) -> void:
	var frames := int(seconds * 30.0)
	for frame in frames:
		$Player.rotation.y += deg_to_rad(degrees) / float(frames)
		await get_tree().process_frame

func _apply_water_shader(root: Node, shader: Shader) -> void:
	if shader == null:
		return
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var material := ShaderMaterial.new()
			material.shader = shader
			mesh_instance.set_surface_override_material(surface, material)

func _spawn_actor(root: String, actor: Dictionary) -> void:
	var relative := str(actor.get("model", ""))
	if relative.is_empty():
		return
	var packed := _load_glb(root.path_join(relative))
	if packed == null:
		return
	var node := packed.instantiate() as Node3D
	node.name = str(actor.get("template", "DAOActor"))
	_apply_dao_transform(node, actor)
	$DAOScene.add_child(node)
	_prepare_meshes(node)
	_play_default_animation(node)
	loaded_actors += 1
	await get_tree().process_frame

func _load_glb(path: String) -> PackedScene:
	if prototypes.has(path):
		return prototypes[path]
	if path.begins_with("res://"):
		var imported := load(path) as PackedScene
		if imported != null:
			prototypes[path] = imported
		return imported
	if not FileAccess.file_exists(path):
		print("OPENDAO_OPTIONAL_MISSING path=" + path)
		return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(path, state)
	if error != OK:
		push_warning("OpenDAO: glTF load failed %s error=%d" % [path, error])
		return null
	var generated := document.generate_scene(state)
	if generated == null:
		return null
	var packed := PackedScene.new()
	if packed.pack(generated) != OK:
		generated.free()
		return null
	generated.free()
	prototypes[path] = packed
	return packed

func _apply_dao_transform(node: Node3D, record: Dictionary) -> void:
	var p := _array_vec3(record.get("position", [0, 0, 0]))
	# DAO/Haven is Z-up; Godot is Y-up.
	node.position = Vector3(p.x, p.z, -p.y)
	var qv: Array = record.get("rotation", [0, 0, 0, 1])
	if qv.size() >= 4:
		var source_q := Quaternion(float(qv[0]), float(qv[1]), float(qv[2]), float(qv[3]))
		var source_basis := Basis(source_q)
		var convert := Basis(Vector3.RIGHT, Vector3(0, 0, -1), Vector3(0, 1, 0))
		node.basis = convert * source_basis * convert.inverse()
	var scale_value := float(record.get("scale", 1.0))
	node.scale = Vector3.ONE * scale_value

func _prepare_meshes(root: Node) -> void:
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
			if source == null:
				continue
			var material := source.duplicate() as BaseMaterial3D
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			material.metallic = 0.0
			material.roughness = 0.72
			mesh_instance.set_surface_override_material(surface, material)

func _play_default_animation(root: Node) -> void:
	for candidate in root.find_children("*", "AnimationPlayer", true, false):
		var player := candidate as AnimationPlayer
		for animation_name in player.get_animation_list():
			if animation_name == "RESET":
				continue
			var animation := player.get_animation(animation_name)
			animation.loop_mode = Animation.LOOP_LINEAR
			player.play(animation_name)
			return

func _create_trimesh_collision(root: Node, collision_layers: int = 1) -> void:
	for candidate in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance.mesh != null:
			_create_mesh_collision(mesh_instance, collision_layers)

func _create_mesh_collision(mesh_instance: MeshInstance3D, collision_layers: int) -> void:
	mesh_instance.create_trimesh_collision()
	for child in mesh_instance.get_children():
		if child is StaticBody3D:
			var body := child as StaticBody3D
			body.collision_layer = collision_layers
			body.collision_mask = 0

func _array_vec3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _array_vec4(value: Array, fallback: Vector4) -> Vector4:
	if value.size() < 4:
		return fallback
	return Vector4(float(value[0]), float(value[1]), float(value[2]), float(value[3]))

func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

func _capture_if_requested() -> void:
	var capture_path := OS.get_environment("DAOPEN_CAPTURE")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
	if capture_path.is_empty():
		return
	# Forward+ fog volumes rely on temporal reprojection. A first-frame image is
	# not representative, so allow the froxel history and procedural resources
	# to converge before producing visual evidence.
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		for frame_index in 24:
			await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(capture_path)
	print("OPENDAO_CAPTURE path=%s error=%d size=%dx%d" % [capture_path, error, image.get_width(), image.get_height()])
	get_tree().quit(0 if error == OK else 3)
