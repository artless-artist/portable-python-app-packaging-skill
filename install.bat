@echo off
rem Double-click entry for install.ps1.
rem
rem Why a .bat at all: the default execution policy on many Windows machines is
rem Restricted, which blocks .ps1 outright. -ExecutionPolicy Bypass below is
rem scoped to this one process, it changes nothing on the machine.
rem
rem Why chcp 65001: the prompts in install.ps1 are Chinese. Without this the
rem console stays on the OEM code page (936 on Chinese Windows, 437 on English)
rem and the text shows up as garbage. The previous code page is restored on exit.
rem
rem Keep this file ASCII-only: cmd.exe reads .bat with the OEM code page.

setlocal
for /f "tokens=2 delims=:" %%a in ('chcp') do set "OLDCP=%%a"
set "OLDCP=%OLDCP: =%"

chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"

if defined OLDCP chcp %OLDCP% >nul
endlocal
