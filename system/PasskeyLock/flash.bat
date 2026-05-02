@echo off
setlocal

:: -----------------------------------------------
:: Build & Flash -- PasskeyLock ESP32
:: Usage: flash.bat [COM3]
:: -----------------------------------------------

set SKETCH_DIR=%~dp0
:: Strip trailing backslash (causes "invalid path" errors in arduino-cli)
if "%SKETCH_DIR:~-1%"=="\" set SKETCH_DIR=%SKETCH_DIR:~0,-1%
set FQBN=esp32:esp32:esp32:PartitionScheme=huge_app
set BUILD_DIR=%SKETCH_DIR%\build

:: --- Locate arduino-cli ---
where arduino-cli >nul 2>&1
if %errorlevel%==0 (
    set CLI=arduino-cli
    goto :found_cli
)
if exist "%USERPROFILE%\arduino-cli.exe" (
    set CLI="%USERPROFILE%\arduino-cli.exe"
    goto :found_cli
)
if exist "%USERPROFILE%\AppData\Local\Arduino15\arduino-cli.exe" (
    set CLI="%USERPROFILE%\AppData\Local\Arduino15\arduino-cli.exe"
    goto :found_cli
)
echo ERROR: arduino-cli not found.
echo.
echo Download the Windows .zip from:
echo   https://github.com/arduino/arduino-cli/releases/latest
echo.
echo Extract arduino-cli.exe to either:
echo   %USERPROFILE%\arduino-cli.exe
echo   Or any folder on your PATH
exit /b 1
:found_cli

:: --- COM port (arg or prompt) ---
if not "%1"=="" (
    set PORT=%1
    goto :build
)

echo Detected serial ports:
wmic path win32_pnpentity get caption /value 2>nul ^
    | findstr /i "COM" ^
    | findstr /i "CP210\|CH340\|FTDI\|Silicon\|USB Serial\|USB-SERIAL\|ESP32"
echo.
set /p PORT=Enter COM port (e.g. COM3):

:build
echo.
echo FQBN : %FQBN%
echo Port : %PORT%
echo.

:: --- Compile ---
echo [1/2] Compiling...
%CLI% compile ^
    --fqbn %FQBN% ^
    --build-path "%BUILD_DIR%" ^
    "%SKETCH_DIR%"
if %errorlevel% neq 0 (
    echo.
    echo BUILD FAILED
    exit /b 1
)

:: --- Upload ---
echo.
echo [2/2] Uploading to %PORT%...
%CLI% upload ^
    --fqbn %FQBN% ^
    --port %PORT% ^
    --input-dir "%BUILD_DIR%" ^
    "%SKETCH_DIR%"
if %errorlevel% neq 0 (
    echo.
    echo UPLOAD FAILED
    exit /b 1
)

echo.
echo Done.
endlocal
