extends Node2D
class_name TestLevel
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
const ART_PIXEL: float = 2.0
const ROOM_BLEED: float = 16.0
const LIP_RADIUS: float = 8.0
const MOSS_DARK: Color = Color("323d32")
const MOSS: Color = Color("52634b")
const MOSS_LIGHT: Color = Color("788160")
const DRY_STEM: Color = Color("625043")

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
var _clock: float = 0.0
var _built: bool = false
var _view: Rect2 = Rect2(Vector2.ZERO, Rooms.ROOM_SIZE)
var _backdrop: Texture2D
var _grain: Texture2D
var _paused: bool = false
var _static_art: Node2D
var _static_viewport: SubViewport
var _pen: Node2D
var _confetti_pieces: Array[PackedFloat32Array] = []
static var _shared_grain: Texture2D
const PAPER_COLORS: Array[Color] = [Color("d59a86"), Color("d9c177"), Color("acbe7d"), Color("95b3d4"), Color("c3a0c8"), Color("e4d8b5")]


func _ready() -> void:
	if ResourceLoader.exists("res://assets/ruins-background.png"):
		_backdrop = load("res://assets/ruins-background.png") as Texture2D
	if _shared_grain == null:
		_shared_grain = _make_grain()
	_grain = _shared_grain
	_pen = self
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	build()
	if sandbox:
		_prepare_confetti()
	_static_art = Node2D.new()
	_static_art.name = "CachedRoomArtwork"
	_static_art.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_static_art.position = Vector2.ONE * ROOM_BLEED
	_static_art.draw.connect(_draw_static)
	_static_viewport = SubViewport.new()
	_static_viewport.name = "RoomArtworkCache"
	_static_viewport.size = Vector2i(Rooms.ROOM_SIZE + Vector2.ONE * ROOM_BLEED * 2.0)
	_static_viewport.disable_3d = true
	_static_viewport.world_2d = World2D.new()
	_static_viewport.transparent_bg = true
	_static_viewport.gui_disable_input = true
	_static_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_static_viewport)
	_static_viewport.add_child(_static_art)
	var cached_picture: Sprite2D = Sprite2D.new()
	cached_picture.name = "CachedRoomPicture"
	cached_picture.centered = false
	cached_picture.position = Vector2.ONE * -ROOM_BLEED
	cached_picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cached_picture.z_index = -1
	cached_picture.texture = _static_viewport.get_texture()
	add_child(cached_picture)


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
		queue_redraw()


func get_zone_index(_world_x: float) -> int:
	return room_index


func set_checkpoint_active(index: int) -> void:
	active_checkpoint = clampi(index, 0, checkpoints.size() - 1)
	queue_redraw()


func set_paused(value: bool) -> void:
	_paused = value
	queue_redraw()


func _draw() -> void:
	# Only animated details rebuild their draw commands each frame.
	_pen = self
	if sandbox:
		_draw_confetti()
		return
	_draw_birds()
	_draw_drifting_dust()
	for i: int in checkpoints.size():
		_draw_checkpoint(checkpoints[i], i)


func _draw_static() -> void:
	# Godot retains these commands until this room is replaced.
	_pen = _static_art
	_draw_lab()
	for platform: Rect2 in platforms:
		if sandbox:
			_draw_sandbox_floor(platform)
		else:
			_draw_platform(platform)
	if not sandbox:
		for hazard: Rect2 in hazards:
			_draw_spikes(hazard)
		_draw_step_joins()
		for platform: Rect2 in platforms:
			_draw_edge_growth(platform)
		_draw_route()
	_pen = self


func _draw_lab() -> void:
	# Bake the city and the terrain in the same room coordinates so they move
	# together, including during camera shake.
	_pen.draw_rect(_view.grow(200), FOG)
	for band: int in 24:
		var t: float = float(band) / 23.0
		var color: Color = Color("8a8596").lerp(Color("bbb7bf"), sin(t * PI) * 0.6) * room_tint
		_pen.draw_rect(Rect2(_view.position + Vector2(0, _view.size.y * t), Vector2(_view.size.x, _view.size.y / 23.0 + 2)), color)
	_draw_painted_distance()
	if sandbox:
		# The celebration space has no foreground landmarks, vegetation, signs,
		# markers or gates. Its open playfield belongs to the player and the paper.
		_pen.draw_rect(_view.grow(50), Color(0.80, 0.79, 0.83, 0.29))
		return
	if _backdrop == null:
		_draw_skyline(0.20, Color("797382"), 270.0, 1)
		_draw_skyline(0.43, Color("686171"), 370.0, 2)
	_draw_midground()
	_draw_room_landmark()
	_draw_exit_building()
	# A soft veil leaves the playable black masonry cleanly separated.
	_pen.draw_rect(_view.grow(50), Color(0.73, 0.71, 0.76, 0.07))
	_draw_growth_in_distance()


func _draw_sandbox_floor(rect: Rect2) -> void:
	var base: Rect2 = _ground_art_rect(rect)
	_pen.draw_rect(base, INK)
	_pen.draw_line(rect.position + Vector2(0, 1), Vector2(rect.end.x, rect.position.y + 1), Color("706775"), 2.0)
	if _grain != null:
		_pen.draw_texture_rect(_grain, base, true, Color(1, 1, 1, 0.56))
	_pen.draw_rect(Rect2(-40, 84, 46, 526), INK)
	_pen.draw_rect(Rect2(1274, 84, 46, 526), INK)
	_pen.draw_line(Vector2(5, 84), Vector2(5, 610), Color("514655"), 1.0)
	_pen.draw_line(Vector2(1275, 84), Vector2(1275, 610), Color("514655"), 1.0)


func _prepare_confetti() -> void:
	# Seeds, sizes and speeds are immutable; compute them once per celebration.
	for i: int in CONFETTI_COUNT:
		var seed_value: float = float(i * 37 + 9)
		_confetti_pieces.append(PackedFloat32Array([
			18.0 + _noise(seed_value + 4) * 1244.0,
			24.0 + _noise(seed_value) * 43.0,
			_noise(seed_value + 11) * 518.0,
			0.6 + _noise(seed_value + 7) * 1.6,
			3.0 + _noise(seed_value + 6) * 4.0,
			3.0 + _noise(seed_value + 13) * 3.0]))


func _draw_confetti() -> void:
	for i: int in _confetti_pieces.size():
		var piece: PackedFloat32Array = _confetti_pieces[i]
		var x: float = piece[0] + sin(_clock * 0.8 + i * 1.3) * 13.0
		var y: float = 88.0 + fposmod(_clock * piece[1] + piece[2], 518.0)
		var rotation_angle: float = _clock * piece[3] + i * 0.8
		var tumble: float = maxf(0.2, absf(sin(_clock * 2.5 + i)))
		var width: float = piece[4]
		_pen.draw_set_transform(Vector2(clampf(x, 12.0, 1268.0), y), rotation_angle, Vector2(1, tumble))
		_pen.draw_rect(Rect2(-width * 0.5, -2.0, width, piece[5]), Color(PAPER_COLORS[i % PAPER_COLORS.size()], 0.94))
		if i % 4 == 0:
			_pen.draw_line(Vector2(-width * 0.5, -1), Vector2(width * 0.5, -1), Color(1, 1, 1, 0.22), 1.0)
	_pen.draw_set_transform(Vector2.ZERO)


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
		_pen.draw_texture_rect(_backdrop, Rect2(Vector2(left, top), size), false, Color(0.97, 0.95, 1.0, 0.93) * room_tint)


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
		_pen.draw_colored_polygon(outline, color)
		if layer == 2:
			# Empty windows and broken floors, distant enough to stay soft.
			for row: int in range(2, int(height / 35.0)):
				for col: int in range(1, int(width / 30.0)):
					if _noise(seed_value + row * 7 + col * 3) > 0.43:
						var hole: Rect2 = Rect2(x + col * 30, roof + row * 35, 10 + _noise(row + seed_value) * 5, 17)
						_pen.draw_rect(hole, Color("948b9c"))
			# Crooked aerials stand out against the empty sky.
			_pen.draw_line(Vector2(x + width * 0.6, roof + 10), Vector2(x + width * 0.6 + 8, roof - 39), color, 3.0)
			_pen.draw_line(Vector2(x + width * 0.6 - 14, roof - 25), Vector2(x + width * 0.6 + 24, roof - 27), color, 2.0)
		else:
			_pen.draw_rect(Rect2(x + width * 0.55, roof - 30, 15, 40), color)


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
		_pen.draw_line(Vector2(x, y + 4), Vector2(x + width - 45, y + 1), color, 5.0)
		_pen.draw_line(Vector2(x, y + 29), Vector2(x + width - 70, y + 27), color, 3.0)
		_pen.draw_polyline(PackedVector2Array([Vector2(x + width - 65, y + 1), Vector2(x + width - 20, y + 9), Vector2(x + width - 47, y + 23)]), color, 3.0, true)
		for girder: int in range(0, int(width) - 65, 52):
			_pen.draw_line(Vector2(x + girder + 2, y + 5), Vector2(x + girder + 35, y + 27), color, 2.0)
			_pen.draw_line(Vector2(x + girder + 35, y + 27), Vector2(x + girder + 51, y + 4), color, 2.0)
			_pen.draw_line(Vector2(x + girder + 6, y + 31), Vector2(x + girder + 27, y + 44), color, 2.0)
		_cable(Vector2(x + 40, y + 26), Vector2(x + width - 85, y + 50), 60.0, color, 2.0)
		_chain(Vector2(x + 74, y + 30), 150 + _noise(float(seed_index * 99)) * 140, Color(0.35, 0.30, 0.40, 0.64))
		_cable(Vector2(x + width - 40, y + 24), Vector2(x + width - 12, y + 205), 18.0, color, 2.0)
	# Suspended concrete remnants and long abandoned lift cables below the route.
	for i: int in range(0, 15):
		var x: float = i * 450.0 + 250.0
		var y: float = 750.0 + _noise(float(i * 21)) * 190.0
		if x < _view.position.x - 250 or x > _view.end.x + 250:
			continue
		_pen.draw_line(Vector2(x, y - 300), Vector2(x, y + 170), Color("5b5266"), 3.0)
		_pen.draw_rect(Rect2(x - 37, y - 18, 76, 58), Color("61576d"))
		_pen.draw_rect(Rect2(x - 28, y - 11, 58, 35), Color("746a7f"), false, 2.0)
		_chain(Vector2(x + 29, y + 41), 72, Color("5b5266"))
	# Ruined frame at the edge of the city, rather than a clean level boundary.
	for x: float in [-96.0, 6510.0]:
		_pen.draw_rect(Rect2(x - 95, -400, 104, 1480), Color("302638"))
		for row: int in range(-10, 23):
			_pen.draw_line(Vector2(x - 88, row * 48), Vector2(x + 7, row * 48 - 4), Color("463a4e"), 2.0)
			if row % 3 == 0:
				_pen.draw_rect(Rect2(x - 70, row * 48 + 11, 37, 25), INK)


func _draw_room_landmark() -> void:
	var iron: Color = Color(0.25, 0.21, 0.29, 0.35)
	var pale: Color = Color(0.51, 0.48, 0.54, 0.28)
	match room_index:
		0:
			# Courtyard: the shell of a greenhouse, with glass long gone.
			for post: int in 5:
				var x: float = 56.0 + post * 66
				_pen.draw_line(Vector2(x, 355), Vector2(x, 604), iron, 3.0)
				if post < 4:
					_pen.draw_line(Vector2(x, 356), Vector2(x + 66, 301), iron, 2.0)
					_pen.draw_line(Vector2(x + 66, 301), Vector2(x + 132, 356), iron, 2.0)
				_pen.draw_line(Vector2(x, 454), Vector2(x + 66, 454), iron, 2.0)
			_vine(Vector2(87, 604), 199.0, 167.0, Color("72835d"), true)
			_vine(Vector2(314, 604), 169.0, 321.0, Color("586c52"), true)
		1:
			# Shaft: a seized pulley, severed lift cables and a distant iron cage.
			var pulley: Vector2 = Vector2(435, 212)
			_pen.draw_arc(pulley, 46, 0.0, TAU, 40, iron, 8.0)
			_pen.draw_arc(pulley, 34, 0.0, TAU, 36, iron, 3.0)
			for spoke: int in 8:
				var axis: Vector2 = Vector2.from_angle(spoke * TAU / 8.0)
				_pen.draw_line(pulley + axis * 8, pulley + axis * 37, iron, 4.0)
			_pen.draw_circle(pulley, 10, iron)
			for x: float in [390.0, 420.0, 450.0, 480.0]:
				_pen.draw_line(Vector2(x, 169), Vector2(x + 3, 625), iron, 2.0)
			_chain(Vector2(511, 171), 402, iron)
			_pen.draw_rect(Rect2(385, 434, 110, 143), pale, false, 5.0)
			for x: int in range(401, 495, 19):
				_pen.draw_line(Vector2(x, 440), Vector2(x, 573), iron, 2.0)
		2:
			# Bridge: snapped suspension lines lead into empty space.
			for side: int in 2:
				var x: float = 92.0 if side == 0 else 1157.0
				_pen.draw_line(Vector2(x, 220), Vector2(x, 547), iron, 11.0)
				_pen.draw_line(Vector2(x - 27, 250), Vector2(x + 27, 250), iron, 4.0)
			_cable(Vector2(92, 240), Vector2(450, 418), 52.0, iron, 3.0)
			_cable(Vector2(1157, 240), Vector2(774, 422), 48.0, iron, 3.0)
			_cable(Vector2(92, 276), Vector2(359, 463), 25.0, iron, 2.0)
			_cable(Vector2(1157, 276), Vector2(936, 462), 26.0, iron, 2.0)
			for link: int in 6:
				var x: float = 142.0 + link * 47
				_pen.draw_line(Vector2(x, 277 + link * 29), Vector2(x - 8, 383 + link * 12), iron, 1.5)
			_chain(Vector2(770, 420), 153, iron)
		3:
			# Core: a dead circular reactor frame and vegetation through the breach.
			var core: Vector2 = Vector2(688, 355)
			for segment: int in 7:
				var angle: float = segment * TAU / 7.0
				_pen.draw_arc(core, 181, angle, angle + 0.63, 15, iron, 9.0)
				_pen.draw_arc(core, 200, angle + 0.03, angle + 0.65, 15, iron, 3.0)
				var axis: Vector2 = Vector2.from_angle(angle + 0.3)
				_pen.draw_line(core + axis * 169, core + axis * 212, iron, 5.0)
				for bolt: int in 3:
					var pos: Vector2 = core + Vector2.from_angle(angle + bolt * 0.19) * 190
					_pen.draw_circle(pos, 3, pale)
			_pen.draw_line(Vector2(503, 168), Vector2(503, 624), iron, 3.0)
			_pen.draw_line(Vector2(880, 158), Vector2(880, 624), iron, 3.0)
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
		if _behind_stone(Vector2(x, y), 10.0):
			continue
		var flap: float = sin(_clock * 3.3 + i * 1.8) * 5.0
		var color: Color = Color("41384e")
		_pen.draw_polyline(PackedVector2Array([Vector2(x - 8, y - flap), Vector2(x - 3, y - 3), Vector2(x, y), Vector2(x + 4, y - 3), Vector2(x + 9, y - flap - 2)]), color, 2.0, true)


func _draw_drifting_dust() -> void:
	for i: int in 26:
		var x: float = _view.position.x + fposmod(i * 91.0 + _clock * (2.0 + i % 5), _view.size.x + 30.0) - 15.0
		var y: float = _view.position.y + fposmod(i * 131.0 + _clock * (4.0 + i % 3), _view.size.y + 30.0) - 15.0
		if _behind_stone(Vector2(x, y), 3.0):
			continue
		_pen.draw_line(Vector2(x, y), Vector2(x + 2, y + 1), Color(0.88, 0.85, 0.88, 0.14), 1.0)

func _behind_stone(point: Vector2, margin: float) -> bool:
	for platform: Rect2 in platforms:
		if _ground_art_rect(platform).grow(margin).has_point(point):
			return true
	return false


func _ground_art_rect(platform: Rect2) -> Rect2:
	# All playable platforms are the exposed tops of building foundations.
	# Extend only the picture below the collision rectangles. The gaps between
	# X spans, and their hazards, remain separate from solid ground.
	var left: float = platform.position.x - ROOM_BLEED if platform.position.x == 0.0 else platform.position.x
	var right: float = platform.end.x + ROOM_BLEED if platform.end.x == WORLD_WIDTH else platform.end.x
	return Rect2(left, platform.position.y, right - left, Rooms.ROOM_SIZE.y + ROOM_BLEED - platform.position.y)


func _draw_platform(platform: Rect2) -> void:
	var rect: Rect2 = _ground_art_rect(platform)
	var radii: Vector2 = _lip_radii(platform)
	var cap_height: float = maxf(radii.x, radii.y)
	var wall: Rect2 = Rect2(rect.position + Vector2(0, cap_height), rect.size - Vector2(0, cap_height))
	_pen.draw_rect(wall, INK)
	var visible_left: float = maxf(rect.position.x, _view.position.x - 60)
	var visible_right: float = minf(rect.end.x, _view.end.x + 60)
	var visible_top: float = maxf(rect.position.y + 19, _view.position.y - 40)
	var visible_bottom: float = minf(rect.end.y, _view.end.y + 80)
	# Uneven courses of dead masonry. Joints and brick widths vary, while the
	# collision edge itself remains the original, precisely horizontal surface.
	var first_row: int = maxi(0, int((visible_top - rect.position.y) / 37))
	var last_row: int = ceili((visible_bottom - rect.position.y - 20.0) / 37.0)
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
			var top: float = y + _noise(seed_value + 4) * 3
			var brick: Rect2 = Rect2(x, top, width, minf(32.0, rect.end.y - top))
			if brick.size.y <= 0.0:
				continue
			var brick_color: Color = Color("1b1223").lerp(Color("302336"), _noise(seed_value + 2) * 0.51)
			_pen.draw_rect(brick, brick_color)
			if _noise(seed_value + 12) > 0.42:
				_pen.draw_line(brick.position + Vector2(3, 0), brick.position + Vector2(width * 0.65, -1), Color("403446"), 1.0)
			if _noise(seed_value + 10) > 0.57:
				var crack_start: Vector2 = brick.position + Vector2(width * 0.32, 2)
				var crack: PackedVector2Array = PackedVector2Array([crack_start, crack_start + Vector2(3 + _noise(seed_value) * 8, 9), crack_start + Vector2(6, 15), crack_start + Vector2(5 + _noise(seed_value + 2) * 12, 21)])
				_pen.draw_polyline(crack, Color("100a17"), 1.0, true)
			if _noise(seed_value + 8) > 0.5:
				var slit_width: float = minf(12.0 + _noise(seed_value + 7) * 30.0, width - 12.0)
				if slit_width > 0.0:
					_pen.draw_rect(Rect2(x + 10, y + 13, slit_width, 3), Color("17111f"))
	# Eroded slab face and its pale, broken top catch the only direct light.
	_draw_top_lip(rect, radii)
	var chip_right: float = rect.end.x - radii.y
	for x: int in range(ceili(rect.position.x + radii.x) + 3, floori(chip_right), 13):
		var seed_value: float = float(x) + rect.position.y * 0.7
		var offset: float = _noise(seed_value + 2) * 8
		var depth: float = 2.0 + _noise(seed_value) * 9.0
		var chip_width: float = minf(2 + _noise(seed_value + 4) * 8, chip_right - x - offset)
		if chip_width > 0.0:
			_pen.draw_rect(Rect2(x + offset, rect.position.y + depth, chip_width, 1 + _noise(seed_value + 5) * 5), Color("17101f"))
		if _noise(seed_value + 8) > 0.62:
			_pen.draw_rect(Rect2(x, rect.position.y, minf(4.0 + _noise(seed_value + 10) * 12.0, chip_right - x), 2.0), Color("746674"))
		if _noise(seed_value + 11) > 0.84 and x + 6 <= chip_right:
			_pen.draw_rect(Rect2(x + 3, rect.position.y + 4, 3, 2), Color("687552"))
	# Keep the broken brickwork and reinforcement within the foundation.
	for x: int in range(int(rect.position.x) + 58, int(rect.end.x) - 20, 159):
		if x < _view.position.x - 100 or x > _view.end.x + 100:
			continue
		var seed_value: float = x * 0.13
		var y: float = rect.position.y + 52
		if rect.size.y > 112.0 and x + 49.0 < rect.end.x:
			if _noise(seed_value + 33) > 0.38:
				var opening: PackedVector2Array = PackedVector2Array([Vector2(x, y + 6), Vector2(x + 12, y + 5), Vector2(x + 15, y), Vector2(x + 41, y + 2), Vector2(x + 43, y + 12), Vector2(x + 48, y + 12), Vector2(x + 46, y + 38), Vector2(x + 36, y + 43), Vector2(x + 36, y + 49), Vector2(x + 8, y + 46), Vector2(x + 9, y + 41), Vector2(x - 2, y + 37)])
				_pen.draw_colored_polygon(opening, Color("0f0917"))
				for bar: int in 3:
					_pen.draw_line(Vector2(x + 9 + bar * 13, y + 1), Vector2(x + 5 + bar * 13, y + 45), Color("392b3b"), 1.0)
			if _noise(seed_value) > 0.48:
				_vine(Vector2(x + 36, rect.position.y + 10), minf(rect.size.y - 21.0, 58.0 + _noise(seed_value + 2) * 80.0), seed_value, Color("3a4a39"), false)
	# Pixel-scale soot and chipped aggregate break up the larger stone courses.
	if _grain != null:
		_pen.draw_texture_rect(_grain, wall, true, Color(1, 1, 1, 0.65))
	_draw_wall_scars(rect)
	for band: int in range(4):
		var top: float = 654.0 + band * 16.0
		_pen.draw_rect(Rect2(rect.position.x, top, rect.size.x, rect.end.y - top), Color(0.03, 0.019, 0.044, 0.10))


func _lip_radii(platform: Rect2) -> Vector2:
	var top: float = platform.position.y + 1.0
	var left: float = platform.position.x
	var right: float = platform.end.x
	return Vector2(
		LIP_RADIUS if left > 0.0 and not _behind_stone(Vector2(left - 1, top), 0.0) else 0.0,
		LIP_RADIUS if right < WORLD_WIDTH and not _behind_stone(Vector2(right + 1, top), 0.0) else 0.0
	)


func _draw_top_lip(rect: Rect2, radii: Vector2) -> void:
	var outline: PackedVector2Array = PackedVector2Array()
	for side: int in [-1, 1]:
		var edge: float = rect.position.x if side < 0 else rect.end.x
		var radius: float = radii.x if side < 0 else radii.y
		if radius == 0.0:
			outline.append(Vector2(edge, rect.position.y))
			continue
		var center: Vector2 = Vector2(edge - side * radius, rect.position.y + radius)
		var start: float = PI if side < 0 else PI * 1.5
		for sample: int in range(7):
			outline.append(center + Vector2.from_angle(start + sample * PI / 12.0) * radius)
	var face: PackedVector2Array = outline.duplicate()
	face.append(Vector2(rect.end.x, rect.position.y + 13))
	face.append(Vector2(rect.position.x, rect.position.y + 13))
	_pen.draw_colored_polygon(face, Color("342838"))
	_pen.draw_polyline(outline, Color("514955"), 1.65, true)


func _draw_step_joins() -> void:
	# Blend the base of a step into its neighboring ledge. These narrow moss
	# bevels are only painted where the actual platform foundations touch.
	for index: int in range(platforms.size() - 1):
		var left: Rect2 = platforms[index]
		var right: Rect2 = platforms[index + 1]
		if not is_equal_approx(left.end.x, right.position.x) or is_equal_approx(left.position.y, right.position.y):
			continue
		var base_on_left: bool = left.position.y > right.position.y
		var side: float = -1.0 if base_on_left else 1.0
		var join_at: Vector2 = Vector2(left.end.x, maxf(left.position.y, right.position.y))
		var outline: PackedVector2Array = PackedVector2Array([
			join_at + Vector2(0, -12),
			join_at + Vector2(side, -8),
			join_at + Vector2(side * 3, -4),
			join_at + Vector2(side * 6, -2),
			join_at + Vector2(side * 10, -0.5),
			join_at + Vector2(side * 14, 0),
		])
		var blend: PackedVector2Array = outline.duplicate()
		blend.append(join_at + Vector2(side * 5, 5))
		blend.append(join_at + Vector2(-side * 3, 5))
		_pen.draw_colored_polygon(blend, Color("322934"))
		_pen.draw_polyline(outline, MOSS_DARK.lerp(MOSS, 0.31), 1.65, true)


func _draw_edge_growth(platform: Rect2) -> void:
	var lip: float = platform.position.y
	var left: int = int(platform.position.x)
	var right: int = int(platform.end.x)
	# Uneven moss patches sit over the worn top edge, with room between
	# clumps so the steps and the hazards remain immediately readable.
	for x: int in range(left + 2, right - 2, 6):
		var seed_value: float = x * 0.71 + lip * 0.39
		var patch: float = sin(x * 0.036 + lip * 0.071) * 0.33 + _noise(seed_value)
		if patch < 0.52:
			continue
		var spread: float = minf(right - x, 4.0 + floorf(_noise(seed_value + 9) * 5.0) * 2.0)
		var depth: float = 2.0 + floorf(_noise(seed_value + 2) * 4.0) * 2.0
		var ink: Color = MOSS_DARK.lerp(MOSS, clampf(patch - 0.25, 0.0, 0.85))
		_pen.draw_rect(Rect2(x, lip - 2.0, spread, depth), ink)
		if patch > 0.94:
			_pen.draw_rect(Rect2(x + 2.0, lip - 4.0, minf(4.0, spread - 2.0), 2.0), MOSS_LIGHT)
	for x: int in range(left + 10, right - 10, 36):
		var seed_value: float = x * 0.47 + lip + room_index * 83.0
		var root_x: float = snappedf(x + _noise(seed_value) * 16.0 - 7.0, ART_PIXEL)
		if _noise(seed_value + 3) < 0.26:
			continue
		var sheltered: bool = absf(root_x - checkpoints[0].x) < 32.0 or finish_rect.grow(16.0).has_point(Vector2(root_x, lip - 1.0))
		var max_height: float = 10.0 if sheltered else 25.0
		for stalk: int in range(2 + int(_noise(seed_value + 11) * 3.0)):
			var stem_seed: float = seed_value + stalk * 19.0
			var height: float = minf(max_height, 5.0 + pow(_noise(stem_seed + 7), 2.0) * 22.0)
			var lean: float = _noise(stem_seed + 2) * 15.0 - 7.5
			var stem_root: Vector2 = Vector2(clampf(root_x + stalk * 4.0 - 5.0, left + 2.0, right - 2.0), lip)
			var stem_color: Color = MOSS.lerp(MOSS_LIGHT, _noise(stem_seed + 2) * 0.6)
			if _noise(stem_seed + 14) > 0.81:
				stem_color = DRY_STEM
			_draw_pixel_stem(stem_root, height, lean, -1.0, stem_seed, stem_color)
		if not sheltered and _noise(seed_value + 31) > 0.72:
			_draw_spore_stalk(Vector2(root_x, lip), seed_value)
	# Rootlets trail down the exposed sides, with darker foliage catching on
	# the vertical face rather than drawing a continuous straight border.
	for side: int in [-1, 1]:
		var edge: float = left if side < 0 else right
		var outside: Vector2 = Vector2(edge + side * 3.0, lip + 7.0)
		if edge < 2.0 or edge > WORLD_WIDTH - 2.0 or _behind_stone(outside, 0.0):
			continue
		for root_index: int in range(3):
			var seed_value: float = edge * 0.41 + root_index * 39.0 + lip
			var origin: Vector2 = Vector2(edge - side * (3.0 + root_index * 5.0), lip + 2.0)
			var length: float = 16.0 + _noise(seed_value) * 34.0
			_draw_pixel_stem(origin, length, side * (4.0 + _noise(seed_value + 5) * 6.0), 1.0, seed_value, MOSS_DARK.lerp(MOSS, 0.54))


func _draw_pixel_stem(root_point: Vector2, length: float, lean: float, direction: float, seed_value: float, ink: Color) -> void:
	var steps: int = maxi(2, roundi(length / ART_PIXEL))
	var previous: Vector2 = root_point.snapped(Vector2.ONE * ART_PIXEL)
	for i: int in range(1, steps + 1):
		var fraction: float = float(i) / steps
		var bend: float = lean * fraction * fraction + sin(fraction * 3.7 + seed_value) * 3.6 * fraction
		var cell: Vector2 = (root_point + Vector2(bend, i * ART_PIXEL * direction)).snapped(Vector2.ONE * ART_PIXEL)
		var ink_cell: Color = ink if i >= 3 else MOSS_DARK
		_pen.draw_rect(Rect2(minf(previous.x, cell.x), cell.y, ART_PIXEL + absf(cell.x - previous.x), ART_PIXEL), ink_cell)
		if i >= 3 and (i + int(seed_value)) % 4 == 0:
			var leaf_side: float = -1.0 if (i + int(seed_value)) % 8 == 0 else 1.0
			var leaf: Vector2 = cell + Vector2(leaf_side * 3.0, direction * ART_PIXEL)
			_pen.draw_rect(Rect2(leaf.x - ART_PIXEL, leaf.y, ART_PIXEL * 2.0, ART_PIXEL), ink.lightened(0.10))
		previous = cell


func _draw_spore_stalk(root_point: Vector2, seed_value: float) -> void:
	# A few curling seed cases punctuate the shorter grass silhouettes.
	var side: float = -1.0 if _noise(seed_value + 13) < 0.5 else 1.0
	var height: float = snappedf(18.0 + _noise(seed_value + 19) * 12.0, ART_PIXEL)
	for i: int in range(roundi(height / ART_PIXEL)):
		var bend: float = side * snappedf(pow(i * ART_PIXEL / height, 2.0) * 6.0, ART_PIXEL)
		_pen.draw_rect(Rect2(root_point + Vector2(bend, -2.0 * i), Vector2(4.0, 2.0)), MOSS_DARK)
	var curl: Vector2 = root_point + Vector2(side * 6.0, -height)
	_pen.draw_rect(Rect2(curl + Vector2(-2.0, 0.0), Vector2(8.0, 4.0)), MOSS)
	_pen.draw_rect(Rect2(curl + Vector2(side * 4.0, 4.0), Vector2(2.0, 4.0)), DRY_STEM)
	_pen.draw_rect(Rect2(curl, Vector2(4.0, 2.0)), MOSS_LIGHT)


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
		_pen.draw_rect(Rect2(x, start, 2 + _noise(seed_value + 2) * 4, length), Color(0.025, 0.013, 0.04, 0.34))
		if _noise(seed_value + 9) > 0.79:
			_pen.draw_polyline(PackedVector2Array([Vector2(x, start + 7), Vector2(x + 2, start + length * 0.5), Vector2(x - 4, start + length)]), Color("4b3542"), 1.0, true)
		for speck: int in 7:
			var sx: float = x + _noise(seed_value + speck * 7) * 25
			var sy: float = start + _noise(seed_value + speck * 11) * length
			_pen.draw_rect(Rect2(sx, sy, 1 + _noise(seed_value + speck * 3) * 2, 1), Color("766174") if speck % 3 == 0 else Color("0f0a16"))


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
	# The hazardous gap remains open above the spikes. A recessed bed under
	# the warning strip avoids seeing the sky through its base.
	var bed: Rect2 = Rect2(rect.position + Vector2(0, 30.0), Vector2(rect.size.x, Rooms.ROOM_SIZE.y + ROOM_BLEED - rect.position.y - 30.0))
	_pen.draw_rect(bed, Color("231825"))
	if _grain != null:
		_pen.draw_texture_rect(_grain, bed, true, Color(1, 1, 1, 0.42))
	_pen.draw_rect(Rect2(rect.position + Vector2(0, 23), Vector2(rect.size.x, 14)), Color("48303b"))
	for i: int in count:
		var x: float = rect.position.x + i * step
		var seed_value: float = x * 0.4
		var lean: float = (_noise(seed_value) - 0.5) * 10.0
		var tip: Vector2 = Vector2(x + step * 0.5 + lean, rect.position.y + _noise(seed_value + 1) * 3)
		var base: Vector2 = Vector2(x + step * 0.5, rect.position.y + 29)
		# Actual hazards have sharp rusty, light-catching tips, unlike soft vines.
		_pen.draw_colored_polygon(PackedVector2Array([base - Vector2(7, 0), tip, base + Vector2(6, 0)]), Color("95685f"))
		_pen.draw_line(tip + Vector2(0, 2), base + Vector2(3, -3), Color("c89c7a"), 1.5)
		if i % 3 == 0:
			_pen.draw_line(base - Vector2(7, 12), base + Vector2(8, -17), Color("6e4b4e"), 2.0)
	# Narrow corroded warning marks remain visible even in the fog.
	for x: int in range(int(rect.position.x) + 6, int(rect.end.x), 26):
		_pen.draw_line(Vector2(x, rect.position.y + 31), Vector2(x + 9, rect.position.y + 36), AMBER.darkened(0.2), 2.0)


func _draw_route() -> void:
	if platforms.is_empty():
		return
	var landing: Rect2 = platforms[platforms.size() - 1]
	var origin: Vector2 = Vector2(maxf(landing.position.x + 18, finish_rect.position.x - 100), landing.position.y + 29)
	var color: Color = Color("a29a8b")
	_pen.draw_line(origin, origin + Vector2(32, 0), Color(color, 0.55), 3.0)
	_pen.draw_polyline(PackedVector2Array([origin + Vector2(22, -8), origin + Vector2(33, 0), origin + Vector2(22, 8)]), Color(color, 0.55), 3.0, true)
	_pen.draw_line(origin + Vector2(5, -1), origin + Vector2(8, 1), INK, 2.0)

func _draw_checkpoint(point: Vector2, index: int) -> void:
	var ground: Vector2 = point + Vector2(0, 24)
	var active: bool = index <= active_checkpoint
	var light: Vector2 = ground + Vector2(-5, -57)
	var lamp: Color = Color("e0d2ab") if active else Color("74665f")
	_pen.draw_rect(Rect2(ground + Vector2(-21, -8), Vector2(32, 8)), Color("302532"))
	_pen.draw_line(ground + Vector2(-8, -6), light + Vector2(0, -10), Color("67544f"), 4.0)
	_pen.draw_line(ground + Vector2(-7, -34), ground + Vector2(8, -45), Color("4b3b40"), 2.0)
	if active:
		for ring: int in range(4, 0, -1):
			_pen.draw_circle(light, 8 + ring * 7, Color(lamp, 0.015 + 0.002 * sin(_clock * 3.0 + index)))
	_pen.draw_rect(Rect2(light + Vector2(-10, -7), Vector2(20, 16)), Color("2a202b"))
	_pen.draw_rect(Rect2(light + Vector2(-6, -4), Vector2(12, 9)), lamp)
	_pen.draw_line(light + Vector2(-13, -9), light + Vector2(11, -10), Color("766156"), 3.0)
	_pen.draw_line(light + Vector2(-3, -7), light + Vector2(-3, 8), Color("46363b"), 2.0)
	_pen.draw_line(light + Vector2(5, -7), light + Vector2(5, 8), Color("46363b"), 2.0)


func _draw_exit_building() -> void:
	var base: Vector2 = Vector2(finish_rect.get_center().x, finish_rect.end.y)
	var landing: Rect2 = platforms.back()
	var left: float = maxf(landing.position.x + 18.0, base.x - 196.0 + room_index * 7.0)
	var right: float = WORLD_WIDTH + ROOM_BLEED + 8.0
	var heights: Array[float] = [307.0, 275.0, 296.0, 318.0]
	var roof: float = base.y - heights[mini(room_index, heights.size() - 1)]
	var floor_y: float = base.y + 10.0
	var front: float = left + 26.0
	var wall: Color = Color("574d5d") * room_tint
	var mortar: Color = Color("443949") * room_tint
	var rim: Color = Color("746773") * room_tint

	# The side wall recedes into the fog. The taller face continues beyond
	# the screen, while the platform masks the bottom of the building.
	_pen.draw_colored_polygon(PackedVector2Array([
		Vector2(left, roof + 56), Vector2(front, roof + 18),
		Vector2(front + 7, floor_y), Vector2(left - 8, floor_y),
	]), Color("6b6071") * room_tint)
	_pen.draw_colored_polygon(PackedVector2Array([
		Vector2(front, roof + 18), Vector2(front + 34, roof + 18),
		Vector2(front + 42, roof + 6), Vector2(front + 77, roof + 6),
		Vector2(front + 88, roof + 27), Vector2(front + 111, roof + 27),
		Vector2(front + 126, roof), Vector2(right, roof + 4),
		Vector2(right, floor_y), Vector2(front + 7, floor_y),
	]), wall)
	_pen.draw_line(Vector2(front + 7, roof + 29), Vector2(front + 13, base.y), rim, 3.0)
	_pen.draw_line(Vector2(left + 5, roof + 70), Vector2(left - 2, base.y - 8), Color(mortar, 0.4), 3.0)
	_pen.draw_polyline(PackedVector2Array([
		Vector2(front + 38, roof + 17), Vector2(front + 44, roof + 4),
		Vector2(front + 45, roof - 10), Vector2(front + 54, roof - 17),
	]), mortar, 2.0)

	# Rows of broken window recesses and concrete floor bands give the
	# façade a larger scale than the passage at its base.
	for row: int in range(5):
		var y: float = roof + 58.0 + row * 49.0
		if y + 31.0 >= base.y:
			break
		_pen.draw_line(Vector2(front + 8, y + 25), Vector2(right, y + 25), mortar, 4.0)
		_pen.draw_line(Vector2(front + 8, y + 28), Vector2(right, y + 28), Color(rim, 0.45), 1.0)
		for column: int in range(4):
			var x: float = front + 24.0 + column * 51.0
			var seed_value: float = room_index * 83.0 + row * 35.0 + column * 23.0
			if _noise(seed_value + 2.0) < 0.26:
				continue
			var window_ink: Color = Color("39323f").lerp(wall, _noise(seed_value) * 0.34)
			_pen.draw_rect(Rect2(x, y - 4, 32, 23), mortar)
			_pen.draw_rect(Rect2(x + 2, y - 3, 28, 18), window_ink)
			_pen.draw_rect(Rect2(x + 12, y - 4, 3, 20), rim)
			if _noise(seed_value + 9.0) > 0.48:
				_pen.draw_colored_polygon(PackedVector2Array([
					Vector2(x + 22, y - 3), Vector2(x + 30, y - 3),
					Vector2(x + 30, y + 13), Vector2(x + 26, y + 4),
				]), Color(rim, 0.55))
	for i: int in range(21):
		var seed_value: float = room_index * 131.0 + i * 63.0
		var x: float = front + 17.0 + _noise(seed_value) * (right - front - 20.0)
		var y: float = roof + 48.0 + _noise(seed_value + 6.0) * (base.y - roof - 60.0)
		_pen.draw_rect(Rect2(x, y, 1.0 + _noise(seed_value + 15.0) * 4.0, 5.0 + _noise(seed_value + 27.0) * 34.0), Color(mortar, 0.28))

	_vine(Vector2(front + 13, roof + 38), 102.0, 652.0 + room_index * 70.0, Color("5c6558"), false)
	_vine(Vector2(front + 29, base.y - 71), 78.0, 399.0 + room_index * 71.0, Color("5f6b57"), false)
	_draw_wall_breach(base, mortar, rim)


func _draw_wall_breach(base: Vector2, mortar: Color, rim: Color) -> void:
	# Descending edges share a sharp tip then split and widen into the
	# walkable opening. The lower lip meets the room's existing exit.
	var tip: Vector2 = base + Vector2(7.0 + room_index * 1.5, -220.0)
	var left_edge: PackedVector2Array = PackedVector2Array([
		tip, base + Vector2(-3, -192), base + Vector2(4, -161),
		base + Vector2(-17, -133), base + Vector2(-12, -112),
		base + Vector2(-30, -91), base + Vector2(-25, -72),
		base + Vector2(-43, -46), base + Vector2(-38, -25),
		base + Vector2(-56, -3), base + Vector2(-53, 8),
	])
	var right_edge: PackedVector2Array = PackedVector2Array([
		tip, base + Vector2(1, -188), base + Vector2(13, -157),
		base + Vector2(-1, -129), base + Vector2(11, -109),
		base + Vector2(3, -94), base + Vector2(27, -66),
		base + Vector2(19, -50), base + Vector2(36, -36),
		base + Vector2(30, -20), base + Vector2(46, 8),
	])
	var fracture: PackedVector2Array = left_edge.duplicate()
	for i: int in range(right_edge.size() - 1, 0, -1):
		fracture.append(right_edge[i])
	_pen.draw_colored_polygon(fracture, Color("2c2432"))
	_pen.draw_polyline(left_edge, mortar, 4.0)
	_pen.draw_polyline(right_edge, rim, 2.0)

	# The inner wall casts a shadow on one side. An uneven wedge of warmer
	# fog is visible deeper through the split at floor height.
	_pen.draw_colored_polygon(PackedVector2Array([
		base + Vector2(0, -128), base + Vector2(8, -107),
		base + Vector2(3, -93), base + Vector2(23, -67),
		base + Vector2(17, -48), base + Vector2(31, -35),
		base + Vector2(26, -17), base + Vector2(40, 8),
		base + Vector2(-48, 8), base + Vector2(-35, -18),
		base + Vector2(-28, -38), base + Vector2(-19, -49),
		base + Vector2(-22, -71), base + Vector2(-11, -86),
		base + Vector2(-10, -109),
	]), Color("615761"))
	var haze: PackedVector2Array = PackedVector2Array([
		base + Vector2(-3, -103), base + Vector2(3, -83),
		base + Vector2(16, -62), base + Vector2(10, -47),
		base + Vector2(25, -28), base + Vector2(23, -17),
		base + Vector2(35, 8), base + Vector2(-42, 8),
		base + Vector2(-30, -13), base + Vector2(-24, -32),
		base + Vector2(-12, -52), base + Vector2(-16, -72),
	])
	var haze_colors: PackedColorArray = PackedColorArray()
	for point: Vector2 in haze:
		var light: float = clampf((point.y - base.y + 103.0) / 111.0, 0.0, 1.0)
		haze_colors.append(Color("655b64").lerp(Color("c0b49e"), light))
	_pen.draw_polygon(haze, haze_colors)

	_pen.draw_polyline(PackedVector2Array([
		left_edge[3], base + Vector2(-34, -142), base + Vector2(-48, -166),
		base + Vector2(-69, -166), base + Vector2(-91, -184),
	]), mortar.darkened(0.3), 2.0)
	_pen.draw_polyline(PackedVector2Array([
		left_edge[5], base + Vector2(-53, -84), base + Vector2(-74, -98),
		base + Vector2(-98, -93), base + Vector2(-108, -108),
	]), mortar.darkened(0.32), 2.0)
	_pen.draw_polyline(PackedVector2Array([
		right_edge[4], base + Vector2(28, -120), base + Vector2(40, -146),
		base + Vector2(61, -154), base + Vector2(82, -177),
	]), mortar.darkened(0.24), 2.0)
	for i: int in range(13):
		var seed_value: float = i * 79.0 + room_index * 39.0
		var side: float = -1.0 if i % 3 != 0 else 1.0
		var x: float = side * (44.0 + _noise(seed_value) * 31.0)
		var height: float = 3.0 + _noise(seed_value + 12.0) * 13.0
		var width: float = 6.0 + _noise(seed_value + 18.0) * 14.0
		var foot: Vector2 = base + Vector2(x, 2)
		_pen.draw_colored_polygon(PackedVector2Array([
			foot - Vector2(width * 0.58, 0), foot + Vector2(-width * 0.21, -height * 0.7),
			foot + Vector2(width * 0.14, -height), foot + Vector2(width * 0.56, -1),
			foot + Vector2(width * 0.62, 4),
		]), mortar.lerp(rim, _noise(seed_value + 30.0) * 0.58))


func _cable(from: Vector2, to: Vector2, sag: float, color: Color, width: float = 2.0) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in 15:
		var t: float = float(i) / 14.0
		points.append(from.lerp(to, t) + Vector2(sin(t * PI * 4.0) * sag * 0.08, sin(t * PI) * sag))
	_pen.draw_polyline(points, color, width, true)


func _chain(origin: Vector2, length: float, color: Color) -> void:
	for link: int in int(length / 9.0):
		var center: Vector2 = origin + Vector2(sin(link * 0.31) * 2.0, link * 9.0)
		if link % 2 == 0:
			_pen.draw_arc(center, 4.2, 0, TAU, 8, color, 1.5)
		else:
			_pen.draw_line(center + Vector2(0, -4), center + Vector2(0, 4), color, 2.0)


func _vine(origin: Vector2, length: float, seed_value: float, color: Color, upwards: bool) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var count: int = maxi(3, int(length / 12))
	var direction: float = -1.0 if upwards else 1.0
	for step: int in count + 1:
		var t: float = float(step) / count
		var x: float = sin(t * 9.0 + seed_value) * 4.0 + sin(t * 19.0 + seed_value * 0.2) * 3.0
		points.append(origin + Vector2(x, t * length * direction))
	_pen.draw_polyline(points, color, 1.4 if upwards else 2.0, true)
	for leaf: int in range(2, count, 3):
		var point: Vector2 = points[leaf]
		var side: float = 1.0 if leaf % 2 == 0 else -1.0
		_pen.draw_line(point, point + Vector2(side * 7, -6), color, 1.0)
		_pen.draw_colored_polygon(PackedVector2Array([point + Vector2(side * 4, -3), point + Vector2(side * 10, -10), point + Vector2(side * 9, -2)]), Color(color, 0.78))


func _noise(value: float) -> float:
	# Stable across frames and platforms; artwork never flickers randomly.
	return fposmod(sin(value * 12.9898 + 78.233) * 43758.5453, 1.0)


