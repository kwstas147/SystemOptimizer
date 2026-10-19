@echo off
rem Launcher: starts the GUI (it asks for Administrator rights by itself)
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0SystemOptimizer.ps1"
