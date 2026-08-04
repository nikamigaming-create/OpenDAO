extends CharacterBody3D

@export var walk_speed := 5.0
@export var sprint_speed := 9.0
@export var mouse_sensitivity := 0.0018
@export var jump_velocity := 6.5
@export var gravity := 18.0
@export var swim_speed := 4.2
var xr_active := false
var locomotion_camera: Camera3D
var left_controller: XRController3D
var vertical_velocity := 0.0
var grounded := true
var in_water := false
var water_surface_y := 0.0
var scripted_motion := false
const GROUND_CLEARANCE := 0.95
const GROUND_RAY_UP := 0.1
const GROUND_RAY_DOWN := 80.0
const MAX_STEP_UP := 0.38

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	floor_snap_length = 0.55
	floor_max_angle = deg_to_rad(50.0)
	floor_constant_speed = true
	floor_stop_on_slope = true
	floor_block_on_wall = true
	# The cooked DAO terrain is split into independent triangle sectors. Sliding
	# a capsule over their border edges catches on seams, so locomotion follows
	# the authored surface with a downward probe instead of treating every seam
	# as a wall.
	collision_mask = 0
	locomotion_camera = $Head/Camera3D

func set_xr_active(enabled: bool, xr_camera: Camera3D, controller: XRController3D) -> void:
	xr_active = enabled
	locomotion_camera = xr_camera if enabled else $Head/Camera3D
	left_controller = controller
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if enabled else Input.MOUSE_MODE_CAPTURED

func set_scripted_motion(enabled: bool) -> void:
	scripted_motion = enabled
	vertical_velocity = 0.0

func set_water_state(enabled: bool, surface_y: float) -> void:
	in_water = enabled
	water_surface_y = surface_y
	vertical_velocity = 0.0
	print("OPENDAO_WATER_STATE active=%s surface_y=%.3f position=%s" % [str(enabled), surface_y, str(global_position)])

func look_at_target(target: Vector3) -> void:
	# Keep the desktop camera itself unrotated. Yaw belongs to the body and pitch
	# belongs to the head, otherwise the initial look-at transform makes later
	# mouse pitch feel like an orbit around a tilted axis.
	var camera := $Head/Camera3D as Camera3D
	camera.rotation = Vector3.ZERO
	var direction := (target - camera.global_position).normalized()
	rotation.y = atan2(-direction.x, -direction.z)
	$Head.rotation = Vector3(asin(clampf(direction.y, -1.0, 1.0)), 0.0, 0.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		$Head.rotate_x(-event.relative.y * mouse_sensitivity)
		$Head.rotation.x = clamp($Head.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if scripted_motion:
		velocity = Vector3.ZERO
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if xr_active and left_controller != null:
		var stick := left_controller.get_vector2("primary")
		if stick.length() > input.length():
			input = stick
	var camera := locomotion_camera
	var forward := -camera.global_basis.z
	var right := camera.global_basis.x
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()
	var direction := (right * input.x + forward * -input.y).normalized()
	if in_water:
		var swim_target := water_surface_y - 0.22
		var vertical_input := 1.0 if Input.is_action_pressed("jump") else 0.0
		var buoyancy := clampf((swim_target - global_position.y) * 3.6, -2.2, 2.2)
		global_position += direction * swim_speed * delta
		global_position.y += (buoyancy + vertical_input * 2.4) * delta
		grounded = false
		vertical_velocity = 0.0
		velocity = Vector3.ZERO
		return
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var requested := global_position + direction * speed * delta
	if not direction.is_zero_approx() and _structure_blocks(global_position, requested):
		requested.x = global_position.x
		requested.z = global_position.z
	var hit := _find_ground_surface(requested)
	if not hit.is_empty():
		var surface_normal: Vector3 = hit["normal"]
		var slope: float = surface_normal.angle_to(Vector3.UP)
		var surface_position: Vector3 = hit["position"]
		var ground_height := surface_position.y + GROUND_CLEARANCE
		var step_up := ground_height - global_position.y
		grounded = vertical_velocity <= 0.0 and step_up <= MAX_STEP_UP and global_position.y <= ground_height + 0.14
		if grounded and Input.is_action_just_pressed("jump"):
			grounded = false
			vertical_velocity = jump_velocity
		if grounded:
			vertical_velocity = 0.0
			requested.y = ground_height
		elif vertical_velocity > 0.0 or global_position.y > ground_height:
			vertical_velocity -= gravity * delta
			requested.y = global_position.y + vertical_velocity * delta
			if vertical_velocity <= 0.0 and requested.y <= ground_height:
				requested.y = ground_height
				vertical_velocity = 0.0
				grounded = true
		if slope <= floor_max_angle or direction.is_zero_approx() or not grounded:
			global_position = requested
	else:
		grounded = false
		vertical_velocity -= gravity * delta
		requested.y = global_position.y + vertical_velocity * delta
		global_position = requested
	velocity = Vector3.ZERO

func _find_ground_surface(position: Vector3) -> Dictionary:
	# DAO walkable geometry is not confined to terrain patches: interiors,
	# porches, bridges, stairs and platforms are structural props. Some source
	# floors have reversed winding, so search both faces, but skip ceilings,
	# steep faces and surfaces too high to be a legitimate step.
	var space := get_world_3d().direct_space_state
	var ray_end := position - Vector3.UP * GROUND_RAY_DOWN
	var ray_start := position + Vector3.UP * GROUND_RAY_UP
	for attempt in range(12):
		var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		query.exclude = [get_rid()]
		query.collision_mask = 3
		query.hit_back_faces = true
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return {}
		var normal: Vector3 = hit["normal"]
		if normal.y < 0.0:
			normal = -normal
		var candidate_height: float = hit["position"].y + GROUND_CLEARANCE
		if normal.angle_to(Vector3.UP) <= floor_max_angle and candidate_height - position.y <= MAX_STEP_UP:
			hit["normal"] = normal
			return hit
		# Continue immediately below a rejected ceiling/edge to find the floor.
		ray_start = hit["position"] - Vector3.UP * 0.03
	return {}

func _structure_blocks(from_position: Vector3, to_position: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	# Three forward probes approximate the standing capsule while leaving the
	# downward floor/terrain probe independent of wall collision.
	for height in [0.18, 0.85, 1.52]:
		var offset := Vector3.UP * float(height)
		var query := PhysicsRayQueryParameters3D.create(from_position + offset, to_position + offset)
		query.exclude = [get_rid()]
		query.collision_mask = 2
		if not space.intersect_ray(query).is_empty():
			return true
	return false
