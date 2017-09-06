@echo off
if [%SUPPRESS_TERMINATE_PROMPT%] == [YES] (
    set SUPPRESS_TERMINATE_PROMPT=
) else (
    set SUPPRESS_TERMINATE_PROMPT=YES
    call %0 %* < nul
    exit /b
)
call preparevs.cmd
:SET SP_USER=
:SET SP_PASSWORD=
:SET SP_RUNAS=60
SET SP_WRITE_LIMIT=30
SET SP_MEMORY_LIMIT=512
SET SP_DEADLINE=10
SET SP_REPORT_FILE=report.txt
SET SP_OUTPUT_FILE=stdout.txt
SET SP_ERROR_FILE=stderr.txt
SET SP_HIDE_REPORT=1
SET SP_HIDE_OUTPUT=0
SET SP_SECURITY_LEVEL=1
SET CATS_JUDGE=1
SET SP_LOAD_RATIO=5%%
SET SP_LEGACY=sp00
SET SP_JSON=1

:repeat
perl judge.pl serve
if [%errorlevel%] == [99] ( exit /b )
perl "-Msigtrap=handler,sub{exit 99},INT" -e "sleep(2)"
if [%errorlevel%] == [99] ( exit /b )
goto repeat
