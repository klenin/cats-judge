package CATS::ConsoleColor;

use strict;
use warnings;

use Term::ANSIColor;

use parent qw(Exporter);
our @EXPORT_OK = qw(colored);

BEGIN {
    eval { require Win32::Console::ANSI; } if $^O eq 'MSWin32';
    no warnings 'redefine';
    *colored = -t STDOUT ? *Term::ANSIColor::colored : sub { $_[0] };
}

1;

