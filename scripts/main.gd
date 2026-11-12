extends Node2D

const PlayerScript = preload("res://scripts/player.gd")
const BombScript = preload("res://scripts/bomb.gd")
const LevelScript = preload("res://scripts/level.gd")
const EffectsScript = preload("res://scripts/effects.gd")
const SoundScript = preload("res://scripts/sound.gd")
const HudScript = preload("res://scripts/hud.gd")
const RoomsScript = preload("res://scripts/rooms.gd")
const CYAN: Color = Color("b2bf8d")
const AMBER: Color = Color("e09b48")
const SCREEN_CENTER: Vector2 = Vector2(640, 360)
const PLACEMENT_RADIUS: float = 60.0
const BOMB_RADIUS: float = 9.0
const MAX_BOMBS: int = 3
const FADE_IN: float = 0.22
const FADE_HOLD: float = 0.08
const FADE_OUT: float = 0.25

var level: Node2D
var player: CharacterBody2D
var effects: Node2D
var sound: Node
var hud: Control
var camera: Camera2D
var bombs: Array[Node2D] = []
var charges: int = 3
var checkpoint: int = 0
var mode: String = "playing"
var elapsed: float = 0.0
var deaths: int = 0
var blasts: int = 0
var zone: int = 0
var shake: float = 0.0
var toast: String = ""
var toast_time: float = 0.0
var plant_cooldown: float = 0.0
var trail_timer: float = 0.0
var room_index: int = 0
var room_count: int = 5
var challenge_count: int = 4
var is_sandbox: bool = false
var transition_alpha: float = 0.0
var transition_elapsed: float = 0.0
var next_room: int = -1
var transition_loaded: bool = false
var placing_bomb: bool = false
var placement_position: Vector2 = Vector2.ZERO
var placement_cursor_position: Vector2 = Vector2.ZERO
var placement_valid: bool = false
var placement_preview: Node2D
var preview_texture: Texture2D
var _placement_query: PhysicsShapeQueryParameters2D
var _placement_ray: PhysicsRayQueryParameters2D

func _ready() -> void:
	_bind_inputs()
	room_count = RoomsScript.definitions().size()
	level = LevelScript.new()
	add_child(level)
	effects = EffectsScript.new()
	add_child(effects)
	player = PlayerScript.new()
	add_child(player)
	player.reset_at(level.checkpoints[0])
	player.jumped.connect(func() -> void: sound.play("jump"))
	player.landed.connect(_on_land)
	camera = Camera2D.new()
	camera.position = SCREEN_CENTER
	camera.position_smoothing_enabled = false
	camera.limit_left = 0
	camera.limit_right = 1280
	camera.limit_top = 0
	camera.limit_bottom = 720
	add_child(camera)
	sound = SoundScript.new()
	add_child(sound)
	preview_texture = BombScript.visual_texture()
	_placement_query = PhysicsShapeQueryParameters2D.new()
	var placement_shape: CircleShape2D = CircleShape2D.new()
	placement_shape.radius = BOMB_RADIUS
	_placement_query.shape = placement_shape
	_placement_query.collision_mask = 1
	_placement_query.collide_with_areas = false
	_placement_query.margin = 0.25
	_placement_ray = PhysicsRayQueryParameters2D.new()
	_placement_ray.collision_mask = 1
	placement_preview = Node2D.new()
	placement_preview.name = "BombPlacementPreview"
	placement_preview.z_index = 20
	placement_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(placement_preview)
	placement_preview.draw.connect(_draw_placement)
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	hud = HudScript.new()
	hud.game = self
	canvas.add_child(hud)
	var save: ConfigFile = ConfigFile.new()
	if save.load("user://record.cfg") == OK:
		sound.set_enabled(bool(save.get_value("settings", "audio", true)))
	level.set_checkpoint_active(0)
	_set_simulation(true)

func _bind_inputs() -> void:
	_key("left", [KEY_A, KEY_LEFT])
	_key("right", [KEY_D, KEY_RIGHT])
	_key("jump", [KEY_SPACE, KEY_W, KEY_UP])
	_key("detonate", [KEY_F])
	_key("brake", [KEY_S, KEY_DOWN])
	_key("restart", [KEY_R])
	_key("pause", [KEY_ESCAPE])
	_key("mute", [KEY_M])
	for pair: Array in [["place_mouse", MOUSE_BUTTON_LEFT], ["detonate", MOUSE_BUTTON_RIGHT]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
		var mouse: InputEventMouseButton = InputEventMouseButton.new()
		mouse.button_index = pair[1]
		InputMap.action_add_event(pair[0], mouse)

func _key(action: String, codes: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for code: int in codes:
		var key: InputEventKey = InputEventKey.new()
		key.physical_keycode = code
		InputMap.action_add_event(action, key)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mute"):
		sound.set_enabled(not sound.enabled)
		_save_settings()
	if mode == "transition":
		return
	if event.is_action_pressed("pause"):
		cancel_placement()
		mode = "playing" if mode == "paused" else "paused"
		_set_simulation(mode == "playing")
		return
	if mode != "playing":
		return
	if event.is_action_pressed("restart"):
		if is_sandbox:
			restart_run()
		else:
			respawn(false)
		return
	if event is InputEventMouseMotion and placing_bomb:
		update_placement(get_global_mouse_position())
	if event.is_action_pressed("place_mouse"):
		begin_placement()
	elif event.is_action_released("place_mouse"):
		commit_placement()
	if event.is_action_pressed("detonate"):
		detonate_bombs()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready():
		cancel_placement()

func _process(delta: float) -> void:
	if mode != "transition":
		return
	transition_elapsed += delta
	if transition_elapsed < FADE_IN:
		transition_alpha = clampf(transition_elapsed / FADE_IN, 0.0, 1.0)
		return
	transition_alpha = 1.0
	if not transition_loaded:
		load_room(next_room)
		transition_loaded = true
		if is_sandbox:
			sound.play("win")
	if transition_elapsed < FADE_IN + FADE_HOLD:
		return
	transition_alpha = 1.0 - clampf((transition_elapsed - FADE_IN - FADE_HOLD) / FADE_OUT, 0.0, 1.0)
	if transition_elapsed >= FADE_IN + FADE_HOLD + FADE_OUT:
		transition_alpha = 0.0
		next_room = -1
		mode = "playing"
		_set_simulation(true)
		notify("Путь пройден! Здесь можно играть сколько угодно." if is_sandbox else "Комната %d / %d — %s" % [room_index + 1, challenge_count, level.zone_names[room_index]])

func advance_room() -> void:
	if mode != "playing" or is_sandbox or room_index + 1 >= room_count:
		return
	cancel_placement()
	mode = "transition"
	next_room = room_index + 1
	transition_elapsed = 0.0
	transition_alpha = 0.0
	transition_loaded = false
	toast_time = 0.0
	_set_simulation(false)
	sound.play("checkpoint")

func restart_run() -> void:
	# Final-room replay starts a fresh run while retaining the audio preference.
	mode = "playing"
	elapsed = 0.0
	deaths = 0
	blasts = 0
	transition_alpha = 0.0
	transition_elapsed = 0.0
	transition_loaded = false
	next_room = -1
	toast = ""
	toast_time = 0.0
	placement_position = Vector2.ZERO
	placement_cursor_position = Vector2.ZERO
	load_room(0)
	player.facing = 1.0
	player.squash = 0.0
	_set_simulation(true)

func load_room(index: int) -> void:
	_clear_bombs()
	if is_instance_valid(level):
		remove_child(level)
		level.queue_free()
	room_index = clampi(index, 0, room_count - 1)
	zone = room_index
	checkpoint = 0
	level = LevelScript.new()
	level.room_index = room_index
	add_child(level)
	move_child(level, 0)
	is_sandbox = level.sandbox
	level.set_checkpoint_active(0)
	level.set_paused(mode != "playing")
	player.reset_at(level.checkpoints[0])
	charges = 3
	plant_cooldown = 0.0
	trail_timer = 0.0
	shake = 0.0
	camera.position = SCREEN_CENTER
	camera.offset = Vector2.ZERO
	camera.reset_smoothing()
	effects.sparks.clear()
	effects.ghosts.clear()
	effects.smoke.clear()
	effects.queue_redraw()

func _clear_bombs() -> void:
	cancel_placement()
	for bomb: Node2D in bombs:
		if is_instance_valid(bomb):
			bomb.set_process(false)
			bomb.set_physics_process(false)
			remove_child(bomb)
			bomb.queue_free()
	bombs.clear()

func _set_simulation(active: bool) -> void:
	player.enabled = active
	player.arms.set_active(active)
	for bomb: Node2D in bombs:
		if is_instance_valid(bomb):
			bomb.set_process(active)
			bomb.set_physics_process(active)
	effects.set_process(active)
	level.set_paused(not active)

func _physics_process(delta: float) -> void:
	shake = maxf(0.0, shake - delta * 28.0)
	camera.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	toast_time = maxf(0.0, toast_time - delta)
	plant_cooldown = maxf(0.0, plant_cooldown - delta)
	if mode != "playing":
		return
	elapsed += delta
	if placing_bomb:
		update_placement(placement_cursor_position)
	for i: int in range(bombs.size() - 1, -1, -1):
		if not is_instance_valid(bombs[i]):
			bombs.remove_at(i)
	trail_timer -= delta
	if player.velocity.length() > 490.0 and trail_timer <= 0.0:
		effects.trail(player.position + Vector2(0, 10))
		trail_timer = 0.025
	for hazard: Rect2 in level.hazards:
		if hazard.grow(8.0).has_point(player.position):
			respawn()
			return
	if player.position.y > 748.0 or player.position.x < -60.0 or player.position.x > 1340.0:
		respawn()
		return
	if not is_sandbox and level.finish_rect.has_point(player.position):
		advance_room()

func begin_placement() -> bool:
	if mode != "playing" or placing_bomb:
		return false
	if charges <= 0 or bombs.size() >= MAX_BOMBS or plant_cooldown > 0.0:
		if plant_cooldown <= 0.0:
			notify("Приземлись, чтобы восстановить заряды." if charges <= 0 else "Сначала взорви установленные бомбы: ПКМ / F.")
			sound.play("deny")
		return false
	placing_bomb = true
	update_placement(get_global_mouse_position())
	return true

func update_placement(cursor_world: Vector2) -> void:
	if not placing_bomb:
		return
	placement_cursor_position = cursor_world
	var offset: Vector2 = (cursor_world - player.global_position).limit_length(PLACEMENT_RADIUS)
	placement_position = player.global_position + offset
	placement_position.x = clampf(placement_position.x, 10.0, 1270.0)
	placement_position.y = clampf(placement_position.y, 94.0, 644.0)
	placement_position = _resolve_placement(placement_position)
	placement_valid = _is_placeable(placement_position)
	player.arms.set_hold_target(placement_position, true)
	player.set_gaze_target(placement_position, true)
	placement_preview.queue_redraw()

func _resolve_placement(desired: Vector2) -> Vector2:
	if _is_placeable(desired):
		return desired
	var origin: Vector2 = player.global_position
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	_placement_ray.from = origin
	_placement_ray.to = desired
	var hit: Dictionary = space.intersect_ray(_placement_ray)
	if not hit.is_empty():
		var normal: Vector2 = hit["normal"]
		var surface: Vector2 = hit["position"]
		var above_surface: Vector2 = surface + normal * (BOMB_RADIUS + 0.75)
		if _is_placeable(above_surface):
			return above_surface
	# Sweep the whole bomb circle, rather than just its center, toward the
	# cursor. This also resolves corners and a cursor just above solid ground.
	_placement_query.transform = Transform2D(0.0, origin)
	_placement_query.motion = desired - origin
	var fractions: PackedFloat32Array = space.cast_motion(_placement_query)
	_placement_query.motion = Vector2.ZERO
	if not fractions.is_empty():
		var safe: Vector2 = origin.lerp(desired, fractions[0])
		safe -= (desired - origin).normalized() * 0.75
		if _is_placeable(safe):
			return safe
	# Conservative fallback along the reachable side of the obstruction.
	for step: int in range(1, 9):
		var candidate: Vector2 = desired.lerp(origin, float(step) / 8.0)
		if _is_placeable(candidate):
			return candidate
	return desired

func _is_placeable(point: Vector2) -> bool:
	if point.distance_to(player.global_position) > PLACEMENT_RADIUS + 0.1:
		return false
	_placement_query.transform = Transform2D(0.0, point)
	_placement_query.motion = Vector2.ZERO
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if not space.intersect_shape(_placement_query, 1).is_empty():
		return false
	_placement_ray.from = player.global_position
	_placement_ray.to = point
	return space.intersect_ray(_placement_ray).is_empty()

func commit_placement() -> bool:
	if not placing_bomb:
		return false
	update_placement(placement_cursor_position)
	var point: Vector2 = placement_position
	var valid: bool = placement_valid
	cancel_placement()
	if mode != "playing":
		return false
	if not valid:
		notify("Бомбу нельзя поставить внутри стены или за препятствием.")
		sound.play("deny")
		return false
	if charges <= 0 or bombs.size() >= MAX_BOMBS or plant_cooldown > 0.0:
		return false
	var bomb: Node2D = BombScript.new()
	bomb.position = point
	bomb.serial = bombs.size() + 1
	add_child(bomb)
	bombs.append(bomb)
	charges = 3 if is_sandbox else charges - 1
	plant_cooldown = 0.14
	sound.play("place")
	return true

func cancel_placement() -> void:
	placing_bomb = false
	placement_valid = false
	if is_instance_valid(player) and is_instance_valid(player.arms):
		player.arms.set_hold_target(placement_position, false)
		player.set_gaze_target(placement_position, false)
	if is_instance_valid(placement_preview):
		placement_preview.queue_redraw()

func _draw_placement() -> void:
	if not placing_bomb:
		return
	var ink: Color = Color("c5d19a") if placement_valid else Color("e18b79")
	placement_preview.draw_line(player.position, placement_position, Color(ink, 0.4), 1.0, true)
	if preview_texture != null:
		BombScript.draw_visual(placement_preview, preview_texture, placement_position, elapsed, 0.0, 0.55)
	if not placement_valid:
		placement_preview.draw_line(placement_position - Vector2(5, 5), placement_position + Vector2(5, 5), ink, 2.0)
		placement_preview.draw_line(placement_position + Vector2(5, -5), placement_position + Vector2(-5, 5), ink, 2.0)

func detonate_bombs() -> int:
	var hits: int = 0
	if mode != "playing":
		return hits
	if bombs.is_empty():
		notify("Отпусти ЛКМ, чтобы зафиксировать бомбу, затем нажми ПКМ / F.")
		return hits
	for bomb: Node2D in bombs:
		if not is_instance_valid(bomb):
			continue
		if player.blast(bomb.global_position):
			hits += 1
		effects.burst(bomb.global_position, AMBER, 42, 460.0)
		bomb.queue_free()
	bombs.clear()
	blasts += 1
	shake = 10.0 if hits > 0 else 4.0
	sound.play("blast")
	return hits

func _on_land(impact: float) -> void:
	charges = 3
	if impact > 300.0:
		effects.burst(player.position + Vector2(0, 20), Color("6e9caa"), 9, 120.0)
		shake = maxf(shake, minf(impact / 260.0, 4.0))

func respawn(count_death: bool = true) -> void:
	if count_death:
		deaths += 1
		sound.play("death")
	_clear_bombs()
	charges = 3
	plant_cooldown = 0.0
	player.reset_at(level.checkpoints[0])
	effects.burst(player.position, CYAN, 20, 180.0)
	camera.position = SCREEN_CENTER
	camera.offset = Vector2.ZERO
	camera.reset_smoothing()
	notify("Свободная комната — прыгай и экспериментируй." if is_sandbox else "Комната %d: новая попытка. R — начать её заново." % (room_index + 1))

func _save_settings() -> void:
	var save: ConfigFile = ConfigFile.new()
	save.load("user://record.cfg")
	save.set_value("settings", "audio", sound.enabled)
	save.save("user://record.cfg")

func notify(message: String) -> void:
	toast = message
	toast_time = 3.5

