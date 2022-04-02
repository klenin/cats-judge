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

call pbox install mingw-w64-7 --homedir=C:\Lang\mingw-w64-7
call pbox install jdk8 --homedir=C:\Lang\jdk8
call pbox install kotlin --homedir=C:\Lang\kotlin
call pbox install python3 --homedir=C:\Lang\python3
call pbox install pypy3 --homedir=C:\Lang\pypy
call pbox install lazarus --homedir=C:\Lang\lazarus
call pbox install ruby --homedir=C:\Lang\ruby
call pbox install php --homedir=C:\Lang\php
call pbox install haskellplatform --homedir=C:\Lang\haskell
call pbox install nodejs-portable --homedir=C:\Lang\nodejs
call pbox install rust --homedir=C:\Lang\rust
call pbox install delphi7-compiler --homedir=C:\Lang\delphi
call pbox install 7zip --homedir=C:\Lang\7-zip
call pbox install go --homedir=C:\Lang\go
rem call pbox install dotnet-core-sdk --homedir=C:\Lang\dotnet

rem https://dotnet.microsoft.com/download/dotnet/thank-you/sdk-5.0.200-windows-x64-binaries
%PBOX_HOME%\bin\wget --output-document %TEMP%\dotnet.zip https://download.visualstudio.microsoft.com/download/pr/761159fa-2843-4abe-8052-147e6c873a78/77658948a9e0f7bc31e978b6bc271ec8/dotnet-sdk-5.0.200-win-x64.zip
%PBOX_HOME%\bin\7za x -oC:\Lang\dotnet %TEMP%\dotnet.zip
setx DOTNET_ROOT C:\Lang\dotnet
setx DOTNET_CLI_TELEMETRY_OPTOUT 1

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

rem Not quite correct, since chocolatey shims will still point to Program Files.
choco install erlang -ia "'/D=C:\Lang\erlang'"

%PBOX_HOME%\bin\wget --output-document %TEMP%\swi-prolog.exe http://www.swi-prolog.org/download/stable/bin/swipl-w64-764.exe
rem Change Prolog's assocated extension, since default .pl conflicts with Perl.
%TEMP%\swi-prolog.exe /S /EXT=pro /INSTDIR=C:\Lang\swipl

mkdir C:\git\
call pbox install git --homedir=C:\git

rem PYTHON3_HOME is set by pbox installer.
if exist "%PYTHON3_HOME%\python.exe" (
    rem Update sqlite3 library
    %PBOX_HOME%\bin\wget --output-document %TEMP%\sqlite3.zip http://www.sqlite.org/2018/sqlite-dll-win64-x64-3250200.zip
    %PBOX_HOME%\bin\7za x -y -o"%PYTHON3_HOME%\DLLs" %TEMP%\sqlite3.zip
    rem Includes numpy
    "%PYTHON3_HOME%\python.exe" -m pip install pandas sklearn opencv-python matplotlib
    rem Install cython
    "%PYTHON3_HOME%\python.exe" -m pip install cython
    copy /y cython.bat "%PYTHON3_HOME%\cython.bat"
    "%PYTHON3_HOME%\python.exe" -m pip install requests
)

mkdir C:\Lang\logisim
%PBOX_HOME%\bin\wget --output-document C:\Lang\logisim\logisim.jar https://github.com/reds-heig/logisim-evolution/releases/download/v3.3.1/logisim-evolution-3.3.1.jar

mkdir C:\Lang\digitalsim
%PBOX_HOME%\bin\wget --output-document %TEMP%\digitalsim.zip https://github.com/hneemann/Digital/releases/download/v0.24/Digital.zip
%PBOX_HOME%\bin\7za e -oC:\Lang\digitalsim %TEMP%\digitalsim.zip */*.jar

%PBOX_HOME%\bin\wget --output-document %TEMP%\nasm.zip https://www.nasm.us/pub/nasm/releasebuilds/2.15.05/win64/nasm-2.15.05-win64.zip
%PBOX_HOME%\bin\7za e -oC:\Lang\nasm %TEMP%\nasm.zip

rem IDE only, separate GUI action required to install C++
choco install visualstudio2015community -y --execution-timeout 27000
