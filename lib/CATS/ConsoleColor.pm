package CATS::ConsoleColor;

use strict;
use warnings;

use Term::ANSIColor;

use parent qw(Exporter);
our @EXPORT_OK = qw(colored);

BEGIN {
    my $use_color = -t STDOUT;
    eval { require Win32::Console::ANSI; 1; } or $use_color = 0 if $^O eq 'MSWin32';
    no warnings 'redefine';
    *colored = $use_color ? *Term::ANSIColor::colored : sub { $_[0] };
}

1;
