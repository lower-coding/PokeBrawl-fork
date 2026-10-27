@echo off
rem Starts PokeBrawl with training mode already picked: R resets, T stops or frees the rival, F3 shows the hitboxes.
rem Uses the Godot 4.7 executable in the GODOT environment variable, or "godot" on PATH.
rem Extra arguments skip the menu, e.g. --p1=pikachu --p2=snorlax --diff=hard --stage=glade --lang=en
setlocal
if "%GODOT%"=="" set GODOT=godot
start "" "%GODOT%" --path "%~dp0game" -- --training %*
