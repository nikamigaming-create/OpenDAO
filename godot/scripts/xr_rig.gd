extends XROrigin3D

var active := false
var spectator_camera: Camera3D

func _ready() -> void:
	# Capture/CI runs stay desktop-only and never wake an installed XR runtime.
	if not OS.get_environment("DAOPEN_CAPTURE").is_empty() or (not OS.get_environment("DAOPEN_TOUR").is_empty() and OS.get_environment("DAOPEN_XR_CAPTURE") != "1"):
		print("OPENDAO_XR disabled=true reason=deterministic_desktop_capture")
		return
	var xr_interface := XRServer.find_interface("OpenXR")
	if xr_interface == null or not xr_interface.is_initialized():
		print("OPENDAO_XR fallback=desktop reason=no_initialized_runtime")
		return
	active = true
	get_viewport().use_xr = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.physics_ticks_per_second = 90
	$"../Head/Camera3D".current = false
	$XRCamera3D.current = true
	$"..".set_xr_active(true, $XRCamera3D, $LeftHand)
	print("OPENDAO_XR ready=true interface=OpenXR")
	if OS.get_environment("DAOPEN_XR_CAPTURE") == "1":
		_create_spectator_mirror()

func _process(_delta: float) -> void:
	if spectator_camera != null:
		spectator_camera.global_transform = $XRCamera3D.global_transform

func _create_spectator_mirror() -> void:
	get_tree().root.gui_embed_subwindows = false
	var mirror_window := Window.new()
	mirror_window.title = "OpenDAO XR Spectator"
	mirror_window.size = Vector2i(1280, 720)
	mirror_window.unresizable = true
	var viewport_container := SubViewportContainer.new()
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch = true
	var spectator_viewport := SubViewport.new()
	spectator_viewport.size = Vector2i(1280, 720)
	spectator_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	spectator_viewport.world_3d = get_viewport().world_3d
	viewport_container.add_child(spectator_viewport)
	spectator_camera = Camera3D.new()
	spectator_camera.fov = 78.0
	spectator_camera.near = 0.05
	spectator_camera.far = 1000.0
	spectator_viewport.add_child(spectator_camera)
	spectator_camera.current = true
	mirror_window.add_child(viewport_container)
	var badge := Label.new()
	badge.text = "META XR SIMULATOR  •  OPENDAO"
	badge.position = Vector2(18, 14)
	badge.add_theme_font_size_override("font_size", 18)
	mirror_window.add_child(badge)
	add_child(mirror_window)
	print("OPENDAO_XR_SPECTATOR ready=true title=OpenDAO XR Spectator size=1280x720")
