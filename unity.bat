@echo off
if exist hack.unity ( exit /b )
start /b /wait "unity" "C:\Program Files\Unity\Hub\Editor\2018.4.13f1\Editor\Unity.exe" -batchmode -quit -projectPath "project" -nographics -buildWindowsPlayer ./build/main.exe -logFile out.txt
if [%errorlevel%] == [1] (
    type out.txt 1>&2
    exit /b 1
)
