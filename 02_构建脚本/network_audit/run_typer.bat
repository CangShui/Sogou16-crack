@echo off
REM ============================================================================
REM  run_typer.bat - continuous real-IME composition typing, to pair with
REM  the network_audit capture (run_capture.bat). Produces realistic IME input
REM  events so the capture reflects genuine Sogou typing traffic.
REM  Usage:
REM    run_typer.bat          (default 30 minutes, type a word every 8s)
REM    run_typer.bat 60       (type 60 minutes)
REM    run_typer.bat 720 12   (type 12 hours, a word every 12s)
REM    run_typer.bat 0        (infinite until Ctrl+C)
REM  ASCII only. No BOM.
REM ============================================================================
setlocal
set MINS=%1
if "%MINS%"=="" set MINS=30
set IVAL=%2
if "%IVAL%"=="" set IVAL=8

echo IME typing for %MINS% minutes (0=infinite), a word every %IVAL%s...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ime_typer.ps1" -Minutes %MINS% -Interval %IVAL% -LogDir "%~dp0netout"

echo.
echo Done. Typing log in %~dp0netout\
endlocal