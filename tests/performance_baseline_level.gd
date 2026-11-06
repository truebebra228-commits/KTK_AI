extends Node2D
## One self-contained room, replaced as a whole when its exit is reached.
## Gameplay (respawning, checkpoints and room changes) belongs to the main scene.

const Rooms = preload("res://scripts/rooms.gd")
const WORLD_WIDTH: float = 1280.0
const INK: Color = Color("181120")
const PANEL: Color = Color("241c2c")
const EDGE: Color = Color("514655")
const CYAN: Color = Color("9cb86e")
const AMBER: Color = Color("b18465")
const WHITE: Color = Color("ded7c8")
const MUTED: Color = Color("8d8590")
const FOG: Color = Color("aaa6b0")
const CONFETTI_COUNT: int = 140

var platforms: Array[Rect2] = []
var hazards: Array[Rect2] = []
var checkpoints: Array[Vector2] = []
var room_index: int = 0
var room_count: int = 5
var challenge_count: int = 4
var sandbox: bool = false
var room_names: Array[String] = []
var subtitle: String = ""
var hint: String = ""
var room_tint: Color = Color.WHITE
var zone_starts: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var zone_names: Array[String] = []
var finish_rect: Rect2 = Rect2(1160.0, 450.0, 100.0, 160.0)
var active_checkpoint: int = 0
var _font: Font = ThemeDB.fallback_font
var _clock: float = 0.0
var _built: bool = false
var _view: Rect2 = Rect2(0, 0, 1280, 720)
var _backdrop: Texture2D
var _grain: Texture2D
var _paused: bool = false


func _ready() -> void:
	if ResourceLoader.exists("res://assets/UI.ttf"):
		_font = load("res://assets/UI.ttf") as Font
	if ResourceLoader.exists("res://assets/ruins-background.png"):
		_backdrop = load("res://assets/ruins-background.png") as Texture2D
	_grain = _make_grain()
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	build()


func build() -> void:
	if _built:
		return
	_built = true
	var rooms: Array[Dictionary] = Rooms.definitions()
	room_count = rooms.size()
	room_index = clampi(room_index, 0, room_count - 1)
	var definition: Dictionary = rooms[room_index]
	zone_names.clear()
	for room: Dictionary in rooms:
		zone_names.append(String(room["name"]))
	room_names.assign(zone_names)
	subtitle = String(definition["subtitle"])
	hint = String(definition["hint"])
	room_tint = definition["tint"]
	sandbox = bool(definition["sandbox"])
	platforms.assign(definition["platforms"])
	hazards.assign(definition["hazards"])
	checkpoints.assign([definition["spawn"]])
	finish_rect = definition["exit"]
	for platform: Rect2 in platforms:
		_add_collider(platform)
	# The room always fits the fixed camera. These borders keep blast jumps in
	# view and are intentionally separate from the walkable-platform data.
	for border: Rect2 in [Rect2(-40, 40, 40, 740), Rect2(1280, 40, 40, 740), Rect2(0, 40, 1280, 44)]:
		_add_collider(border)
	queue_redraw()


func _add_collider(rect: Rect2) -> void:
	var body: StaticBody2D = StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = rect.get_center()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = rect.size
	var collision: CollisionShape2D = CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func _process(delta: float) -> void:
	if not _paused:
		_clock += delta
	_update_view()
	queue_redraw()


func _update_view() -> void:
	var camera: Camera2D = get_viewport().get_camera_2d()
	var size: Vector2 = get_viewport_rect().size
	if camera != null:
		size /= camera.zoom
		_view = Rect2(camera.get_screen_center_position() - size * 0.5, size)
	else:
		_view = Rect2(Vector2.ZERO, size)


func get_zone_index(_world_x: float) -> int:
	return room_index


func set_checkpoint_active(index: int) -> void:
	active_checkpoint = clampi(index, 0, checkpoints.size() - 1)
	queue_redraw()


func set_paused(value: bool) -> void:
	_paused = value
	queue_redraw()


func _draw() -> void:
	_update_view()
	_draw_lab()
	for i: int in platforms.size():
		if sandbox:
			_draw_sandbox_floor(platforms[i])
		else:
			_draw_platform(platforms[i], false)
	if sandbox:
		_draw_confetti()
		return
	for hazard: Rect2 in hazards:
		_draw_spikes(hazard)
	_draw_signs()
	_draw_route()
	for i: int in checkpoints.size():
		_draw_checkpoint(checkpoints[i], i)
	_draw_portal()


func _draw_lab() -> void:
	# The city is built in depth, not on a laboratory grid. The middle distance
	# drifts more slowly than the walkable silhouette as the camera moves.
	draw_rect(_view.grow(200), FOG)
	for band: int in 24:
		var t: float = float(band) / 23.0
		var color: Color = Color("8a8596").lerp(Color("bbb7bf"), sin(t * PI) * 0.6) * room_tint
		draw_rect(Rect2(_view.position + Vector2(0, _view.size.y * t), Vector2(_view.size.x, _view.size.y / 23.0 + 2)), color)
	_draw_painted_distance()
	if sandbox:
		# The celebration space has no foreground landmarks, vegetation, signs,
		# markers or gates. Its open playfield belongs to the player and the paper.
		draw_rect(_view.grow(50), Color(0.80, 0.79, 0.83, 0.29))
		return
	if _backdrop == null:
		_draw_skyline(0.20, Color("797382"), 270.0, 1)
		_draw_skyline(0.43, Color("686171"), 370.0, 2)
	_draw_midground()
	_draw_room_landmark()
	# A soft veil leaves the playable black masonry cleanly separated.
	draw_rect(_view.grow(50), Color(0.73, 0.71, 0.76, 0.07))
	_draw_growth_in_distance()
	_draw_birds()
	_draw_drifting_dust()


func _draw_sandbox_floor(rect: Rect2) -> void:
	draw_rect(rect, INK)
	draw_line(rect.position + Vector2(0, 1), Vector2(rect.end.x, rect.position.y + 1), Color("706775"), 2.0)
	if _grain != null:
		draw_texture_rect(_grain, rect, true, Color(1, 1, 1, 0.56))
	draw_rect(Rect2(-40, 84, 46, 526), INK)
	draw_rect(Rect2(1274, 84, 46, 526), INK)
	draw_line(Vector2(5, 84), Vector2(5, 610), Color("514655"), 1.0)
	draw_line(Vector2(1275, 84), Vector2(1275, 610), Color("514655"), 1.0)


func _draw_confetti() -> void:
	# Analytic motion keeps the celebration bounded at 140 paper pieces. The
	# same paused clock drives every piece; no timers or particles keep running.
	var colors: Array[Color] = [Color("d59a86"), Color("d9c177"), Color("acbe7d"), Color("95b3d4"), Color("c3a0c8"), Color("e4d8b5")]
	for i: int in CONFETTI_COUNT:
		var seed_value: float = float(i * 37 + 9)
		var speed: float = 24.0 + _noise(seed_value) * 43.0
		var x: float = 18.0 + _noise(seed_value + 4) * 1244.0 + sin(_clock * 0.8 + i * 1.3) * 13.0
		var y: float = 88.0 + fposmod(_clock * speed + _noise(seed_value + 11) * 518.0, 518.0)
		var rotation_angle: float = _clock * (0.6 + _noise(seed_value + 7) * 1.6) + i * 0.8
		var tumble: float = maxf(0.2, absf(sin(_clock * 2.5 + i)))
		var width: float = 3.0 + _noise(seed_value + 6) * 4.0
		draw_set_transform(Vector2(clampf(x, 12.0, 1268.0), y), rotation_angle, Vector2(1, tumble))
		draw_rect(Rect2(-width * 0.5, -2.0, width, 3.0 + _noise(seed_value + 13) * 3.0), Color(colors[i % colors.size()], 0.94))
		if i % 4 == 0:
			draw_line(Vector2(-width * 0.5, -1), Vector2(width * 0.5, -1), Color(1, 1, 1, 0.22), 1.0)
	draw_set_transform(Vector2.ZERO)


func _draw_painted_distance() -> void:
	if _backdrop == null:
		return
	var texture_size: Vector2 = _backdrop.get_size()
	var scale_factor: float = maxf(_view.size.x / texture_size.x, _view.size.y / texture_size.y) * 1.5
	var size: Vector2 = texture_size * scale_factor
	# Each room looks onto a different part of the same dead city. The camera
	# itself remains still; only a new room changes the composition and light.
	var composition: int = mini(room_index, 3)
	var scroll: float = fposmod(_view.get_center().x * 0.10 + composition * 190.0, size.x)
	var top: float = _view.position.y - (size.y - _view.size.y) * (0.24 + composition * 0.13)
	for tile: int in range(-1, 3):
		var left: float = _view.position.x - scroll + tile * size.x
		draw_texture_rect(_backdrop, Rect2(Vector2(left, top), size), false, Color(0.97, 0.95, 1.0, 0.93) * room_tint)


func _draw_skyline(parallax: float, color: Color, spacing: float, layer: int) -> void:
	var center: Vector2 = _view.get_center()
	var start: int = int(floor((center.x * parallax - _view.size.x * 0.65) / spacing)) - 1
	var finish: int = start + int(_view.size.x / spacing) + 5
	var bottom: float = center.y * (1.0 - parallax) + 970.0 * parallax
	for i: int in range(start, finish):
		var seed_value: float = float(i * 17 + layer * 239)
		var x: float = i * spacing + center.x * (1.0 - parallax)
		var width: float = 85.0 + _noise(seed_value) * 120.0
		var height: float = 150.0 + _noise(seed_value + 4.0) * 370.0
		var roof: float = bottom - height
		var outline: PackedVector2Array = PackedVector2Array([
			Vector2(x, bottom + 200), Vector2(x, roof + 24), Vector2(x + width * 0.21, roof + 24),
			Vector2(x + width * 0.21, roof + 8), Vector2(x + width * 0.52, roof + 14),
			Vector2(x + width * 0.61, roof), Vector2(x + width * 0.74, roof + 12),
			Vector2(x + width, roof + 7), Vector2(x + width, bottom + 200)
		])
		draw_colored_polygon(outline, color)
		if layer == 2:
			# Empty windows and broken floors, distant enough to stay soft.
			for row: int in range(2, int(height / 35.0)):
				for col: int in range(1, int(width / 30.0)):
					if _noise(seed_value + row * 7 + col * 3) > 0.43:
						var hole: Rect2 = Rect2(x + col * 30, roof + row * 35, 10 + _noise(row + seed_value) * 5, 17)
						draw_rect(hole, Color("948b9c"))
			# Crooked aerials stand out against the empty sky.
			draw_line(Vector2(x + width * 0.6, roof + 10), Vector2(x + width * 0.6 + 8, roof - 39), color, 3.0)
			draw_line(Vector2(x + width * 0.6 - 14, roof - 25), Vector2(x + width * 0.6 + 24, roof - 27), color, 2.0)
		else:
			draw_rect(Rect2(x + width * 0.55, roof - 30, 15, 40), color)


func _draw_midground() -> void:
	var color: Color = Color(0.32, 0.27, 0.37, 0.54)
	# Collapsed overhead transit lines. Their grey silhouette signals distance;
	# only the darker, textured concrete foreground is solid.
	for i: int in range(-1, 13):
		var seed_index: int = i + room_index * 17
		var x: float = i * 580.0 + 70.0 + room_index * 31.0
		if x > _view.end.x + 700 or x + 680 < _view.position.x - 200:
			continue
		var y: float = 94.0 + _noise(float(seed_index * 41)) * 75.0
		var width: float = 350.0 + _noise(float(seed_index * 33)) * 170.0
		# The abandoned span is a corroded skeleton, not a second solid platform.
		draw_line(Vector2(x, y + 4), Vector2(x + width - 45, y + 1), color, 5.0)
		draw_line(Vector2(x, y + 29), Vector2(x + width - 70, y + 27), color, 3.0)
		draw_polyline(PackedVector2Array([Vector2(x + width - 65, y + 1), Vector2(x + width - 20, y + 9), Vector2(x + width - 47, y + 23)]), color, 3.0, true)
		for girder: int in range(0, int(width) - 65, 52):
			draw_line(Vector2(x + girder + 2, y + 5), Vector2(x + girder + 35, y + 27), color, 2.0)
			draw_line(Vector2(x + girder + 35, y + 27), Vector2(x + girder + 51, y + 4), color, 2.0)
			draw_line(Vector2(x + girder + 6, y + 31), Vector2(x + girder + 27, y + 44), color, 2.0)
		_cable(Vector2(x + 40, y + 26), Vector2(x + width - 85, y + 50), 60.0, color, 2.0)
		_chain(Vector2(x + 74, y + 30), 150 + _noise(float(seed_index * 99)) * 140, Color(0.35, 0.30, 0.40, 0.64))
		_cable(Vector2(x + width - 40, y + 24), Vector2(x + width - 12, y + 205), 18.0, color, 2.0)
	# Suspended concrete remnants and long abandoned lift cables below the route.
	for i: int in range(0, 15):
		var x: float = i * 450.0 + 250.0
		var y: float = 750.0 + _noise(float(i * 21)) * 190.0
		if x < _view.position.x - 250 or x > _view.end.x + 250:
			continue
		draw_line(Vector2(x, y - 300), Vector2(x, y + 170), Color("5b5266"), 3.0)
		draw_rect(Rect2(x - 37, y - 18, 76, 58), Color("61576d"))
		draw_rect(Rect2(x - 28, y - 11, 58, 35), Color("746a7f"), false, 2.0)
		_chain(Vector2(x + 29, y + 41), 72, Color("5b5266"))
	# Ruined frame at the edge of the city, rather than a clean level boundary.
	for x: float in [-96.0, 6510.0]:
		draw_rect(Rect2(x - 95, -400, 104, 1480), Color("302638"))
		for row: int in range(-10, 23):
			draw_line(Vector2(x - 88, row * 48), Vector2(x + 7, row * 48 - 4), Color("463a4e"), 2.0)
			if row % 3 == 0:
				draw_rect(Rect2(x - 70, row * 48 + 11, 37, 25), INK)


func _draw_room_landmark() -> void:
	var iron: Color = Color(0.25, 0.21, 0.29, 0.35)
	var pale: Color = Color(0.51, 0.48, 0.54, 0.28)
	match room_index:
		0:
			# Courtyard: the shell of a greenhouse, with glass long gone.
			for post: int in 5:
				var x: float = 56.0 + post * 66
				draw_line(Vector2(x, 355), Vector2(x, 604), iron, 3.0)
				if post < 4:
					draw_line(Vector2(x, 356), Vector2(x + 66, 301), iron, 2.0)
					draw_line(Vector2(x + 66, 301), Vector2(x + 132, 356), iron, 2.0)
				draw_line(Vector2(x, 454), Vector2(x + 66, 454), iron, 2.0)
			_vine(Vector2(87, 604), 199.0, 167.0, Color("72835d"), true)
			_vine(Vector2(314, 604), 169.0, 321.0, Color("586c52"), true)
		1:
			# Shaft: a seized pulley, severed lift cables and a distant iron cage.
			var pulley: Vector2 = Vector2(435, 212)
			draw_arc(pulley, 46, 0.0, TAU, 40, iron, 8.0)
			draw_arc(pulley, 34, 0.0, TAU, 36, iron, 3.0)
			for spoke: int in 8:
				var axis: Vector2 = Vector2.from_angle(spoke * TAU / 8.0)
				draw_line(pulley + axis * 8, pulley + axis * 37, iron, 4.0)
			draw_circle(pulley, 10, iron)
			for x: float in [390.0, 420.0, 450.0, 480.0]:
				draw_line(Vector2(x, 169), Vector2(x + 3, 625), iron, 2.0)
			_chain(Vector2(511, 171), 402, iron)
			draw_rect(Rect2(385, 434, 110, 143), pale, false, 5.0)
			for x: int in range(401, 495, 19):
				draw_line(Vector2(x, 440), Vector2(x, 573), iron, 2.0)
		2:
			# Bridge: snapped suspension lines lead into empty space.
			for side: int in 2:
				var x: float = 92.0 if side == 0 else 1157.0
				draw_line(Vector2(x, 220), Vector2(x, 547), iron, 11.0)
				draw_line(Vector2(x - 27, 250), Vector2(x + 27, 250), iron, 4.0)
			_cable(Vector2(92, 240), Vector2(450, 418), 52.0, iron, 3.0)
			_cable(Vector2(1157, 240), Vector2(774, 422), 48.0, iron, 3.0)
			_cable(Vector2(92, 276), Vector2(359, 463), 25.0, iron, 2.0)
			_cable(Vector2(1157, 276), Vector2(936, 462), 26.0, iron, 2.0)
			for link: int in 6:
				var x: float = 142.0 + link * 47
				draw_line(Vector2(x, 277 + link * 29), Vector2(x - 8, 383 + link * 12), iron, 1.5)
			_chain(Vector2(770, 420), 153, iron)
		3:
			# Core: a dead circular reactor frame and vegetation through the breach.
			var core: Vector2 = Vector2(688, 355)
			for segment: int in 7:
				var angle: float = segment * TAU / 7.0
				draw_arc(core, 181, angle, angle + 0.63, 15, iron, 9.0)
				draw_arc(core, 200, angle + 0.03, angle + 0.65, 15, iron, 3.0)
				var axis: Vector2 = Vector2.from_angle(angle + 0.3)
				draw_line(core + axis * 169, core + axis * 212, iron, 5.0)
				for bolt: int in 3:
					var pos: Vector2 = core + Vector2.from_angle(angle + bolt * 0.19) * 190
					draw_circle(pos, 3, pale)
			draw_line(Vector2(503, 168), Vector2(503, 624), iron, 3.0)
			draw_line(Vector2(880, 158), Vector2(880, 624), iron, 3.0)
			_chain(Vector2(596, 151), 87, iron)
			_vine(Vector2(583, 627), 253.0, 882.0, Color("7d925d"), true)
			_vine(Vector2(887, 627), 215.0, 491.0, Color("597c4e"), true)


func _draw_growth_in_distance() -> void:
	for i: int in range(-1, 28):
		var x: float = 200.0 + i * 241.0 + room_index * 53.0
		if x < _view.position.x - 100 or x > _view.end.x + 100:
			continue
		var height: float = 95.0 + _noise(float((i + room_index * 5) * 13)) * 345.0
		var base: float = 895.0 + _noise(float(i * 8)) * 70.0
		_vine(Vector2(x, base), height, float(i * 29), Color("63815d"), true)
		if i % 3 == 0:
			_vine(Vector2(x + 15, base + 30), height * 0.7, float(i * 29 + 5), Color("84996d"), true)


func _draw_birds() -> void:
	for i: int in 11:
		var period: float = _view.size.x + 160.0
		var x: float = _view.position.x + fposmod(i * 167.0 - _clock * (6.0 + i % 4) - _view.get_center().x * 0.08, period) - 80.0
		var y: float = _view.position.y + 135.0 + _noise(float(i * 53)) * 230.0 + sin(_clock * 0.6 + i) * 13.0
		var flap: float = sin(_clock * 3.3 + i * 1.8) * 5.0
		var color: Color = Color("41384e")
		draw_polyline(PackedVector2Array([Vector2(x - 8, y - flap), Vector2(x - 3, y - 3), Vector2(x, y), Vector2(x + 4, y - 3), Vector2(x + 9, y - flap - 2)]), color, 2.0, true)


func _draw_drifting_dust() -> void:
	for i: int in 26:
		var x: float = _view.position.x + fposmod(i * 91.0 + _clock * (2.0 + i % 5), _view.size.x + 30.0) - 15.0
		var y: float = _view.position.y + fposmod(i * 131.0 + _clock * (4.0 + i % 3), _view.size.y + 30.0) - 15.0
		draw_line(Vector2(x, y), Vector2(x + 2, y + 1), Color(0.88, 0.85, 0.88, 0.14), 1.0)


func _draw_platform(rect: Rect2, ceiling: bool) -> void:
	if not rect.intersects(_view.grow(240)):
		return
	draw_rect(rect, INK)
	var visible_left: float = maxf(rect.position.x, _view.position.x - 60)
	var visible_right: float = minf(rect.end.x, _view.end.x + 60)
	var visible_top: float = maxf(rect.position.y + 19, _view.position.y - 40)
	var visible_bottom: float = minf(rect.end.y, _view.end.y + 80)
	# Uneven courses of dead masonry. Joints and brick widths vary, while the
	# collision edge itself remains the original, precisely horizontal surface.
	var first_row: int = maxi(0, int((visible_top - rect.position.y) / 37))
	var last_row: int = int((visible_bottom - rect.position.y) / 37) + 1
	for row: int in range(first_row, last_row):
		var y: float = rect.position.y + 20 + row * 37
		var offset: float = 41.0 if row % 2 == 0 else 0.0
		var start: int = int(floor((visible_left - rect.position.x - offset) / 91))
		var end: int = int(ceil((visible_right - rect.position.x) / 91))
		for col: int in range(start, end):
			var seed_value: float = rect.position.x * 0.17 + row * 71 + col * 37
			var x: float = maxf(rect.position.x, rect.position.x + col * 91 + offset)
			var width: float = minf(86.0 + _noise(seed_value) * 4.0, rect.end.x - x)
			if width <= 0.0:
				continue
			var brick: Rect2 = Rect2(x, y + _noise(seed_value + 4) * 3, width, 32)
			var brick_color: Color = Color("1b1223").lerp(Color("302336"), _noise(seed_value + 2) * 0.51)
			draw_rect(brick, brick_color)
			if _noise(seed_value + 12) > 0.42:
				draw_line(brick.position + Vector2(3, 0), brick.position + Vector2(width * 0.65, -1), Color("403446"), 1.0)
			if _noise(seed_value + 10) > 0.57:
				var crack_start: Vector2 = brick.position + Vector2(width * 0.32, 2)
				var crack: PackedVector2Array = PackedVector2Array([crack_start, crack_start + Vector2(3 + _noise(seed_value) * 8, 9), crack_start + Vector2(6, 15), crack_start + Vector2(5 + _noise(seed_value + 2) * 12, 21)])
				draw_polyline(crack, Color("100a17"), 1.0, true)
			if _noise(seed_value + 8) > 0.5:
				draw_rect(Rect2(x + 10, y + 13, 12 + _noise(seed_value + 7) * 30, 3), Color("17111f"))
	# Eroded slab face and its pale, broken top catch the only direct light.
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, minf(13, rect.size.y))), Color("342838"))
	draw_line(rect.position + Vector2(0, 1), Vector2(rect.end.x, rect.position.y + 1), Color("665c69"), 1.0)
	for x: int in range(int(rect.position.x) + 3, int(rect.end.x), 13):
		var seed_value: float = float(x) + rect.position.y * 0.7
		var offset: float = _noise(seed_value + 2) * 8
		var depth: float = 2.0 + _noise(seed_value) * 9.0
		draw_rect(Rect2(x + offset, rect.position.y + depth, 2 + _noise(seed_value + 4) * 8, 1 + _noise(seed_value + 5) * 5), Color("17101f"))
		if _noise(seed_value + 8) > 0.52:
			draw_line(Vector2(x, rect.position.y + 1), Vector2(x + 3 + _noise(seed_value + 10) * 8, rect.position.y + 1), Color("a3979b"), 1.0)
		if _noise(seed_value + 11) > 0.84:
			draw_rect(Rect2(x + 3, rect.position.y + 4, 3, 2), Color("687552"))
	# Large ruptures in the façade, hanging iron and root systems at the edge.
	for x: int in range(int(rect.position.x) + 58, int(rect.end.x) - 20, 159):
		if x < _view.position.x - 100 or x > _view.end.x + 100:
			continue
		var seed_value: float = x * 0.13
		var y: float = rect.position.y + 52
		if rect.size.y > 110:
			if _noise(seed_value + 33) > 0.38:
				var opening: PackedVector2Array = PackedVector2Array([Vector2(x, y + 6), Vector2(x + 12, y + 5), Vector2(x + 15, y), Vector2(x + 41, y + 2), Vector2(x + 43, y + 12), Vector2(x + 48, y + 12), Vector2(x + 46, y + 38), Vector2(x + 36, y + 43), Vector2(x + 36, y + 49), Vector2(x + 8, y + 46), Vector2(x + 9, y + 41), Vector2(x - 2, y + 37)])
				draw_colored_polygon(opening, Color("0f0917"))
				for bar: int in 3:
					draw_line(Vector2(x + 9 + bar * 13, y + 1), Vector2(x + 5 + bar * 13, y + 45), Color("392b3b"), 1.0)
			if _noise(seed_value) > 0.45:
				_vine(Vector2(x + 48, rect.position.y + 10), 95.0 + _noise(seed_value + 2) * 100.0, seed_value, Color("4d6246"), false)
		else:
			_chain(Vector2(x, rect.end.y), 45 + _noise(seed_value) * 110, Color("443746"))
			_cable(Vector2(x + 35, rect.end.y), Vector2(x + 55, rect.end.y + 90), 17.0, Color("3b2b3f"), 2.0)
	if ceiling:
		draw_line(Vector2(rect.position.x, rect.end.y - 1), rect.end - Vector2(0, 1), Color("675769"), 2.0)
		for x: int in range(int(rect.position.x) + 25, int(rect.end.x), 91):
			draw_line(Vector2(x, rect.end.y), Vector2(x - 4, rect.end.y + 13), Color("4a394c"), 2.0)
	else:
		# Flat rubble stays below ankle height; it never masquerades as spikes.
		for x: int in range(int(rect.position.x) + 15, int(rect.end.x) - 15, 61):
			var seed_value: float = x * 0.31
			if _noise(seed_value) > 0.56:
				draw_line(Vector2(x, rect.position.y - 1), Vector2(x + 8, rect.position.y - 2), Color("746873"), 2.0)
	# A few roots cling to broken vertical outer edges.
	if rect.size.y > 120:
		_vine(rect.position + Vector2(rect.size.x - 7, 14), minf(205, rect.size.y - 20), rect.position.x, Color("506f48"), false)
	# Pixel-scale soot and chipped aggregate break up the larger stone courses.
	if _grain != null:
		var grain_rect: Rect2 = rect.intersection(_view.grow(30))
		draw_texture_rect(_grain, grain_rect, true, Color(1, 1, 1, 0.75))
	_draw_wall_scars(rect)


func _draw_wall_scars(rect: Rect2) -> void:
	if rect.size.y < 120:
		return
	for x: int in range(int(rect.position.x) + 14, int(rect.end.x) - 12, 37):
		if x < _view.position.x - 50 or x > _view.end.x + 50:
			continue
		var seed_value: float = x * 0.37 + rect.position.y
		var start: float = rect.position.y + 18 + _noise(seed_value) * 30
		var length: float = minf(rect.size.y - 40, 21 + _noise(seed_value + 3) * 240)
		# Runoff and old iron leave thin irregular vertical scars, not new tiles.
		draw_rect(Rect2(x, start, 2 + _noise(seed_value + 2) * 4, length), Color(0.025, 0.013, 0.04, 0.34))
		if _noise(seed_value + 9) > 0.79:
			draw_polyline(PackedVector2Array([Vector2(x, start + 7), Vector2(x + 2, start + length * 0.5), Vector2(x - 4, start + length)]), Color("4b3542"), 1.0, true)
		for speck: int in 7:
			var sx: float = x + _noise(seed_value + speck * 7) * 25
			var sy: float = start + _noise(seed_value + speck * 11) * length
			draw_rect(Rect2(sx, sy, 1 + _noise(seed_value + speck * 3) * 2, 1), Color("766174") if speck % 3 == 0 else Color("0f0a16"))


func _make_grain() -> Texture2D:
	var image: Image = Image.create(192, 192, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 684231
	for y: int in 192:
		for x: int in 192:
			var roll: float = random.randf()
			if roll < 0.27:
				image.set_pixel(x, y, Color(0.018, 0.01, 0.028, 0.3 + random.randf() * 0.4))
			elif roll > 0.87:
				image.set_pixel(x, y, Color(0.55, 0.47, 0.57, 0.08 + random.randf() * 0.16))
	return ImageTexture.create_from_image(image)


func _draw_spikes(rect: Rect2) -> void:
	if not rect.intersects(_view.grow(90)):
		return
	var count: int = maxi(1, int(rect.size.x / 17))
	var step: float = rect.size.x / float(count)
	draw_rect(Rect2(rect.position + Vector2(0, 23), Vector2(rect.size.x, minf(rect.size.y, 14))), Color("48303b"))
	for i: int in count:
		var x: float = rect.position.x + i * step
		var seed_value: float = x * 0.4
		var lean: float = (_noise(seed_value) - 0.5) * 10.0
		var tip: Vector2 = Vector2(x + step * 0.5 + lean, rect.position.y + _noise(seed_value + 1) * 3)
		var base: Vector2 = Vector2(x + step * 0.5, rect.position.y + 29)
		# Actual hazards have sharp rusty, light-catching tips, unlike soft vines.
		draw_colored_polygon(PackedVector2Array([base - Vector2(7, 0), tip, base + Vector2(6, 0)]), Color("95685f"))
		draw_line(tip + Vector2(0, 2), base + Vector2(3, -3), Color("c89c7a"), 1.5)
		if i % 3 == 0:
			draw_line(base - Vector2(7, 12), base + Vector2(8, -17), Color("6e4b4e"), 2.0)
	# Narrow corroded warning marks remain visible even in the fog.
	for x: int in range(int(rect.position.x) + 6, int(rect.end.x), 26):
		draw_line(Vector2(x, rect.position.y + 31), Vector2(x + 9, rect.position.y + 36), AMBER.darkened(0.2), 2.0)


func _draw_signs() -> void:
	match room_index:
		0:
			_sign(Vector2(58, 248), "01", "ЗАРОСШИЙ ДВОР", ["Начни с малого.", "Дверь — на другом конце двора."])
		1:
			_sign(Vector2(42, 278), "02", "ЛИФТ НЕ РАБОТАЕТ", ["Придётся искать иной подъём.", "Взрыв под ногами — путь наверх."])
		2:
			_sign(Vector2(387, 222), "03", "МОСТА БОЛЬШЕ НЕТ", ["Оставь прошлое позади.", "Импульс унесёт на другой берег."])
		3:
			_sign(Vector2(338, 512), "04", "СЕРДЦЕ РАЗЛОМА", ["Ещё один взрыв.", "Ещё один шанс добраться."])

func _sign(origin: Vector2, number: String, title: String, lines: Array[String]) -> void:
	# Faded stencilled paint. No glowing UI panel is embedded in the ruins.
	var ink: Color = Color("4d414f")
	_text(origin + Vector2(-1, 1), number, 48, Color(0.24, 0.19, 0.27, 0.12))
	_text(origin, number, 47, Color(0.26, 0.21, 0.29, 0.33))
	_text(origin + Vector2(64, -12), title, 19, ink)
	for i: int in lines.size():
		_text(origin + Vector2(65, 14 + i * 21), lines[i], 13, Color("625667"))
	draw_line(origin + Vector2(65, 49), origin + Vector2(114, 49), Color(0.26, 0.21, 0.29, 0.35), 1.0)


func _draw_route() -> void:
	if platforms.is_empty():
		return
	var landing: Rect2 = platforms[platforms.size() - 1]
	var origin: Vector2 = Vector2(maxf(landing.position.x + 18, finish_rect.position.x - 100), landing.position.y + 29)
	var color: Color = Color("a29a8b")
	draw_line(origin, origin + Vector2(32, 0), Color(color, 0.55), 3.0)
	draw_polyline(PackedVector2Array([origin + Vector2(22, -8), origin + Vector2(33, 0), origin + Vector2(22, 8)]), Color(color, 0.55), 3.0, true)
	draw_line(origin + Vector2(5, -1), origin + Vector2(8, 1), INK, 2.0)
	if landing.size.y > 150:
		_text(landing.position + Vector2(35, 101), "%02d" % (room_index + 1), 51, Color(0.45, 0.37, 0.45, 0.16))

func _draw_checkpoint(point: Vector2, index: int) -> void:
	var ground: Vector2 = point + Vector2(0, 24)
	var active: bool = index <= active_checkpoint
	var light: Vector2 = ground + Vector2(-5, -57)
	var lamp: Color = Color("e0d2ab") if active else Color("74665f")
	draw_rect(Rect2(ground + Vector2(-21, -8), Vector2(32, 8)), Color("302532"))
	draw_line(ground + Vector2(-8, -6), light + Vector2(0, -10), Color("67544f"), 4.0)
	draw_line(ground + Vector2(-7, -34), ground + Vector2(8, -45), Color("4b3b40"), 2.0)
	if active:
		for ring: int in range(4, 0, -1):
			draw_circle(light, 8 + ring * 7, Color(lamp, 0.015 + 0.002 * sin(_clock * 3.0 + index)))
	draw_rect(Rect2(light + Vector2(-10, -7), Vector2(20, 16)), Color("2a202b"))
	draw_rect(Rect2(light + Vector2(-6, -4), Vector2(12, 9)), lamp)
	draw_line(light + Vector2(-13, -9), light + Vector2(11, -10), Color("766156"), 3.0)
	draw_line(light + Vector2(-3, -7), light + Vector2(-3, 8), Color("46363b"), 2.0)
	draw_line(light + Vector2(5, -7), light + Vector2(5, 8), Color("46363b"), 2.0)
	_text(ground + Vector2(14, -15), "%02d" % (room_index + 1), 10, Color("a69a89") if active else MUTED.darkened(0.2))


func _draw_portal() -> void:
	var center: Vector2 = finish_rect.get_center()
	var pulse: float = (sin(_clock * 1.4) + 1.0) * 0.5
	# A damaged service doorway: shelter, not a holographic gate.
	var arch: Rect2 = finish_rect.grow_individual(25, 22, 25, 0)
	draw_rect(arch, Color("302533"))
	draw_rect(Rect2(arch.position + Vector2(-6, 16), Vector2(14, arch.size.y - 16)), Color("443743"))
	draw_rect(Rect2(arch.position + Vector2(arch.size.x - 9, 5), Vector2(16, arch.size.y - 5)), Color("443743"))
	draw_rect(finish_rect, Color("17121d"))
	for band: int in range(14, 0, -1):
		var width: float = 25.0 + band * 5
		draw_rect(Rect2(center.x - width * 0.5, finish_rect.position.y + 5, width, finish_rect.size.y - 5), Color(0.83, 0.82, 0.69, 0.012 + pulse * 0.001))
	draw_rect(Rect2(center.x - 8, finish_rect.position.y + 9, 16, finish_rect.size.y - 9), Color("b4b29b"))
	draw_rect(Rect2(center.x - 3, finish_rect.position.y + 9, 6, finish_rect.size.y - 9), Color("ded9bd"))
	draw_line(Vector2(center.x - 43, finish_rect.position.y), Vector2(center.x - 43, finish_rect.end.y), Color("5e514f"), 3.0)
	draw_line(Vector2(center.x + 43, finish_rect.position.y), Vector2(center.x + 43, finish_rect.end.y), Color("5e514f"), 3.0)
	for row: int in 5:
		draw_line(arch.position + Vector2(0, 19 + row * 36), arch.position + Vector2(22, 19 + row * 36), Color("17121d"), 2.0)
		draw_line(arch.position + Vector2(arch.size.x - 22, 31 + row * 31), arch.position + Vector2(arch.size.x, 31 + row * 31), Color("17121d"), 2.0)
	_vine(arch.position + Vector2(arch.size.x - 6, 2), 111.0, 875.0, Color("6d8556"), false)
	_cable(arch.position + Vector2(5, -15), arch.position + Vector2(arch.size.x - 7, -11), 18.0, Color("372735"), 2.0)
	_text(finish_rect.position + Vector2(10, -9), "УБЕЖИЩЕ" if room_index == room_count - 1 else "ПРОХОД", 12, Color("b1a693"))
	draw_rect(Rect2(finish_rect.position + Vector2(-13, finish_rect.size.y - 3), Vector2(finish_rect.size.x + 26, 6)), Color("645951"))


func _cable(from: Vector2, to: Vector2, sag: float, color: Color, width: float = 2.0) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in 15:
		var t: float = float(i) / 14.0
		points.append(from.lerp(to, t) + Vector2(sin(t * PI * 4.0) * sag * 0.08, sin(t * PI) * sag))
	draw_polyline(points, color, width, true)


func _chain(origin: Vector2, length: float, color: Color) -> void:
	for link: int in int(length / 9.0):
		var center: Vector2 = origin + Vector2(sin(link * 0.31) * 2.0, link * 9.0)
		if link % 2 == 0:
			draw_arc(center, 4.2, 0, TAU, 8, color, 1.5)
		else:
			draw_line(center + Vector2(0, -4), center + Vector2(0, 4), color, 2.0)


func _vine(origin: Vector2, length: float, seed_value: float, color: Color, upwards: bool) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var count: int = maxi(3, int(length / 12))
	var direction: float = -1.0 if upwards else 1.0
	for step: int in count + 1:
		var t: float = float(step) / count
		var x: float = sin(t * 9.0 + seed_value) * 4.0 + sin(t * 19.0 + seed_value * 0.2) * 3.0
		points.append(origin + Vector2(x, t * length * direction))
	draw_polyline(points, color, 1.4 if upwards else 2.0, true)
	for leaf: int in range(2, count, 3):
		var point: Vector2 = points[leaf]
		var side: float = 1.0 if leaf % 2 == 0 else -1.0
		draw_line(point, point + Vector2(side * 7, -6), color, 1.0)
		draw_colored_polygon(PackedVector2Array([point + Vector2(side * 4, -3), point + Vector2(side * 10, -10), point + Vector2(side * 9, -2)]), Color(color, 0.78))


func _noise(value: float) -> float:
	# Stable across frames and platforms; artwork never flickers randomly.
	return fposmod(sin(value * 12.9898 + 78.233) * 43758.5453, 1.0)


func _text(at: Vector2, text: String, size: int, color: Color) -> void:
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)
