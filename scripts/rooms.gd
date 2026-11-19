extends RefCounted
class_name RoomCatalog
## Four camera-sized challenges and a fifth, open celebration room.
## All coordinates are local to a 1280 x 720 room.

const ROOM_COUNT: int = 5
const CHALLENGE_COUNT: int = 4
const ROOM_SIZE: Vector2 = Vector2(1280, 720)
const PLAY_TOP: float = 84.0
const PLAY_BOTTOM: float = 654.0


static func definitions() -> Array[Dictionary]:
	var rooms: Array[Dictionary] = [
		{
			"name": "Заросший двор",
			"sandbox": false,
			"subtitle": "Обычный прыжок · 54 пикселя вверх",
			"hint": "Зажми A/D и нажми ПРОБЕЛ. Пройди ступени и войди в пролом справа.",
			"platforms": [
				Rect2(0, 610, 320, 44),
				Rect2(320, 556, 150, 98),
				Rect2(470, 502, 150, 152),
				Rect2(620, 556, 150, 98),
				Rect2(770, 610, 510, 44),
			],
			"hazards": [],
			"spawn": Vector2(110, 586),
			"exit": Rect2(1160, 450, 100, 160),
			"tint": Color(1.0, 0.97, 1.0, 1.0),
		},
		{
			"name": "Лифтовая шахта",
			"sandbox": false,
			"subtitle": "Вертикальный импульс · уступ 260 пикселей",
			"hint": "Зажми ЛКМ, сдвинь бомбу под героя и отпусти. Прыгни вправо, затем ПКМ или F.",
			"platforms": [Rect2(0, 610, 390, 44), Rect2(540, 350, 740, 304)],
			"hazards": [Rect2(390, 628, 150, 26)],
			"spawn": Vector2(110, 586),
			"exit": Rect2(1160, 190, 100, 160),
			"tint": Color(0.84, 0.91, 1.0, 1.0),
		},
		{
			"name": "Оборванный мост",
			"sandbox": false,
			"subtitle": "Диагональный импульс · разрыв 500 пикселей",
			"hint": "ЛКМ: оставь бомбу позади. Прыгни вправо, затем ПКМ/F, чтобы перелететь разрыв.",
			"platforms": [Rect2(0, 550, 340, 104), Rect2(840, 550, 440, 104)],
			"hazards": [Rect2(340, 628, 500, 26)],
			"spawn": Vector2(110, 526),
			"exit": Rect2(1160, 390, 100, 160),
			"tint": Color(1.0, 0.94, 0.88, 1.0),
		},
		{
			"name": "Сердце разлома",
			"sandbox": false,
			"subtitle": "Воздушная цепочка · последний перелёт",
			"hint": "В полёте зажми ЛКМ, отпусти бомбу под собой, затем ПКМ/F. S — тормоз.",
			"platforms": [Rect2(0, 610, 250, 44), Rect2(1040, 350, 240, 304)],
			"hazards": [Rect2(250, 628, 790, 26)],
			"spawn": Vector2(110, 586),
			"exit": Rect2(1160, 190, 100, 160),
			"tint": Color(0.87, 0.96, 0.83, 1.0),
		},
		{
			"name": "Тихое небо",
			"sandbox": true,
			"subtitle": "Свободная комната · ты добрался",
			"hint": "Прыгай, ставь бомбы и празднуй. Здесь можно остаться сколько угодно.",
			"platforms": [Rect2(0, 610, 1280, 44)],
			"hazards": [],
			"spawn": Vector2(640, 586),
			"exit": Rect2(),
			"tint": Color(1.0, 1.0, 0.96, 1.0),
		},
	]
	return rooms
