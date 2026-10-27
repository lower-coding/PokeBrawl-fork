@echo off
rem Starts PokeBrawl on the menu.
rem Uses the Godot 4.7 executable in the GODOT environment variable, or "godot" on PATH.
rem Extra arguments skip the menu, e.g. --p1=pikachu --p2=snorlax --diff=hard --stage=glade --lang=en
setlocal
if "%GODOT%"=="" set GODOT=godot
start "" "%GODOT%" --path "%~dp0game" -- %*
