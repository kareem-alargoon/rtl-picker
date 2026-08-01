@echo off
rem Prefers the compiled app; falls back to the PowerShell version if it hasn't
rem been built yet. Build it with:  powershell -File tools\build-exe.ps1
if exist "%~dp0RTLPicker.exe" (
    start "" "%~dp0RTLPicker.exe"
) else (
    rem -STA is required for clipboard access.
    start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "%~dp0RTLPicker.ps1"
)
