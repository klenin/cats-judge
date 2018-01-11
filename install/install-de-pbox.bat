call set-http-proxy.bat proxy.dvfu.ru 3128

rem Firebird 3.x needs extra config to be able to connect to 2.x
choco install firebird --version 2.5.7.1000 -y -params "/ClientAndDevTools"
set FIREBIRD_HOME=C:\Program Files\Firebird\Firebird_2_5
setx FIREBIRD_HOME %FIREBIRD_HOME%

mkdir C:\Lang\

rem Need relatively late Perl, pbox provides only 5.20
%PBOX_HOME%\bin\wget --output-document %TEMP%\perl.msi http://strawberryperl.com/download/5.26.1.1/strawberry-perl-5.26.1.1-64bit.msi
msiexec /i %TEMP%\perl.msi INSTALLDIR=C:\Lang\perl /quiet /passive /norestart

rem Must install DBD::Firebird before MinGW to avoid G++ version clash
set PATH=%PATH%;%FIREBIRD_HOME%;C:\Lang\perl\perl\bin
setx PATH %PATH%
call cpanm DBD::Firebird

call pbox install mingw-w64 --homedir=C:\Lang\mingw-w64
call pbox install jdk8 --homedir=C:\Lang\jdk8
call pbox install kotlin --homedir=C:\Lang\kotlin
call pbox install python3 --homedir=C:\Lang\python3
call pbox install lazarus --homedir=C:\Lang\lazarus
call pbox install ruby --homedir=C:\Lang\ruby
call pbox install php --homedir=C:\Lang\php
call pbox install haskellplatform --homedir=C:\Lang\haskell
call pbox install nodejs-portable --homedir=C:\Lang\nodejs
call pbox install rust --homedir=C:\Lang\rust
call pbox install delphi7-compiler --homedir=C:\Lang\delphi
call pbox install 7zip --homedir=C:\Lang\7-zip
call pbox install go --homedir=C:\Lang\go

rem Pbox provides only PascalABC 2.22
mkdir C:\Lang\pascalabc
%PBOX_HOME%\bin\wget --output-document %TEMP%\pabcnet.zip http://pascalabc.net/downloads/PABCNETC.zip
%PBOX_HOME%\bin\7za x -oC:\Lang\pascalabc %TEMP%\pabcnet.zip

rem LLVM uses NSIS installer
%PBOX_HOME%\bin\wget --output-document %TEMP%\llvm.exe http://releases.llvm.org/5.0.0/LLVM-5.0.0-win64.exe
%TEMP%\llvm.exe /S /D=C:\Lang\clang

mkdir C:\Lang\freebasic
%PBOX_HOME%\bin\wget --output-document %TEMP%\freebasic.7z http://free-basic.ru/user-files/FreeBASIC-1.05.0-win64.7z
%PBOX_HOME%\bin\7za x -oC:\Lang %TEMP%\freebasic.7z
move C:\Lang\FreeBASIC-1.05.0-win64 C:\Lang\freebasic

mkdir C:\git\
call pbox install git --homedir=C:\git

rem IDE only, separate GUI action required to install C++
choco install visualstudio2015community -y --execution-timeout 27000
