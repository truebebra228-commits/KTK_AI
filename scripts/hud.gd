extends Control
## A small, passive overlay. Gameplay input belongs entirely to main.gd.

const PAPER: Color = Color("ded4bd")
const MUTED: Color = Color("a69a94")
const OXIDE: Color = Color("bb8659")
const GREEN: Color = Color("b1bf86")
const BAD: Color = Color("ce8a79")
const CHALLENGE_ROOMS: int = 4
const REPLAY_PROMPT: String = "нажмите R чтоб пройти игру заново"

var game: Node2D
var font: Font

func _ready() -> void:
	font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _text(at: Vector2, value: String, size: int = 14, color: Color = PAPER) -> void:
	draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _draw() -> void:
	if game == null:
		return
	# Leave the complete room visible between the header and control strip.
	draw_rect(Rect2(0, 0, 1280, 76), Color(0.065, 0.05, 0.07, 0.93))
	draw_line(Vector2(0, 76), Vector2(1280, 76), Color("51464a"))
	var room_label: String = "ФИНАЛ · СВОБОДНАЯ ИГРА" if game.is_sandbox else "КОМНАТА %d / %d" % [game.room_index + 1, CHALLENGE_ROOMS]
	_text(Vector2(24, 31), room_label, 18, GREEN if game.is_sandbox else PAPER)
	if not game.is_sandbox:
		_text(Vector2(234, 31), game.level.zone_names[game.room_index], 17, MUTED)
	_text(Vector2(24, 58), game.level.hint, 14, MUTED)
	_text(Vector2(960, 28), "ЗАРЯДЫ", 11, MUTED)
	for index: int in range(3):
		var center: Vector2 = Vector2(1045 + index * 26, 25)
		var color: Color = OXIDE if index < game.charges else Color("42353c")
		draw_circle(center, 7.0, color)
		draw_rect(Rect2(center + Vector2(-3, -11), Vector2(6, 5)), color)
	_text(Vector2(1134, 29), "M · ЗВУК " + ("ВКЛ" if game.sound.enabled else "ВЫКЛ"), 12, MUTED)
	_text(Vector2(960, 57), "ЛКМ — ВЫБРАТЬ МЕСТО", 11, MUTED)
	if game.is_sandbox:
		var replay_width: float = font.get_string_size(REPLAY_PROMPT, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		_text(Vector2(641 - replay_width * 0.5, 123), REPLAY_PROMPT, 22, Color("181120"))
		_text(Vector2(640 - replay_width * 0.5, 122), REPLAY_PROMPT, 22, PAPER)
	# This strip is below the room's lowest playable surface (y654).
	draw_rect(Rect2(0, 654, 1280, 66), Color(0.065, 0.05, 0.07, 0.95))
	draw_line(Vector2(0, 654), Vector2(1280, 654), Color("51464a"))
	_text(Vector2(24, 679), "ЛКМ: зажми, перемести и отпусти — бомба     ПКМ / F — взрыв", 14)
	var replay_control: String = "R — игра заново" if game.is_sandbox else "R — комната заново"
	_text(Vector2(24, 704), "A/D + ПРОБЕЛ — прыжок    S — тормоз    " + replay_control + "    ESC — пауза    M — звук", 13, MUTED)
	if game.placing_bomb:
		_text(Vector2(976, 680), "ОТПУСТИ ЛКМ", 15, GREEN if game.placement_valid else BAD)
		_text(Vector2(976, 703), "установить бомбу" if game.placement_valid else "выбери свободное место", 12, MUTED)
	if game.mode == "paused":
		var label: String = "ПАУЗА · ESC — продолжить"
		var width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		_text(Vector2(641 - width * 0.5, 106), label, 20, Color("100d13"))
		_text(Vector2(640 - width * 0.5, 105), label, 20)
	if game.transition_alpha > 0.0:
		draw_rect(Rect2(0, 0, 1280, 720), Color(0.0, 0.0, 0.0, clampf(game.transition_alpha, 0.0, 1.0)))
