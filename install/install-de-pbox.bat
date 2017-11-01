set HTTP_PROXY=http://proxy.dvfu.ru:3128
set HTTPS_PROXY=http://proxy.dvfu.ru:3128

rem Firebird 3.x needs extra config to be able to connect to 2.x
choco install firebird --version 2.5.7.1000 -y -params "/ClientAndDevTools"
rem !!! Need to make fbclient.dll available
mkdir C:\Lang\
rem Need relatively late Perl, pbox only provides 5.20
call pbox install strawberryperl --homedir=C:\Lang\perl
rem Must install DBD::Firebird before MinGW to avoid G++ version clash
cpanm DBD::Firebird

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

mkdir C:\Lang\pascalabc
%PBOX_HOME%\bin\wget --output-document %TEMP%\pabcnet.zip http://pascalabc.net/downloads/PABCNETC.zip 
%PBOX_HOME%\bin\7za x -oC:\Lang\pascalabc %TEMP%\pabcnet.zip

mkdir C:\git\
call pbox install git --homedir=C:\git
                                                              
