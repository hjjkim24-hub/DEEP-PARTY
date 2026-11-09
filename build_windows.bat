@echo off
setlocal
rem ============================================================
rem  DEEP PARTY - one-click Windows build
rem  Makes build\DEEP PARTY.exe (runs without Godot installed).
rem  First run downloads Godot 4.3 + export templates (~1 GB).
rem ============================================================
cd /d "%~dp0"
set "PROJ=%CD%"
set "VER=4.3"
set "TOOLS=%PROJ%\.build_tools"
set "GODOT=%TOOLS%\Godot_v%VER%-stable_win64_console.exe"
set "TPL=%APPDATA%\Godot\export_templates\%VER%.stable"
set "BASE=https://github.com/godotengine/godot/releases/download/%VER%-stable"

if not exist "%TOOLS%" mkdir "%TOOLS%"
if not exist "%TOOLS%\.gdignore" type nul > "%TOOLS%\.gdignore"
if not exist "%PROJ%\build" mkdir "%PROJ%\build"
if not exist "%PROJ%\build\.gdignore" type nul > "%PROJ%\build\.gdignore"

if exist "%GODOT%" goto have_godot
echo [1/4] Downloading Godot %VER% ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest '%BASE%/Godot_v%VER%-stable_win64.exe.zip' -OutFile '%TOOLS%\godot.zip'; Expand-Archive -Force '%TOOLS%\godot.zip' '%TOOLS%'; Remove-Item '%TOOLS%\godot.zip'"
if not exist "%GODOT%" goto fail_godot
:have_godot
echo [1/4] Godot %VER% ready.

if exist "%TPL%\windows_release_x86_64.exe" goto have_tpl
echo [2/4] Downloading export templates (about 1 GB, one time only) ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest '%BASE%/Godot_v%VER%-stable_export_templates.tpz' -OutFile '%TOOLS%\templates.zip'; Expand-Archive -Force '%TOOLS%\templates.zip' '%TOOLS%\tpl'; New-Item -ItemType Directory -Force '%TPL%' | Out-Null; Copy-Item '%TOOLS%\tpl\templates\windows_*' '%TPL%' -Force; Copy-Item '%TOOLS%\tpl\templates\version.txt' '%TPL%' -Force; Remove-Item -Recurse -Force '%TOOLS%\tpl'; Remove-Item '%TOOLS%\templates.zip'"
if not exist "%TPL%\windows_release_x86_64.exe" goto fail_tpl
:have_tpl
echo [2/4] Export templates ready.

echo [3/4] Importing assets ...
"%GODOT%" --headless --path "%PROJ%" --import

echo [4/4] Exporting build\DEEP PARTY.exe ...
"%GODOT%" --headless --path "%PROJ%" --export-release "Windows Desktop" "build/DEEP PARTY.exe"
if not exist "%PROJ%\build\DEEP PARTY.exe" goto fail_export

echo.
echo Done!  build\DEEP PARTY.exe
explorer "%PROJ%\build"
pause
exit /b 0

:fail_godot
echo ERROR: Could not download Godot. Check your internet connection.
pause
exit /b 1
:fail_tpl
echo ERROR: Could not download export templates. Check your internet connection.
pause
exit /b 1
:fail_export
echo ERROR: Export failed. Please send the messages above.
pause
exit /b 1
