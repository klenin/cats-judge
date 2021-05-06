@echo off
if not "%VS140COMNTOOLS%"=="" ( call "C:\Program Files (x86)\Microsoft Visual Studio 14.0\VC\vcvarsall.bat" amd64
) else if not "%VS130COMNTOOLS%"=="" ( call "%VS130COMNTOOLS%vsvars32.bat"
) else if not "%VS120COMNTOOLS%"=="" ( call "%VS120COMNTOOLS%vsvars32.bat"
) else if not "%VS110COMNTOOLS%"=="" ( call "%VS110COMNTOOLS%vsvars32.bat"
) else if not "%VS100COMNTOOLS%"=="" ( call "%VS100COMNTOOLS%vsvars32.bat"
) else if not "%VS90COMNTOOLS%"=="" ( call "%VS90COMNTOOLS%vsvars32.bat"
) else if not "%VS80COMNTOOLS%"=="" ( call "%VS80COMNTOOLS%vsvars32.bat"
)
