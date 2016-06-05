package CATS::Spawner::Platform;

use strict;
use warnings;

use File::Spec;
use POSIX qw();

sub get {
    $^O eq 'MSWin32' ? 'win32' :
    $^O eq 'darwin' ? 'darwin' :
    $^O eq 'linux' ? (POSIX::uname[4] eq 'x86_64' ? 'linux-amd64' : 'linux-i386') :
    undef
}

sub get_path {
    my $platform = $_[0] || get;
    my $fn = $^O eq 'MSWin32' ? 'sp.exe' : 'sp';
    File::Spec->catfile('spawner-bin', $platform, $fn);
}

1;
