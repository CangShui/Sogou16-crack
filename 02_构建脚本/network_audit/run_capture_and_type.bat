@echo off
REM ============================================================================
REM  run_capture_and_type.bat - start network capture AND continuous IME typing
REM  at the same time, for N minutes. Capture is the audit; typing generates the
REM  realistic Sogou IME input throughout the capture.
REM  Usage:
REM    run_capture_and_type.bat            (default 30 min, sample 10s, word 8s)
REM    run_capture_and_type.bat 60         (60 minutes)
REM    run_capture_and_type.bat 720 15 12  (720 min, sample 15s, word 12s)
REM  Opens two windows: one capture (netstat sample), one typer.
REM  ASCII only. No BOM.
REM ============================================================================
setlocal
set MINS=%1
if "%MINS%"=="" set MINS=30
set CIV=%2
if "%CIV%"=="" set CIV=10
set TIV=%3
if "%TIV%"=="" set TIV=8

echo Starting capture (%MINS% min, sample %CIV%s) + IME typing (every %TIV%s)...
start "audit-capture" cmd /c "%~dp0run_capture.bat" %MINS% %CIV%
start "ime-typer" cmd /c "%~dp0run_typer.bat" %MINS% %TIV%

echo Both started. Let them run for %MINS% minutes, then check netout\ for results.
endlocal