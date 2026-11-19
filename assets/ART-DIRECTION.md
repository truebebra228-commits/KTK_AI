# Bomb the way

Окружение переоформлено по настроению референса пользователя: холодный серо-лиловый туман, разрушенная промышленная архитектура, почти чёрные руины, свисающие кабели и цепи, редкие зелёные корни. Исходные рисунки героя и бомбы предоставлены пользователем и сохранены в `references`. Изображение с примером окружения использовано только как визуальный ориентир и не включено в распространяемый проект.

Спрайты и фоновая панорама подготовлены встроенным инструментом image_gen, затем сохранены в проекте. Физика осталась прежней. Прозрачные поля при отрисовке убираются через AtlasTexture; исходные PNG не перезаписываются. Масштаб, наклон, отражение и сжатие спрайтов анимируются в Godot.

## Итоговые файлы

- `hero-cutout.png` — герой с огромной головой, чёрными глазами и бровями, зубастой улыбкой, оранжевой майкой, сине-серыми штанами и тонкими руками.
- `bomb-cutout.png` — жёлто-охристая бомба с чёрными повреждениями, светлой нижней полосой и искрящимся фитилём.
- `ruins-background.png` — туманная промышленная панорама; передний план и параллакс дополнены кодом Godot.

## Набор промптов

Hero / background-extraction: Edit target is the supplied 128x128 character drawing. Create a clean cutout with genuinely transparent background. Remove only exterior connected white background, retaining enclosed white teeth details. Keep irregular hand-drawn thick black pixelated contours, huge round tan head, angrily slanted black eyes and brows, enormous white gritted toothy grin, orange torso, blue-gray trousers, black stick arms and claw fingers. Preserve identity, expression, shape and colors. Entire character visible, centered, small transparent margin; no accessories, floor, glow or shadows.

Bomb / background-extraction: Edit target is the supplied 128x128 bomb drawing. Remove exterior white connected background and retain enclosed white highlights. Keep irregular black outline, yellow ochre round casing, scratched dark patch markings, pale bottom stripe, black-outlined cap and bent fuse with yellow-orange sparks. Preserve rough thick pixelated lines, proportions and colors. Whole bomb and sparks visible, centered with small transparent margin; no new details, glow or shadow.

Environment / stylized-concept: Wide 16:9 distant background for a side-on 2D postapocalyptic platformer. Reference image is mood guidance. Desolate fog-filled ruined industrial megacity; flattened game pixel-art painterly texture. Pale desaturated grey-lavender overcast sky; layers of concrete high-rises disappearing into grey smog, skeletal radio masts, overhead bridge remnants, abandoned factory towers, rusting pipes, sparse wires and angular architecture. Soft muted purple slate midground, distant structures lost in fog. Rare sickly green bioluminescent vines and runoff. Subtle grain and weathered organic industrial detail. Orthographic side view, no perspective ground. Buildings in lower half and outer thirds; broad foggy central negative space. No foreground playable platforms, characters, bombs, text, HUD or grid. Soft foggy borders, original architecture.
