@echo off
setlocal
for /f "tokens=* usebackq" %%i in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%USERPROFILE%\knvm\knvm.ps1" resolve nodedir`) do set "NODE_DIR=%%i"
if not defined NODE_DIR (
    echo [knvm] Aktif node versiyonu bulunamadi. 'knvm use ^<versiyon^>' calistirin. 1>&2
    exit /b 1
)
"%NODE_DIR%\node.exe" %*
