@echo off
rem Builds the installer: first SystemOptimizer.exe (build-exe.bat), then dist\SystemOptimizer-Setup-<version>.exe.
rem Requires Inno Setup 6 (free): winget install JRSoftware.InnoSetup
setlocal
cd /d "%~dp0"

call "%~dp0build-exe.bat" /nopause
if errorlevel 1 goto :fail

set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" set "ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" (
    echo [ERROR] Inno Setup 6 was not found. Install it with: winget install JRSoftware.InnoSetup
    goto :fail
)

"%ISCC%" /Qp "installer\SystemOptimizer.iss"
if errorlevel 1 (
    echo [ERROR] The installer build failed.
    goto :fail
)

echo [OK] The installer is in the dist folder.
if not "%~1"=="/nopause" pause
exit /b 0

:fail
if not "%~1"=="/nopause" pause
exit /b 1
