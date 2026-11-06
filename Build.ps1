param(
    [string]$Godot = 'godot',
    [string]$ReleaseTemplate = ''
)
$ErrorActionPreference = 'Stop'
$taskProject = $PSScriptRoot
$taskEditor = Get-Command $Godot -ErrorAction SilentlyContinue
if (-not $taskEditor) { throw 'Pass the Godot 4 executable path with -Godot. Install matching export templates in Godot to build Windows.' }
& $taskEditor.Source --headless --path $taskProject --editor --import --quit
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
foreach ($taskTest in @('integration.gd', 'ui_smoke.gd', 'art_smoke.gd', 'arms_smoke.gd')) {
    & $taskEditor.Source --headless --fixed-fps 120 --path $taskProject --script "res://tests/$taskTest"
    if ($LASTEXITCODE -ne 0) { throw "Check failed: $taskTest" }
}
$taskPresetPath = Join-Path $taskProject 'export_presets.cfg'
$taskPreset = [System.IO.File]::ReadAllText($taskPresetPath)
try {
    if ($ReleaseTemplate) {
        $taskTemplate = (Resolve-Path -LiteralPath $ReleaseTemplate).Path.Replace('\', '/')
        $taskUpdatedPreset = [regex]::Replace($taskPreset, 'custom_template/release="[^"]*"', ('custom_template/release="' + $taskTemplate + '"'))
        [System.IO.File]::WriteAllText($taskPresetPath, $taskUpdatedPreset)
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $taskProject 'dist') | Out-Null
    & $taskEditor.Source --headless --path $taskProject --export-release 'Windows Desktop'
    if ($LASTEXITCODE -ne 0) { throw 'Windows export failed.' }
} finally {
    [System.IO.File]::WriteAllText($taskPresetPath, $taskPreset)
}
