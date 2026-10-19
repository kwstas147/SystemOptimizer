@echo off
rem Builds SystemOptimizer.exe: src\Launcher.cs + embedded SystemOptimizer.ps1 + icon.
rem Uses csc.exe from .NET Framework 4, which ships with Windows. Run it after every change to the .ps1.
setlocal
cd /d "%~dp0"

set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" (
    echo [ERROR] csc.exe of .NET Framework 4 was not found.
    goto :fail
)

for %%F in (SystemOptimizer.ps1 SystemOptimizer.ico src\Launcher.cs) do (
    if not exist "%%F" (
        echo [ERROR] Missing file: %%F
        goto :fail
    )
)

"%CSC%" /nologo /target:winexe /platform:anycpu /optimize+ /codepage:65001 ^
    /win32icon:SystemOptimizer.ico ^
    /resource:SystemOptimizer.ps1,SystemOptimizer.ps1 ^
    /reference:System.Windows.Forms.dll ^
    /out:SystemOptimizer.exe src\Launcher.cs
if errorlevel 1 (
    echo [ERROR] The build failed.
    goto :fail
)

echo [OK] SystemOptimizer.exe was built.
if not "%~1"=="/nopause" pause
exit /b 0

:fail
if not "%~1"=="/nopause" pause
exit /b 1
