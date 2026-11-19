extends Control
## Quiet gameplay HUD and a small modal menu. Gameplay input belongs to main.gd.

const PAPER: Color = Color("ded4bd")
const MUTED: Color = Color("a69a94")
const OXIDE: Color = Color("bb8659")
const GREEN: Color = Color("b1bf86")
const EDGE: Color = Color("51464a")

var game: Node2D
var font: Font
var play_button: Button
var settings_button: Button
var back_button: Button
var resume_button: Button
var pause_settings_button: Button
var main_menu_button: Button
var volume_slider: HSlider
var fullscreen_toggle: CheckButton
var _volume_value: Label
var _overlay: Control
var _pages: Dictionary = {}
var _shown_mode: String = ""


func _ready() -> void:
	font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_menu()
	refresh_menu()


func _process(_delta: float) -> void:
	if game != null and _shown_mode != game.mode:
		refresh_menu()
	queue_redraw()


func _box(fill: Color, border: Color, padding: float = 0.0) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


func _slider_box(fill: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = _box(fill, border)
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style


func _switch_icon(checked: bool) -> Texture2D:
	var fill: String = "#8d9b68" if checked else "#2b252e"
	var edge: String = "#b1bf86" if checked else "#796b74"
	var x: int = 26 if checked else 6
	var svg: String = '<svg xmlns="http://www.w3.org/2000/svg" width="44" height="24"><rect x="1" y="1" width="42" height="22" rx="3" fill="%s" stroke="%s" stroke-width="2"/><rect x="%d" y="6" width="12" height="12" fill="#ded4bd"/></svg>' % [fill, edge, x]
	var image: Image = Image.new()
	image.load_svg_from_string(svg)
	return ImageTexture.create_from_image(image)


func _label(value: String, size: int, ink: Color = PAPER) -> Label:
	var label: Label = Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", ink)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _page(name_value: String) -> VBoxContainer:
	var page: VBoxContainer = VBoxContainer.new()
	page.name = name_value
	page.add_theme_constant_override("separation", 14)
	page.visible = false
	_pages[name_value] = page
	return page


func _spacer(page: VBoxContainer, height: float) -> void:
	var space: Control = Control.new()
	space.custom_minimum_size.y = height
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(space)


func _rule(page: VBoxContainer) -> void:
	var line: ColorRect = ColorRect.new()
	line.color = Color(0.69, 0.51, 0.35, 0.5)
	line.custom_minimum_size.y = 1.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(line)


func _button(page: VBoxContainer, name_value: String, caption: String, callback: Callable, primary: bool = false) -> Button:
	var button: Button = Button.new()
	button.name = name_value
	button.text = caption
	button.custom_minimum_size = Vector2(352, 52)
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color("1b1918") if primary else PAPER)
	button.add_theme_color_override("font_hover_color", Color("1b1918") if primary else PAPER)
	button.add_theme_color_override("font_pressed_color", Color("1b1918") if primary else GREEN)
	button.add_theme_color_override("font_focus_color", Color("1b1918") if primary else PAPER)
	button.add_theme_stylebox_override("normal", _box(GREEN if primary else Color("29232a"), Color("83905f") if primary else EDGE))
	button.add_theme_stylebox_override("hover", _box(Color("c2cd9d") if primary else Color("383039"), PAPER if primary else OXIDE))
	button.add_theme_stylebox_override("pressed", _box(Color("96a56f") if primary else Color("211c23"), GREEN))
	button.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), Color("d4c5a1")))
	button.pressed.connect(callback)
	page.add_child(button)
	return button


func _build_menu() -> void:
	_overlay = Control.new()
	_overlay.name = "MenuOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.055, 0.043, 0.065, 0.76)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "MenuPanel"
	panel.custom_minimum_size.x = 420.0
	panel.add_theme_stylebox_override("panel", _box(Color(0.105, 0.083, 0.109, 0.98), EDGE, 34.0))
	center.add_child(panel)

	var main_page: VBoxContainer = _page("menu")
	panel.add_child(main_page)
	main_page.add_child(_label(str(ProjectSettings.get_setting("application/config/name")), 42))
	_spacer(main_page, 5.0)
	_rule(main_page)
	_spacer(main_page, 5.0)
	play_button = _button(main_page, "Play", "Играть", func() -> void: game.start_game(), true)
	settings_button = _button(main_page, "Settings", "Настройки", func() -> void: game.open_settings())

	var pause_page: VBoxContainer = _page("paused")
	panel.add_child(pause_page)
	pause_page.add_child(_label("ПАУЗА", 32))
	_spacer(pause_page, 4.0)
	_rule(pause_page)
	_spacer(pause_page, 4.0)
	resume_button = _button(pause_page, "Resume", "Продолжить", func() -> void: game.resume_game(), true)
	pause_settings_button = _button(pause_page, "PauseSettings", "Настройки", func() -> void: game.open_settings())
	main_menu_button = _button(pause_page, "MainMenu", "В главное меню", func() -> void: game.return_to_menu())

	var settings_page: VBoxContainer = _page("settings")
	panel.add_child(settings_page)
	settings_page.add_child(_label("НАСТРОЙКИ", 30))
	_spacer(settings_page, 4.0)
	_rule(settings_page)
	_spacer(settings_page, 2.0)
	var volume_row: HBoxContainer = HBoxContainer.new()
	settings_page.add_child(volume_row)
	var volume_caption: Label = _label("Громкость звука", 17)
	volume_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	volume_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_row.add_child(volume_caption)
	_volume_value = _label("100%", 16, GREEN)
	_volume_value.custom_minimum_size.x = 54.0
	_volume_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	volume_row.add_child(_volume_value)
	volume_slider = HSlider.new()
	volume_slider.name = "VolumeSlider"
	volume_slider.min_value = 0.0
	volume_slider.max_value = 100.0
	volume_slider.step = 1.0
	volume_slider.custom_minimum_size = Vector2(352, 28)
	volume_slider.add_theme_stylebox_override("slider", _slider_box(Color("342d36"), Color("796b74")))
	volume_slider.add_theme_stylebox_override("grabber_area", _slider_box(Color("8d9b68"), GREEN))
	volume_slider.add_theme_stylebox_override("grabber_area_highlight", _slider_box(GREEN, PAPER))
	volume_slider.value_changed.connect(_on_volume_changed)
	settings_page.add_child(volume_slider)
	fullscreen_toggle = CheckButton.new()
	fullscreen_toggle.name = "FullscreenToggle"
	fullscreen_toggle.text = "Полный экран"
	fullscreen_toggle.custom_minimum_size.y = 48.0
	fullscreen_toggle.add_theme_font_size_override("font_size", 17)
	fullscreen_toggle.add_theme_color_override("font_color", PAPER)
	fullscreen_toggle.add_theme_color_override("font_hover_color", GREEN)
	fullscreen_toggle.add_theme_icon_override("checked", _switch_icon(true))
	fullscreen_toggle.add_theme_icon_override("unchecked", _switch_icon(false))
	fullscreen_toggle.toggled.connect(func(value: bool) -> void: game.set_fullscreen(value))
	settings_page.add_child(fullscreen_toggle)
	_spacer(settings_page, 4.0)
	back_button = _button(settings_page, "Back", "Назад", func() -> void: game.close_settings())


func _on_volume_changed(value: float) -> void:
	_volume_value.text = "%d%%" % roundi(value)
	game.set_sound_volume(value / 100.0)


func _focus_visible(control: Control) -> void:
	if is_instance_valid(control) and control.is_visible_in_tree():
		control.grab_focus()


func refresh_menu() -> void:
	if not is_instance_valid(_overlay) or game == null:
		return
	var page_changed: bool = _shown_mode != game.mode
	_shown_mode = game.mode
	var show_menu: bool = _pages.has(_shown_mode)
	_overlay.visible = show_menu
	for page_name: String in _pages:
		(_pages[page_name] as Control).visible = show_menu and page_name == _shown_mode
	if _shown_mode == "settings":
		volume_slider.set_value_no_signal(game.sound.volume * 100.0)
		_volume_value.text = "%d%%" % roundi(volume_slider.value)
		fullscreen_toggle.set_pressed_no_signal(game.fullscreen)
	if page_changed:
		var focus_owner: Control = get_viewport().gui_get_focus_owner()
		if is_instance_valid(focus_owner):
			focus_owner.release_focus()
		if _shown_mode == "settings":
			call_deferred("_focus_visible", volume_slider)
		elif _shown_mode == "menu":
			call_deferred("_focus_visible", play_button)
		elif _shown_mode == "paused":
			call_deferred("_focus_visible", resume_button)
	queue_redraw()


func _draw() -> void:
	if game == null:
		return
	if game.mode == "playing":
		# Charges are the only gameplay overlay; no room names or key hints.
		draw_rect(Rect2(1158, 14, 104, 38), Color(0.065, 0.05, 0.07, 0.68))
		for index: int in range(3):
			var center: Vector2 = Vector2(1184 + index * 26, 34)
			var ink: Color = OXIDE if index < game.charges else Color("42353c")
			draw_circle(center, 6.0, ink)
			draw_rect(Rect2(center + Vector2(-2, -10), Vector2(4, 5)), ink)
	if game.transition_alpha > 0.0:
		draw_rect(Rect2(0, 0, 1280, 720), Color(0.0, 0.0, 0.0, clampf(game.transition_alpha, 0.0, 1.0)))
