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
rem                         with Exomizer (loads faster), the manual and
rem                         the CRX2026 picture
rem   magictypewriter-packed.prg   (release) the packed program
rem   magictypewriter-release.d64  (release) a copy of the release disk, for
rem                         the GitHub release: a debug build later
rem                         overwrites magictypewriter.d64, not this one
rem   main.vs               labels for VICE's monitor
rem   main.lbl, main.lst    label list and assembly listing, for reading
rem
rem A release build needs Exomizer (exomizer.exe), on the PATH or in C:\bin;
rem without it the release build stops: a release is always packed.
rem (VS64's build is a debug build: it makes only the .prg.)
rem
rem build.sh does the same steps on Linux. Keep the two in step.
rem ======================================================================
setlocal
cd /d "%~dp0"

set ACME=C:\bin\acme0.97win\acme\acme.exe
set C1541=C:\bin\GTK3VICE-3.9-win64\GTK3VICE-3.9-win64\bin\c1541.exe
set EXOMIZER=exomizer
where %EXOMIZER% >nul 2>nul
if errorlevel 1 if exist C:\bin\exomizer.exe set EXOMIZER=C:\bin\exomizer.exe

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
rem tape; -x1: the border flashes while it unpacks), the manual and the
rem CRX2026 picture (test\crx2026.prg, a Magic Typewriter document).
:release_disk
"%EXOMIZER%" -v >nul 2>nul
if errorlevel 1 goto no_exomizer
echo Packing with Exomizer...
"%EXOMIZER%" sfx sys -x1 -q -o build\magictypewriter-packed.prg build\magictypewriter.prg
if errorlevel 1 goto failed
echo Making disk image (the packed program, the manual and CRX2026)...
"%C1541%" -format "magic typewriter,mt" d64 build\magictypewriter.d64 -write build\magictypewriter-packed.prg "magic typewriter" >nul
if errorlevel 1 goto failed
"%C1541%" -attach build\magictypewriter.d64 -write test\manual.prg "manual,p" >nul
if errorlevel 1 goto failed
"%C1541%" -attach build\magictypewriter.d64 -write test\crx2026.prg "crx2026,p" >nul
if errorlevel 1 goto failed
copy /y build\magictypewriter.d64 build\magictypewriter-release.d64 >nul
if errorlevel 1 goto failed
echo Done: build\magictypewriter-release.d64 (release: packed program, manual, CRX2026)
exit /b 0
:no_exomizer
echo Exomizer was not found (on the PATH or as C:\bin\exomizer.exe).
echo A release must be packed: install Exomizer, then build again.
goto failed

:failed
echo BUILD FAILED
exit /b 1
