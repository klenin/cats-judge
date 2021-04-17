package CATS::ConsoleColor;

use strict;
use warnings;

use Term::ANSIColor;

use parent qw(Exporter);
our @EXPORT_OK = qw(colored);

my $use_color = 0;

sub _no_color {
    shift if ref $_[0];
    @_;
}

BEGIN {
    $use_color = -t STDOUT;
    eval { require Win32::Console::ANSI; 1; } or $use_color = 0 if $^O eq 'MSWin32';
    no warnings 'redefine';
    *colored = $use_color ? *Term::ANSIColor::colored : *_no_color;
}

1;
