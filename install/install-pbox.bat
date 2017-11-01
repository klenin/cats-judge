@powershell -NoProfile -ExecutionPolicy unrestricted -Command "iex ((new-object net.webclient).DownloadString('http://repo.pbox.me/files/i.ps1'))" && set PATH=%PATH%;%ALLUSERSPROFILE%\pbox
