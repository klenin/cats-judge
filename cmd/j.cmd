@echo off
call "%~dp0..\preparevs.cmd" >nul
rem set SP_USER=
rem set SP_PASSWORD=
set SP_RUNAS=0
set SP_WRITE_LIMIT=30
set SP_MEMORY_LIMIT=512
set SP_DEADLINE=10
set SP_REPORT_FILE=report.txt
set SP_OUTPUT_FILE=stdout.txt
set SP_ERROR_FILE=stderr.txt
set SP_HIDE_REPORT=1
set SP_HIDE_OUTPUT=0
set SP_SECURITY_LEVEL=0
set CATS_JUDGE=1
set SP_LOAD_RATIO=5%%
rem set SP_LEGACY=sp00
set SP_JSON=1

perl "%~dp0..\judge.pl" %*
