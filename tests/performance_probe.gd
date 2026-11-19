extends SceneTree
## Real, uncapped OpenGL measurements; no --fixed-fps and no headless FPS claim.
## --script tests/performance_probe.gd -- [--baseline-only|--current-only]
## CPU draw timings measure command generation, not GPU execution time.

class TimedBaseline extends "res://tests/performance_baseline_level.gd":
	var draw_timings: PackedFloat64Array = PackedFloat64Array()
	func _draw() -> void:
		var start: int = Time.get_ticks_usec()
		super._draw()
		draw_timings.append(float(Time.get_ticks_usec() - start))

class TimedCurrent extends "res://scripts/level.gd":
	var draw_timings: PackedFloat64Array = PackedFloat64Array()
	func _draw() -> void:
		var start: int = Time.get_ticks_usec()
		super._draw()
		draw_timings.append(float(Time.get_ticks_usec() - start))

const SAMPLES_PER_ROOM: int = 250
var game: Node2D

func _initialize() -> void:
	call_deferred("run_probe")

func summary(values: PackedFloat64Array) -> Dictionary:
	if values.is_empty():
		return {"samples": 0}
	var sorted: PackedFloat64Array = values.duplicate()
	sorted.sort()
	var sum: float = 0.0
	for value: float in values:
		sum += value
	return {"samples": values.size(), "mean": sum / float(values.size()),
		"median": sorted[int(sorted.size() / 2)],
		"p95": sorted[int((sorted.size() - 1) * 0.95)], "maximum": sorted[-1]}

func next_draw() -> void:
	await process_frame
	await RenderingServer.frame_post_draw

func benchmark(kind: String, room_index: int) -> Dictionary:
	game.load_room(room_index)
	var old_level: Node2D = game.level
	var world: Node = old_level.get_parent()
	world.remove_child(old_level)
	old_level.queue_free()
	var measured: Node2D = TimedBaseline.new() if kind == "baseline" else TimedCurrent.new()
	measured.room_index = room_index
	game.level = measured
	var load_start: int = Time.get_ticks_usec()
	world.add_child(measured)
	world.move_child(measured, 0)
	var ready_us: int = Time.get_ticks_usec() - load_start
	game.is_sandbox = measured.sandbox
	game.player.reset_at(measured.checkpoints[0])
	game._set_simulation(true)
	await next_draw()
	var first_frame_us: int = Time.get_ticks_usec() - load_start
	var initial_draw_us: float = float(measured.draw_timings[0]) if not measured.draw_timings.is_empty() else 0.0
	for warmup: int in range(40):
		await next_draw()
	measured.draw_timings.clear()
	var process_us: PackedFloat64Array = PackedFloat64Array()
	var physics_us: PackedFloat64Array = PackedFloat64Array()
	var draw_calls: PackedFloat64Array = PackedFloat64Array()
	var start_frames: int = Engine.get_frames_drawn()
	var start_us: int = Time.get_ticks_usec()
	for sample: int in range(SAMPLES_PER_ROOM):
		if sample % 100 == 0:
			game.cancel_placement()
			game.player.reset_at(measured.checkpoints[0])
			game.charges = 3
			game.plant_cooldown = 0.0
			game.begin_placement()
		if game.placing_bomb:
			game.update_placement(game.player.position + Vector2(cos(sample * 0.05) * 75.0, -42.0 + sin(sample * 0.07) * 14.0))
		if sample % 100 == 45:
			game.commit_placement()
		if sample % 100 == 78:
			game.detonate_bombs()
		await next_draw()
		process_us.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000000.0)
		physics_us.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000000.0)
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var elapsed_us: int = Time.get_ticks_usec() - start_us
	var actual_frames: int = Engine.get_frames_drawn() - start_frames
	game.cancel_placement()
	return {"variant": kind, "room": room_index + 1, "sandbox": measured.sandbox,
		"synchronous_ready_us": ready_us, "ready_to_first_render_us": first_frame_us,
		"first_level_draw_generation_us": initial_draw_us,
		"steady_level_draw_generation_us": summary(measured.draw_timings),
		"engine_process_monitor_us": summary(process_us),
		"engine_physics_monitor_us": summary(physics_us),
		"gpu_draw_calls_per_frame": summary(draw_calls),
		"wall_us": elapsed_us, "actual_rendered_frames": actual_frames,
		"observed_uncapped_render_frames_per_second": float(actual_frames) * 1000000.0 / float(elapsed_us)}

func run_probe() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run this probe with the real renderer; headless throughput is not game FPS.")
		quit(2)
		return
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game = load("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(game)
	game.sound.set_enabled(false)
	game.start_game()
	for warmup: int in range(40):
		await next_draw()
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var variants: Array[String] = ["baseline", "current"]
	var tag: String = "comparison"
	if arguments.has("--baseline-only"):
		variants = ["baseline"]
		tag = "baseline"
	elif arguments.has("--current-only"):
		variants = ["current"]
		tag = "current"
	var measurements: Array[Dictionary] = []
	for variant: String in variants:
		for room: int in [0, 4]:
			var result: Dictionary = await benchmark(variant, room)
			measurements.append(result)
			print("PERF ", JSON.stringify(result))
	# Isolate pose math from rendering; this does not assert or simulate game FPS.
	var arms: Node2D = game.player.arms
	arms.set_hold_target(game.player.position + Vector2(80, -25), true)
	var pose_start: int = Time.get_ticks_usec()
	for step: int in range(10000):
		arms._step_pose(1.0 / 120.0)
	var pose_mean_us: float = float(Time.get_ticks_usec() - pose_start) / 10000.0
	var report: Dictionary = {"engine": Engine.get_version_info(), "os": OS.get_name(),
		"display_server": DisplayServer.get_name(), "vsync": "disabled", "fixed_fps": false,
		"notes": "Real rendered-frame throughput on this machine; CPU draw timing excludes GPU execution. First-render wall includes static child command generation and submission.",
		"monitor_warning": "Engine TIME_* monitor snapshots refresh asynchronously and may include stale startup values. Their sampled averages are not per-frame CPU profiler measurements; compare direct draw timings instead.",
		"isolated_arms_pose_mean_us": pose_mean_us, "measurements": measurements}
	var output: String = "res://previews/performance-%s.json" % tag
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("PERF_REPORT ", output, " arms_pose_mean_us=", pose_mean_us)
	game.queue_free()
	await process_frame
	await process_frame
	quit(0)
