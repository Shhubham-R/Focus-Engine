@echo off
setlocal enabledelayedexpansion

set HOSTS=%windir%\System32\drivers\etc\hosts
set MARK=#SITEBLOCKER
set TASKDIR=%~dp0
set UNBLOCK_BAT=%TASKDIR%unblock_sites.bat
set TIMEFILE=%TASKDIR%unblock_time.txt

:: ----- Must run as admin -----
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo This script must be run as Administrator.
    echo Right-click and select "Run as administrator".
    pause
    exit /b 1
)

echo ============================
echo   Website Blocker
echo ============================
echo Suggested domains: youtube.com, facebook.com, instagram.com, twitter.com, reddit.com, netflix.com
echo.

set /p HOURS=Enter number of hours to block: 
set /p DOMAINS=Enter domains to block (comma separated, e.g. youtube.com,facebook.com): 

:: Get unblock date and time as separate values
for /f "tokens=1,2" %%A in ('powershell -NoProfile -Command "$t=(Get-Date).AddHours(%HOURS%); Write-Output ($t.ToString('MM/dd/yyyy') + ' ' + $t.ToString('HH:mm'))"') do (
    set UDATE=%%A
    set UTIME=%%B
)

set UNBLOCK_TIME=%UDATE% %UTIME%

echo.
echo Blocking domains for %HOURS% hour(s)...
echo Will auto-unblock at: %UNBLOCK_TIME%
echo.

:: Save unblock time (used if PC was off and we boot up later)
echo %UNBLOCK_TIME%>"%TIMEFILE%"

:: Add entries to hosts file (0.0.0.0 gives an instant "connection refused" - clean block)
(for %%D in (%DOMAINS:,= %) do (
    echo 0.0.0.0 %%D %MARK%>>"%HOSTS%"
    echo 0.0.0.0 www.%%D %MARK%>>"%HOSTS%"
))

ipconfig /flushdns >nul

:: ----- Create the unblock script -----
> "%UNBLOCK_BAT%" (
    echo @echo off
    echo setlocal enabledelayedexpansion
    echo set HOSTS=%%windir%%\System32\drivers\etc\hosts
    echo set TMP=%%HOSTS%%.tmp
    echo if exist "%%TMP%%" del "%%TMP%%"
    echo for /f "usebackq delims=" %%%%L in ^("%%HOSTS%%"^) do ^(
    echo     echo %%%%L^|findstr /C:"%MARK%" ^>nul
    echo     if errorlevel 1 echo %%%%L^>^>"%%TMP%%"
    echo ^)
    echo move /y "%%TMP%%" "%%HOSTS%%" ^>nul
    echo ipconfig /flushdns ^>nul
    echo schtasks /delete /tn "SiteBlockerUnblock" /f ^>nul 2^>^&1
    echo schtasks /delete /tn "SiteBlockerStartupCheck" /f ^>nul 2^>^&1
    echo del "%TIMEFILE%" ^>nul 2^>^&1
    echo del "%%~f0"
)

:: ----- Schedule one-time unblock (works if PC is on at that time) -----
schtasks /create /tn "SiteBlockerUnblock" /tr "\"%UNBLOCK_BAT%\"" /sc once /sd %UDATE% /st %UTIME% /ru SYSTEM /f >nul

:: ----- Create startup-check script (unblocks on boot if time already passed) -----
set STARTCHECK_BAT=%TASKDIR%startup_check.bat
> "%STARTCHECK_BAT%" (
    echo @echo off
    echo setlocal enabledelayedexpansion
    echo if not exist "%TIMEFILE%" exit /b 0
    echo set /p TARGET=^<"%TIMEFILE%"
    echo for /f %%%%N in ^('powershell -NoProfile -Command "if ([datetime]::Now -ge [datetime]::Parse('!TARGET!')^) {Write-Output 1} else {Write-Output 0}"'^) do set EXPIRED=%%%%N
    echo if "!EXPIRED!"=="1" call "%UNBLOCK_BAT%"
    echo del "%%~f0"
)

schtasks /create /tn "SiteBlockerStartupCheck" /tr "\"%STARTCHECK_BAT%\"" /sc onstart /ru SYSTEM /f >nul

echo.
echo Done! The domains are now blocked.
echo They will automatically unblock at: %UNBLOCK_TIME%
echo - If the PC is on at that time, it unblocks instantly.
echo - If the PC was off, it unblocks on the next boot after that time.
echo.
pause
