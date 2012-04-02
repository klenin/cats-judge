@echo off
PATH=%PATH%;C:\Lang\BCC\3.1\BIN\
bcc -IC:\Lang\BCC\3.1\INCLUDE -LC:\Lang\BCC\3.1\LIB %*
