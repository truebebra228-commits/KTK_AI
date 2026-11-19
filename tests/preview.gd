extends SceneTree
## Render the start menu, settings and live gameplay/placement states.

func _initialize() -> void:
	call_deferred("capture")

func frames(count: int) -> void:
	for i: int in range(count):
		await physics_frame

func save_frame(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/" + name + ".png")

func capture() -> void:
	var game: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://previews"))
	await frames(12)
	await save_frame("menu")
	game.open_settings()
	await frames(4)
	await save_frame("settings")
	game.close_settings()
	game.start_game()
	await frames(12)
	await save_frame("gameplay")
	for index: int in range(game.room_count):
		game.load_room(index)
		game.toast_time = 0.0
		await frames(18)
		await save_frame("room-%d" % (index + 1))
	# A real draggable preview in the final, playable celebration room.
	game.begin_placement()
	game.update_placement(game.player.position + Vector2(60, -25))
	await frames(4)
	await save_frame("placement-preview")
	game.commit_placement()
	await frames(20)
	game.begin_placement()
	game.update_placement(game.player.position + Vector2(-65, -45))
	game.commit_placement()
	await frames(35)
	await save_frame("sandbox-confetti")
	# Show a blast produced by a real, released cursor charge below the hero.
	game._clear_bombs()
	game.plant_cooldown = 0.0
	game.begin_placement()
	game.update_placement(game.player.position + Vector2(0, 9))
	game.commit_placement()
	await frames(3)
	game.detonate_bombs()
	await frames(24)
	await save_frame("sandbox-flight")
	game.queue_free()
	await process_frame
	await process_frame
	quit()
