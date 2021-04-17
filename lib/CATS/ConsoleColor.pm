package CATS::ConsoleColor;

use strict;
use warnings;

use Term::ANSIColor;

use parent qw(Exporter);
our @EXPORT_OK = qw(colored);

my $use_color = 0;

sub _no_color {
    ref $_[0] ? shift : pop;
    @_;
}

BEGIN {
    $use_color =
        ($ENV{CLICOLOR} // 1) && -t STDOUT && #/
        ($^O ne 'MSWin32' || eval { require Win32::Console::ANSI; 1; });
    no warnings 'redefine';
    *colored = $use_color ? *Term::ANSIColor::colored : *_no_color;
}

1;
