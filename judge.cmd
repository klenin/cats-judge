@echo off
perl -c judge.pl 2>nul || ( perl -c judge.pl || exit /b )

if [%SUPPRESS_TERMINATE_PROMPT%] == [YES] (
    set SUPPRESS_TERMINATE_PROMPT=
) else (
    set SUPPRESS_TERMINATE_PROMPT=YES
    call %0 %* < nul
    exit /b
)
call preparevs.cmd
rem set SP_USER=
rem set SP_PASSWORD=
rem set SP_RUNAS=60
set SP_WRITE_LIMIT=30
set SP_MEMORY_LIMIT=512
set SP_DEADLINE=10
set SP_REPORT_FILE=report.txt
set SP_OUTPUT_FILE=stdout.txt
set SP_ERROR_FILE=stderr.txt
set SP_HIDE_REPORT=1
set SP_HIDE_OUTPUT=0
set SP_SECURITY_LEVEL=1
set CATS_JUDGE=1
set SP_LOAD_RATIO=5%%
set SP_LEGACY=sp00
set SP_JSON=1
set DOTNET_CLI_UI_LANGUAGE=en-us
set VSLANG=1033

perl judge.pl config --print "^name$" --bare | ^
perl -MWin32::API -e "($x = <STDIN>) && Win32::API->new('kernel32', 'SetConsoleTitle', 'P', 'I')->Call($x)"

:repeat
perl judge.pl serve
if [%errorlevel%] == [99] ( exit /b )
perl "-Msigtrap=handler,sub{exit 99},INT" -e "sleep(2)"
if [%errorlevel%] == [99] ( exit /b )
goto repeat
