@echo off
rem Renders the district fly-through offline (fixed 60 fps, with sound) and
rem converts it to MP4 for YouTube. Add --titles after --quit for shot captions.
setlocal
set GODOT=C:\Users\Allen\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe
set ROOT=%~dp0
if not exist "%ROOT%videos" mkdir "%ROOT%videos"
"%GODOT%" --path "%ROOT%game" --write-movie "%ROOT%videos\district_flythrough.avi" --fixed-fps 60 --resolution 1920x1080 -- --level=district --cinematic=all --quit
where ffmpeg >nul 2>&1 && ffmpeg -y -i "%ROOT%videos\district_flythrough.avi" -c:v libx264 -crf 17 -preset slow -pix_fmt yuv420p -c:a aac -b:a 192k "%ROOT%videos\district_flythrough.mp4"
