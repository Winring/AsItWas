@echo off
setlocal

set "HERE=%~dp0"
set "ATT=%HERE%att-source"

where git >nul 2>nul
if errorlevel 1 (
  echo Git was not found. Install Git for Windows and rerun this file.
  exit /b 1
)

if not exist "%ATT%\.git" (
  echo Downloading the latest ATT Git repository...
  git clone https://github.com/ATTWoWAddon/AllTheThings.git "%ATT%"
  if errorlevel 1 exit /b %errorlevel%
) else (
  echo Updating ATT Git repository...
  git -C "%ATT%" pull --ff-only
  if errorlevel 1 exit /b %errorlevel%
)

call "%HERE%run_windows.bat" "%ATT%"
exit /b %errorlevel%
