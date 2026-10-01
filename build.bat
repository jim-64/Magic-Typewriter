@echo off
rem ======================================================================
rem Magic Typewriter build (Windows)
rem
rem   build            debug build (includes the test mailbox)
rem   build release    release build (no test mailbox)
rem
rem Output in the build folder:
rem   magictypewriter.prg   the program
rem   magictypewriter.d64   disk image with the program and the test files
rem   main.vs               labels for VICE's monitor
rem   main.lbl, main.lst    label list and assembly listing, for reading
rem
rem build.sh does the same steps on Linux. Keep the two in step.
rem ======================================================================
setlocal
cd /d "%~dp0"

set ACME=C:\bin\acme0.97win\acme\acme.exe
set C1541=C:\bin\GTK3VICE-3.9-win64\GTK3VICE-3.9-win64\bin\c1541.exe

set DEBUG=1
if /i "%~1"=="release" set DEBUG=0

if not exist build mkdir build

echo Assembling (DEBUG=%DEBUG%)...
"%ACME%" -f cbm -DDEBUG=%DEBUG% -o build\magictypewriter.prg -l build\main.lbl --vicelabels build\main.vs -r build\main.lst src\main.asm
if errorlevel 1 goto failed

echo Making disk image...
"%C1541%" -format "magic typewriter,mt" d64 build\magictypewriter.d64 -write build\magictypewriter.prg "magic typewriter" >nul
if errorlevel 1 goto failed

rem Add the files in test\ (name without extension): first the .prg files as
rem PRG files (the manual, a Magic Typewriter document: made from
rem docs\manual.txt by tools\make_manual.py), then the .seq files as SEQ.
for %%f in (test\*.prg) do (
    "%C1541%" -attach build\magictypewriter.d64 -write "%%f" "%%~nf,p" >nul
    if errorlevel 1 goto failed
)
for %%f in (test\*.seq) do (
    "%C1541%" -attach build\magictypewriter.d64 -write "%%f" "%%~nf,s" >nul
    if errorlevel 1 goto failed
)

echo Done: build\magictypewriter.prg and build\magictypewriter.d64
exit /b 0

:failed
echo BUILD FAILED
exit /b 1
