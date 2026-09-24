@echo off
if defined USER_PATH_FIRST goto :eof
set USER_PATH_FIRST=1
for /f "tokens=2,*" %%a in ('reg query HKCU\Environment /v Path 2^>nul ^| find "Path"') do set "UPATH=%%b"
if defined UPATH call set "PATH=%UPATH%;%PATH%"
set UPATH=