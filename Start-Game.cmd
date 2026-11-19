@echo off
cd /d "%~dp0"
if exist "dist\Bomb-the-way.exe" (
  start "" "dist\Bomb-the-way.exe"
) else (
  echo Windows build not found. Import project.godot in Godot 4 and press F6/F5.
  pause
)
