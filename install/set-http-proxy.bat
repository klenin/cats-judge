@echo off
set HTTP_PROXY=http://%1:%2
set HTTPS_PROXY=http://%1:%2
set _JAVA_OPTIONS=-Dhttp.proxyHost=%1 -Dhttp.proxyPort=%2

setlocal
set _H=%1
set _P=%2
setx HTTP_PROXY http://%_H%:%_P%
setx HTTPS_PROXY %HTTP_PROXY%
setx _JAVA_OPTIONS "-Dhttp.proxyHost=%_H% -Dhttp.proxyPort=%_P%"
endlocal
