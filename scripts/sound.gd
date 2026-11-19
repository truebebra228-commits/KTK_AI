extends Node
## Original, self-contained synthesized effects. No external audio files required.
## Add this Node once, then call play("jump"), play("blast"), etc.

const SAMPLE_RATE: int = 22050
const VOICES: int = 8

var enabled: bool = true
var volume: float = 1.0
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_voice: int = 0


func _ready() -> void:
	for voice: int in range(VOICES):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.volume_db = -9.0 + linear_to_db(maxf(volume, 0.0001))
		add_child(player)
		_players.append(player)
	_streams["jump"] = _synthesize("jump", 0.18)
	_streams["place"] = _synthesize("place", 0.13)
	_streams["blast"] = _synthesize("blast", 0.52)
	_streams["checkpoint"] = _synthesize("checkpoint", 0.6)
	_streams["death"] = _synthesize("death", 0.4)
	_streams["win"] = _synthesize("win", 1.1)
	_streams["deny"] = _synthesize("deny", 0.16)


func play(kind: String) -> void:
	if not enabled or volume <= 0.0 or not _streams.has(kind) or _players.is_empty():
		return
	var player: AudioStreamPlayer = _players[_next_voice]
	for candidate: AudioStreamPlayer in _players:
		if not candidate.playing:
			player = candidate
			break
	_next_voice = (_next_voice + 1) % VOICES
	player.stream = _streams[kind] as AudioStreamWAV
	player.play()


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		for player: AudioStreamPlayer in _players:
			player.stop()

func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	for player: AudioStreamPlayer in _players:
		player.volume_db = -9.0 + linear_to_db(maxf(volume, 0.0001))
		if volume <= 0.0:
			player.stop()


func _synthesize(kind: String, duration: float) -> AudioStreamWAV:
	var count: int = int(duration * SAMPLE_RATE)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(count * 2)
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 17183
	var phase: float = 0.0
	var filtered_noise: float = 0.0
	for index: int in range(count):
		var time: float = float(index) / SAMPLE_RATE
		var progress: float = time / duration
		var attack: float = minf(time * 200.0, 1.0)
		var release: float = minf((duration - time) * 70.0, 1.0)
		var value: float = 0.0
		var frequency: float = 220.0
		var noise: float = random.randf_range(-1.0, 1.0)
		filtered_noise = lerpf(filtered_noise, noise, 0.16)
		match kind:
			"jump":
				frequency = lerpf(340.0, 760.0, progress)
				phase += TAU * frequency / SAMPLE_RATE
				value = (sin(phase) + 0.18 * sin(phase * 2.0)) * pow(1.0 - progress, 1.3) * 0.5
			"place":
				frequency = lerpf(540.0, 190.0, progress)
				phase += TAU * frequency / SAMPLE_RATE
				value = sin(phase) * exp(-progress * 6.0) * 0.65 + noise * exp(-progress * 30.0) * 0.3
			"blast":
				frequency = lerpf(135.0, 33.0, sqrt(progress))
				phase += TAU * frequency / SAMPLE_RATE
				value = sin(phase) * exp(-progress * 5.0) * 0.7
				value += filtered_noise * exp(-progress * 4.5) * 1.2
				value += noise * exp(-progress * 19.0) * 0.35
			"checkpoint":
				var note: int = mini(int(progress * 3.0), 2)
				frequency = [523.25, 659.25, 783.99][note]
				phase += TAU * frequency / SAMPLE_RATE
				var pulse: float = fmod(time, duration / 3.0) / (duration / 3.0)
				value = (sin(phase) + 0.15 * sin(phase * 2.0)) * sin(pulse * PI) * 0.45
			"death":
				frequency = lerpf(390.0, 75.0, progress)
				phase += TAU * frequency / SAMPLE_RATE
				value = sin(phase) * (1.0 - progress) * 0.5 + filtered_noise * (1.0 - progress) * 0.2
			"win":
				var notes: Array[float] = [523.25, 659.25, 783.99, 1046.5]
				var note: int = mini(int(progress * 5.0), 3)
				frequency = notes[note]
				phase += TAU * frequency / SAMPLE_RATE
				var local_time: float = maxf(0.0, time - float(note) * duration / 5.0)
				value = (sin(phase) + 0.25 * sin(phase * 1.5) + 0.15 * sin(phase * 2.0)) * exp(-local_time * 4.0) * 0.4
			"deny":
				phase += TAU * 145.0 / SAMPLE_RATE
				value = sin(phase) * sin(progress * PI) * 0.3
		value *= attack * release
		var sample: int = int(clampf(value, -1.0, 1.0) * 29000.0)
		bytes[index * 2] = sample & 0xff
		bytes[index * 2 + 1] = (sample >> 8) & 0xff
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream
