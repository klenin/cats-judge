@echo off

set VS=C:\Program Files (x86)\Microsoft Visual Studio 14.0\VC
set WK=C:\Program Files (x86)\Windows Kits
set P3=%PYTHON3_HOME%

rem Compile:
if "%1" == "-c" (
    rem echo from distutils.core import setup; from Cython.Build import cythonize > setup.py
    rem echo setup(ext_modules = cythonize(r"%2"^)^) >> setup.py
    rem python setup.py build_ext --inplace
    %PYTHON3_HOME%\python -m cython %2 --embed -3
    if errorlevel 1 exit 1
    "%VS%\BIN\x86_amd64\cl.exe" /c /nologo /Ox /W3 /GL /DNDEBUG ^
        -I%P3%\include -I%P3%\include "-I%VS%\INCLUDE" "-I%VS%\ATLMFC\INCLUDE" ^
        "-I%WK%\10\include\10.0.10240.0\ucrt" ^
        "-I%WK%\NETFXSDK\4.6.1\include\um" "-I%WK%\8.1\include\shared" ^
        "-I%WK%\8.1\include\um" "-I%WK%\8.1\include\winrt" /Tc%3.c /Fo%3.obj
    if errorlevel 1 exit 2
    "%VS%\BIN\x86_amd64\link.exe" /nologo /INCREMENTAL:NO /LTCG /MANIFEST:EMBED,ID=2 /MANIFESTUAC:NO ^
        /LIBPATH:%P3%\libs /LIBPATH:%P3%\PCbuild\amd64 ^
        "/LIBPATH:%VS%\LIB\amd64" "/LIBPATH:%VS%\ATLMFC\LIB\amd64" ^
        "/LIBPATH:%WK%\10\lib\10.0.10240.0\ucrt\x64" "/LIBPATH:%WK%\NETFXSDK\4.6.1\lib\um\x64" ^
        "/LIBPATH:%WK%\8.1\lib\winv6.3\um\x64" %3.obj /OUT:%3.exe
    if errorlevel 1 exit 3
    exit 0
)

rem Run:
if "%1" == "-r" (
    rem echo import %2 > %2.py
    rem python %2.py
    %2.exe
    if errorlevel 1 exit 4
    exit 0
)

exit 5
