@echo off
rem Opens the project in the Godot editor with a log file of its own, so a crash leaves Godot's
rem crash report (with the GDScript backtrace: script and line) behind. The editor writes no log
rem otherwise: Godot logs the editor only when it is started with --log-file, which keeps one file
rem and overwrites it, so each launch gets a new name (editor-<time>.log; the last 20 are kept).
rem See docs/godot/CONVENTIONS.md "When the editor crashes".
rem
rem Godot: %GODOT_EDITOR% (the Godot 4.7.2 editor executable, not the console one), else the
rem default install path. `open-editor.cmd --dry-run` prints the command instead of running it.
setlocal
set "EXE=%GODOT_EDITOR%"
if "%EXE%"=="" set "EXE=C:\Users\User\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
for %%p in ("%~dp0..\..\godot") do set "PROJECT=%%~fp"
set "LOGS=%APPDATA%\Godot\app_userdata\Slime Isa\logs"
if not exist "%EXE%" (
	echo open-editor: Godot not found at %EXE%; set GODOT_EDITOR to the Godot 4.7.2 editor executable.
	exit /b 1
)
if not exist "%LOGS%" mkdir "%LOGS%"
for /f "usebackq delims=" %%t in (`powershell -NoProfile -Command "Get-Date -Format yyyy-MM-ddTHH.mm.ss"`) do set "STAMP=%%t"
set "LOG=%LOGS%\editor-%STAMP%.log"
if /i "%~1"=="--dry-run" (
	echo "%EXE%" --path "%PROJECT%" --editor --log-file "%LOG%"
	exit /b 0
)
powershell -NoProfile -Command "Get-ChildItem -LiteralPath $env:LOGS -Filter 'editor-*.log' | Sort-Object LastWriteTime -Descending | Select-Object -Skip 19 | Remove-Item -Force"
start "" "%EXE%" --path "%PROJECT%" --editor --log-file "%LOG%"
