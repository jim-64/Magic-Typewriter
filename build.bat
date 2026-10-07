@echo off
rem ======================================================================
rem Magic Typewriter build (Windows)
rem
rem   build            debug build (includes the test mailbox)
rem   build release    release build (no test mailbox)
rem
rem Output in the build folder:
rem   magictypewriter.prg   the program
rem   magictypewriter.d64   disk image: debug build - the program and all the
rem                         test files; release build - the program packed
rem                         with Exomizer (loads faster) and the manual
rem   magictypewriter-packed.prg   (release) the packed program
rem   main.vs               labels for VICE's monitor
rem   main.lbl, main.lst    label list and assembly listing, for reading
rem
rem Exomizer (exomizer.exe) must be on the PATH for the packed program;
rem without it the release disk gets the program as it is.
rem
rem build.sh does the same steps on Linux. Keep the two in step.
rem ======================================================================
setlocal
cd /d "%~dp0"

set ACME=C:\bin\acme0.97win\acme\acme.exe
set C1541=C:\bin\GTK3VICE-3.9-win64\GTK3VICE-3.9-win64\bin\c1541.exe
set EXOMIZER=exomizer

set DEBUG=1
if /i "%~1"=="release" set DEBUG=0

if not exist build mkdir build

echo Assembling (DEBUG=%DEBUG%)...
"%ACME%" -f cbm -DDEBUG=%DEBUG% -o build\magictypewriter.prg -l build\main.lbl --vicelabels build\main.vs -r build\main.lst src\main.asm
if errorlevel 1 goto failed

if "%DEBUG%"=="0" goto release_disk

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

rem The release disk: the program packed by Exomizer into a program that
rem unpacks itself (a BASIC SYS line, so LOAD and RUN as usual, from disk or
rem tape; -x1: the border flashes while it unpacks), and the manual.
:release_disk
set PROGRAM=build\magictypewriter.prg
where %EXOMIZER% >nul 2>nul
if errorlevel 1 goto no_exomizer
echo Packing with Exomizer...
"%EXOMIZER%" sfx sys -x1 -q -o build\magictypewriter-packed.prg build\magictypewriter.prg
if errorlevel 1 goto failed
set PROGRAM=build\magictypewriter-packed.prg
goto release_write
:no_exomizer
echo Exomizer is not on the PATH: the disk gets the program unpacked.
:release_write
echo Making disk image (the program and the manual)...
"%C1541%" -format "magic typewriter,mt" d64 build\magictypewriter.d64 -write %PROGRAM% "magic typewriter" >nul
if errorlevel 1 goto failed
"%C1541%" -attach build\magictypewriter.d64 -write test\manual.prg "manual,p" >nul
if errorlevel 1 goto failed
echo Done: build\magictypewriter.prg and build\magictypewriter.d64 (release)
exit /b 0

:failed
echo BUILD FAILED
exit /b 1
