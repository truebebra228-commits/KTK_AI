extends SceneTree
## Checks imported textures and cutout masks after an art-only update.
## Run after import: Godot --headless --path . --script res://tests/art_smoke.gd

var passed: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + description)
	else:
		failures.append(description)
		print("FAIL: " + description)

func run_checks() -> void:
	check_cutout("res://assets/hero-cutout.png")
	check_cutout("res://assets/bomb-cutout.png")
	var png_count: int = 0
	for filename: String in DirAccess.get_files_at("res://assets"):
		if not filename.ends_with(".png"):
			continue
		png_count += 1
		var path: String = "res://assets/" + filename
		var texture: Texture2D = load(path) as Texture2D
		check(texture != null and texture.get_width() > 0 and texture.get_height() > 0, "imported texture loads: " + filename)
		if texture != null:
			print("  texture: %s %d x %d" % [filename, texture.get_width(), texture.get_height()])
	check(png_count >= 3, "hero, bomb and environment PNG resources are present")
	print("\nART RESULT: %d passed, %d failed" % [passed, failures.size()])
	for failure: String in failures:
		print("  FAILED: " + failure)
	quit(0 if failures.is_empty() else 1)

func check_cutout(path: String) -> void:
	var filename: String = path.get_file()
	var cutout: Texture2D = load(path) as Texture2D
	var image: Image = cutout.get_image() if cutout != null else null
	check(image != null and not image.is_empty(), "cutout image exists: " + filename)
	if image == null or image.is_empty():
		return
	check(image.get_width() >= 32 and image.get_height() >= 32, "cutout has usable dimensions: " + filename)
	var transparent: int = 0
	var opaque: int = 0
	var boundary_count: int = 0
	var transparent_boundary: int = 0
	var white_boundary: int = 0
	var width: int = image.get_width()
	var height: int = image.get_height()
	for y: int in range(height):
		for x: int in range(width):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a < 0.02:
				transparent += 1
			elif pixel.a > 0.95:
				opaque += 1
			if x == 0 or y == 0 or x == width - 1 or y == height - 1:
				boundary_count += 1
				if pixel.a < 0.02:
					transparent_boundary += 1
				if pixel.a > 0.95 and minf(pixel.r, minf(pixel.g, pixel.b)) > 0.9:
					white_boundary += 1
	var count: float = float(width * height)
	var transparency: float = float(transparent) / count
	var opacity: float = float(opaque) / count
	check(transparency > 0.05 and opacity > 0.01, "cutout has transparent background and visible foreground: " + filename)
	check(float(transparent_boundary) / float(boundary_count) > 0.98, "cutout outer border is transparent: " + filename)
	check(white_boundary == 0, "no opaque white rectangle at image border: " + filename)
	print("  mask: %s %.1f%% transparent, %.1f%% opaque" % [filename, transparency * 100.0, opacity * 100.0])
