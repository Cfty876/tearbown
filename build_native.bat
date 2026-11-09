@echo off
rem Builds native\ (voxcore GDExtension) and copies it to game\bin\voxcore.dll.
rem Close the Godot editor first: Windows locks the loaded DLL (the build still
rem succeeds, the copy is retried by running this script again).
setlocal
call "C:\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
set CMAKE_DIR=C:\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake
set PATH=%CMAKE_DIR%\CMake\bin;%CMAKE_DIR%\Ninja;%PATH%
set ROOT=%~dp0
if not exist "%ROOT%native\build\build.ninja" (
  cmake -S "%ROOT%native" -B "%ROOT%native\build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DPython3_EXECUTABLE="%ROOT%tools\python\python.exe" || exit /b 1
)
set TARGET=%1
if "%TARGET%"=="" set TARGET=voxcore
cmake --build "%ROOT%native\build" --target %TARGET% || exit /b 1
if "%TARGET%"=="voxcore" (
  copy /Y "%ROOT%native\build\out\voxcore.dll" "%ROOT%game\bin\voxcore.dll" >nul 2>&1 && echo COPIED to game\bin || echo COPY FAILED: game\bin\voxcore.dll is locked, close Godot and run again
)
echo BUILD OK
