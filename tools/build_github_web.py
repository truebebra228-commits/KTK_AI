"""Build a static GitHub Pages game whose every file is below 25,000,000 bytes.

The production project and its Windows export preset are never modified.
Import/export happens in an isolated staging copy under .codex-tmp.
Requires Python 3 and the matching Godot 4.7.2 non-threaded web release template.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


PROJECT = Path(__file__).resolve().parents[1]
WORKSPACE = PROJECT.parent
TOOLS = PROJECT / "tools"
MAX_FILE_SIZE = 25_000_000


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run_godot(executable: str, *arguments: str) -> None:
    result = subprocess.run([executable, *arguments], check=False, capture_output=True)
    text = (result.stdout + result.stderr).decode("utf-8", errors="replace")
    # Keep import/export logs available without dumping their progress spam.
    print("\n".join(line for line in text.splitlines() if "ERROR" in line or "Error" in line or "Godot Engine" in line))
    if result.returncode or "SCRIPT ERROR" in text:
        raise RuntimeError(f"Godot failed ({result.returncode}):\n{text[-8000:]}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=str(WORKSPACE / ".codex-tmp/godot/Godot_v4.7.2-stable_win64_console.exe"))
    parser.add_argument("--template", type=Path, default=WORKSPACE / ".codex-tmp/godot/web_nothreads_release.zip")
    parser.add_argument("--output", type=Path, default=WORKSPACE / "artifacts/impulse/github")
    args = parser.parse_args()
    if not args.template.is_file():
        raise SystemExit(f"Missing web template: {args.template}")
    godot = shutil.which(args.godot) or str(Path(args.godot).resolve())
    cache = WORKSPACE / ".codex-tmp" / "web-build"
    cache.mkdir(parents=True, exist_ok=True)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="stage-", dir=cache) as staging:
        stage = Path(staging)
        stage_project = stage / "project"
        stage_project.mkdir()
        shutil.copy2(PROJECT / "project.godot", stage_project / "project.godot")
        for folder in ("assets", "scenes", "scripts"):
            shutil.copytree(PROJECT / folder, stage_project / folder,
                            ignore=shutil.ignore_patterns("references", "*.import", "__pycache__"))
        preset = (TOOLS / "web_export.cfg").read_text(encoding="utf-8")
        preset = preset.replace("@WEB_TEMPLATE@", args.template.resolve().as_posix())
        (stage_project / "export_presets.cfg").write_text(preset, encoding="utf-8")
        raw = stage / "raw"
        raw.mkdir()
        run_godot(godot, "--headless", "--path", str(stage_project), "--editor", "--import", "--quit")
        run_godot(godot, "--headless", "--path", str(stage_project), "--export-release", "GitHub Web", str(raw / "index.html"))
        wasm = (raw / "index.wasm").read_bytes()
        compressed = gzip.compress(wasm, compresslevel=9, mtime=0)
        if gzip.decompress(compressed) != wasm:
            raise RuntimeError("WASM gzip round-trip failed.")
        (output / "index.wasm.gz").write_bytes(compressed)
        html = (raw / "index.html").read_text(encoding="utf-8")
        marker = '<script src="index.js"></script>'
        if marker not in html:
            raise RuntimeError("The Godot HTML script tag changed; review loader insertion.")
        html = html.replace(marker, '<script src="github-gzip-loader.js"></script>\n\t' + marker, 1)
        (output / "index.html").write_text(html, encoding="utf-8")
        for source in raw.iterdir():
            if source.name not in {"index.wasm", "index.html"} and source.is_file():
                shutil.copy2(source, output / source.name)
        # A previous raw export is never allowed to survive in the upload folder.
        if (output / "index.wasm").exists():
            (output / "index.wasm").unlink()
        shutil.copy2(TOOLS / "github-gzip-loader.js", output / "github-gzip-loader.js")
        shutil.copy2(TOOLS / "github.gitignore", output / ".gitignore")
        for license_name in ("LICENSE.txt", "LICENSE-GODOT.txt"):
            shutil.copy2(PROJECT / license_name, output / license_name)
        (output / ".nojekyll").write_text("", encoding="utf-8")
        source_hashes = {
            file.relative_to(stage_project).as_posix(): sha256(file.read_bytes())
            for folder in ("scripts", "scenes", "assets")
            for file in sorted((stage_project / folder).rglob("*"))
            if file.is_file() and file.suffix != ".import"
        }
        manifest = {
            "engine": "Godot 4.7.2 / web_nothreads_release",
            "wasm_uncompressed_bytes": len(wasm),
            "wasm_gzip_bytes": len(compressed),
            "wasm_sha256": sha256(wasm),
            "wasm_gzip_sha256": sha256(compressed),
            "source_sha256": source_hashes,
            "files": {file.name: file.stat().st_size for file in sorted(output.iterdir()) if file.is_file()},
        }
        (output / "web-build.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    readme = """# ИМПУЛЬС — компактная версия для GitHub

Игра запускается в браузере. Каждый файл в этой папке меньше 25 МБ.

## Запуск на GitHub Pages

1. Загрузите содержимое этой папки в корень репозитория. Сохраните имена файлов.
2. Откройте **Settings → Pages**.
3. Выберите **Deploy from a branch**, ветку **main**, папку **/(root)** и нажмите **Save**.
4. После публикации откройте ссылку, которую покажет GitHub Pages.

Папка `project/`, если она присутствует, содержит редактируемый проект Godot.
Она не нужна для запуска браузерной версии.

## Локальный запуск

Откройте терминал в этой папке и выполните `python -m http.server 8000`.
Затем откройте `http://localhost:8000` в Chrome, Edge, Firefox или Safari.
Открытие `index.html` двойным щелчком не подходит: браузеру нужен HTTP-сервер.

## Файлы

`index.wasm.gz` — официальный движок Godot, сжатый без потери данных.
`github-gzip-loader.js` распаковывает его внутри браузера. Это работает на
обычном статическом хостинге без специальных серверных заголовков.
`index.pck` — сама игра, графика и звук. Остальные JS-файлы — штатный web runtime.

Не добавляйте сюда Windows `.exe`, `.godot/` или папки `dist/` — они не нужны
для браузерной игры. Их исключает `.gitignore`.
"""
    (output / "README.md").write_text(readme, encoding="utf-8")
    files = [file for file in output.rglob("*") if file.is_file()]
    oversized = [file for file in files if file.stat().st_size >= MAX_FILE_SIZE]
    if oversized:
        raise RuntimeError("Files exceed the GitHub upload limit: " + ", ".join(str(file) for file in oversized))
    print(json.dumps({"output": str(output), "files": len(files), "total_bytes": sum(file.stat().st_size for file in files),
                      "largest_file_bytes": max(file.stat().st_size for file in files)}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
