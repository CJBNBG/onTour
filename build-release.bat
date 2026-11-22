@echo off
setlocal EnableExtensions EnableDelayedExpansion
title onTour - Release-Build

rem ====================================================================
rem  onTour - Release-Build als Android App Bundle (.aab)
rem
rem  Ablauf: Flutter aktualisieren, aufraeumen, Pakete holen, Gradle
rem  bereinigen, App Bundle bauen, Datei nach Version/Build benennen.
rem  Bricht beim ersten Fehler ab und nennt Schritt und Fehlercode.
rem
rem  Aufruf:  build-release.bat            (am Ende "pause")
rem           build-release.bat nopause    (ohne "pause", z. B. fuer Skripte)
rem  Ablegen: im Projektordner (neben pubspec.yaml).
rem  Ergebnis: build\app\outputs\bundle\release\onTour-<Version>-<Build>.aab
rem            (Version und Build stammen aus "version:" in pubspec.yaml)
rem  Protokoll der Schritte: build-log.txt (wird bei jedem Lauf neu angelegt)
rem ====================================================================

rem ---------- Einstellungen (1 = ausfuehren, 0 = ueberspringen) ----------
set "DO_FLUTTER_UPGRADE=0"
set "DO_PUB_CACHE_REPAIR=1"
set "DO_PUB_UPGRADE=1"
set "DO_GRADLE_REFRESH=1"
set "APP_NAME=onTour"

rem ---------- Grundlagen ----------
set "ROOT=%~dp0"
set "LOG=%ROOT%build-log.txt"
set "STEP="
set "RC="
set "MSG="

cd /d "%ROOT%" 
if errorlevel 1 (
  set "STEP=In den Projektordner wechseln"
  set "MSG=Ordner nicht erreichbar: %ROOT%"
  goto :fail
)

> "%LOG%" echo [%date% %time%] Build gestartet in %ROOT%

rem ---------- Voraussetzungen pruefen ----------
set "STEP=Voraussetzungen pruefen"

where flutter >nul 2>&1
if errorlevel 1 (
  set "MSG=Flutter wurde nicht gefunden. Ist Flutter im PATH?"
  goto :fail
)
if not exist "%ROOT%pubspec.yaml" (
  set "MSG=pubspec.yaml fehlt - die Batch-Datei gehoert in den Projektordner."
  goto :fail
)
if not exist "%ROOT%android\gradlew.bat" (
  set "MSG=android\gradlew.bat fehlt - Android-Projektordner unvollstaendig."
  goto :fail
)

rem Version und Build aus pubspec.yaml lesen (Zeile "version: 1.0.0+25")
set "VERSION_FULL="
for /f "tokens=2 delims=: " %%A in ('findstr /b /c:"version:" "%ROOT%pubspec.yaml"') do (
  if not defined VERSION_FULL set "VERSION_FULL=%%A"
)
if not defined VERSION_FULL (
  set "MSG=Keine Zeile "version:" in pubspec.yaml gefunden."
  goto :fail
)
set "VER="
set "BUILD="
for /f "tokens=1,2 delims=+" %%A in ("!VERSION_FULL!") do (
  set "VER=%%A"
  set "BUILD=%%B"
)
if not defined VER (
  set "MSG=Version konnte nicht gelesen werden: !VERSION_FULL!"
  goto :fail
)
if defined BUILD (
  set "AAB_NAME=%APP_NAME%-!VER!-!BUILD!.aab"
) else (
  set "AAB_NAME=%APP_NAME%-!VER!.aab"
)
set "AAB_DIR=%ROOT%build\app\outputs\bundle\release"
set "AAB_SRC=%AAB_DIR%\app-release.aab"
set "AAB_DST=%AAB_DIR%\!AAB_NAME!"

echo.
echo  Projekt : %ROOT%
echo  Version : !VER!  Build: !BUILD!
echo  Ergebnis: !AAB_NAME!
>> "%LOG%" echo [%date% %time%] Version !VER!, Build !BUILD!, Ziel !AAB_NAME!

rem Hinweis (kein Abbruch): ohne Signierung ist das Bundle nicht fuer den Play Store geeignet
if not exist "%ROOT%android\key.properties" (
  echo.
  echo  HINWEIS: android\key.properties nicht gefunden - das Bundle wird
  echo           evtl. nicht mit deinem Upload-Schluessel signiert.
  >> "%LOG%" echo [%date% %time%] HINWEIS: android\key.properties fehlt
)

rem ---------- 1. Flutter aktualisieren ----------
if not "%DO_FLUTTER_UPGRADE%"=="1" goto :skip_upgrade
set "STEP=Flutter aktualisieren (flutter upgrade)"
call :run flutter upgrade || goto :fail
:skip_upgrade

rem ---------- 2. Lokalisierung (nur wenn eingerichtet) ----------
if exist "%ROOT%l10n.yaml" (
  set "STEP=Lokalisierung erzeugen (flutter gen-l10n)"
  call :run flutter gen-l10n || goto :fail
) else (
  echo.
  echo  flutter gen-l10n uebersprungen: keine l10n.yaml im Projekt.
  >> "%LOG%" echo [%date% %time%] gen-l10n uebersprungen ^(keine l10n.yaml^)
)

rem ---------- 3. Aufraeumen und Pakete ----------
set "STEP=Projekt bereinigen (flutter clean)"
call :run flutter clean || goto :fail

if not "%DO_PUB_CACHE_REPAIR%"=="1" goto :skip_cache
set "STEP=Paket-Cache reparieren (flutter pub cache repair)"
call :run flutter pub cache repair || goto :fail
:skip_cache

set "STEP=Pakete holen (flutter pub get)"
call :run flutter pub get || goto :fail

if not "%DO_PUB_UPGRADE%"=="1" goto :skip_pubupgrade
set "STEP=Pakete aktualisieren (flutter pub upgrade)"
call :run flutter pub upgrade || goto :fail
:skip_pubupgrade

rem ---------- 4. Gradle ----------
set "STEP=In den Ordner android wechseln"
pushd "%ROOT%android"
if errorlevel 1 (
  set "MSG=Ordner android nicht erreichbar."
  goto :fail
)

set "STEP=Gradle bereinigen (gradlew clean)"
call :run .\gradlew clean || goto :fail

if not "%DO_GRADLE_REFRESH%"=="1" goto :skip_gradle_refresh
set "STEP=Gradle-Abhaengigkeiten neu laden (gradlew dependencies --refresh-dependencies)"
call :run .\gradlew dependencies --refresh-dependencies || goto :fail
:skip_gradle_refresh

set "STEP=Gradle mit Configuration Cache (gradlew --configuration-cache)"
call :run .\gradlew --configuration-cache || goto :fail

popd

rem ---------- 5. App Bundle bauen ----------
set "STEP=App Bundle bauen (flutter build appbundle --release)"
call :run flutter build appbundle --release || goto :fail

rem ---------- 6. Ergebnis pruefen und umbenennen ----------
set "STEP=Ergebnis pruefen"
if not exist "%AAB_SRC%" (
  set "MSG=Erwartete Datei fehlt: %AAB_SRC%"
  goto :fail
)

echo.
dir "%AAB_DIR%\*"

set "STEP=Datei umbenennen (-> !AAB_NAME!)"
if exist "!AAB_DST!" (
  echo.
  echo  "!AAB_NAME!" existiert bereits und wird ersetzt.
  del /q "!AAB_DST!"
  if errorlevel 1 (
    set "MSG=Die vorhandene Datei laesst sich nicht loeschen ^(geoeffnet?^): !AAB_DST!"
    goto :fail
  )
)
move /y "%AAB_SRC%" "!AAB_DST!" >nul
if errorlevel 1 (
  set "MSG=Umbenennen nicht moeglich: %AAB_SRC%"
  goto :fail
)

rem ---------- Erfolg ----------
echo.
echo ################################################################
echo  BUILD ERFOLGREICH
echo  Datei : !AAB_DST!
for %%F in ("!AAB_DST!") do echo  Groesse: %%~zF Bytes
echo ################################################################
>> "%LOG%" echo [%date% %time%] BUILD ERFOLGREICH: !AAB_DST!
if /i not "%~1"=="nopause" pause
endlocal & exit /b 0


rem ====================================================================
rem  :run - fuehrt einen Befehl aus, protokolliert ihn und meldet den
rem         Fehlercode zurueck (Aufruf: set "STEP=..." & call :run <Befehl>)
rem ====================================================================
:run
echo.
echo ================================================================
echo [%time%] %STEP%
echo ^> %*
echo ================================================================
>> "%LOG%" echo [%date% %time%] START: %STEP%
call %*
set "RC=!errorlevel!"
if not "!RC!"=="0" (
  >> "%LOG%" echo [%date% %time%] FEHLER ^(Code !RC!^): %STEP%
  exit /b !RC!
)
>> "%LOG%" echo [%date% %time%] OK: %STEP%
exit /b 0


rem ====================================================================
rem  :fail - einheitliche Fehlermeldung, danach Abbruch mit Fehlercode 1
rem ====================================================================
:fail
cd /d "%ROOT%" 2>nul
echo.
echo ################################################################
echo  BUILD FEHLGESCHLAGEN
echo  Schritt  : %STEP%
if defined RC echo  Code     : %RC%
if defined MSG echo  Hinweis  : %MSG%
echo  Tipp     : Die Fehlermeldung steht oberhalb. "flutter doctor -v"
echo             prueft die Installation, "%LOG%" zeigt die Schritte.
echo ################################################################
>> "%LOG%" echo [%date% %time%] BUILD FEHLGESCHLAGEN bei: %STEP% ^(Code %RC%^) %MSG%
if /i not "%~1"=="nopause" pause
endlocal & exit /b 1