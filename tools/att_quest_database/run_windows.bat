@echo off
setlocal

if "%~1"=="" (
  echo Usage: run_windows.bat C:\path\to\AllTheThings
  exit /b 2
)

set "PROJECT=%~dp0..\.."
set "ATT=%~1"
rem PowerShell can leave a quote after a relative path ending in a backslash.
set "ATT=%ATT:"=%"
if "%ATT:~-1%"=="\" set "ATT=%ATT:~0,-1%"

where py >nul 2>nul
if errorlevel 1 (
  echo Python 3 was not found. Install Python 3 and rerun this file.
  exit /b 1
)

py -3 "%~dp0build_att_quest_database.py" "%ATT%"
if errorlevel 1 exit /b %errorlevel%

echo.
echo ATT quest database generated successfully.
exit /b 0
