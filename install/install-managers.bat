@powershell -NoProfile -ExecutionPolicy unrestricted -Command "iex ((new-object net.webclient).DownloadString('http://repo.pbox.me/files/i.ps1'))" && set PATH=%PATH%;%ALLUSERSPROFILE%\pbox
@"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -InputFormat None -ExecutionPolicy Bypass -Command "iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))" && SET "PATH=%PATH%;%ALLUSERSPROFILE%\chocolatey\bin"

rem PBOX has very old wget with TLS 1.1, unable to download anything over modern https.
@curl --output %TEMP%\wget.zip https://eternallybored.org/misc/wget/releases/wget-1.21.2-win64.zip
@%PBOX_HOME%\bin\7za e -o%PBOX_HOME%\bin -y %TEMP%\wget.zip wget.exe
