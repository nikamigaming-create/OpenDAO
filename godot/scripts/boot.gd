extends Control

const SAVE_PATH := "user://saves/slot1.json"

func _ready() -> void:
	$Movie.finished.connect(_show_menu)
	$Menu/Buttons/NewGame.pressed.connect(_new_game)
	$Menu/Buttons/Continue.pressed.connect(_continue_game)
	$Menu/Buttons/Quit.pressed.connect(func(): get_tree().quit())
	$Menu/Buttons/Continue.disabled = not FileAccess.file_exists(SAVE_PATH)
	if OS.get_environment("OPENDAO_SMOKE_EXIT") == "1":
		_show_menu()
		print("OPENDAO_RUNTIME_SMOKE_PASS")
		get_tree().quit()
		return
	# Automated renderer validation must never wait at the movie/menu or require
	# foreground input. Interactive launches still show the normal boot flow.
	if not OS.get_environment("DAOPEN_CAPTURE").is_empty() or not OS.get_environment("DAOPEN_TOUR").is_empty():
		_load_world()
	elif $Movie.stream == null:
		_show_menu()

func _unhandled_input(event: InputEvent) -> void:
	if $Movie.visible and event.is_pressed():
		_show_menu()

func _show_menu() -> void:
	$Movie.stop()
	$Movie.visible = false
	$Skip.visible = false
	$Menu.visible = true
	$Menu/Buttons/NewGame.grab_focus()

func _new_game() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://saves"))
	var save := {
		"schema": 1,
		"character": {
			"name": "Aedan",
			"race": "Human",
			"origin": "Human Noble",
			"class": "Warrior",
			"level": 1,
			"experience": 0
		},
		"area": "Redcliffe Village",
		"spawn": {"x": 255.0, "y": 2.7523, "z": -316.0},
		"actors_loaded": 12
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(save, "  "))
	file.close()
	_load_world()

func _continue_game() -> void:
	_load_world()

func _load_world() -> void:
	$Menu.visible = false
	$Loading.visible = true
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://main.tscn")
