package CATS::Spawner::Platform;

use strict;
use warnings;

use POSIX qw();

sub get {
    $^O eq 'MSWin32' ? 'win32' :
    $^O eq 'darwin' ? 'darwin' :
    $^O eq 'linux' ? (POSIX::uname[4] eq 'x86_64' ? 'linux-amd64' : 'linux-i386') :
    undef
}

1;
