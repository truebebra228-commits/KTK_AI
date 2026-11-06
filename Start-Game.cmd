@echo off
cd /d "%~dp0"
if exist "dist\Impulse.exe" (
  start "" "dist\Impulse.exe"
) else (
  echo Windows build not found. Import project.godot in Godot 4 and press F6/F5.
  pause
)
