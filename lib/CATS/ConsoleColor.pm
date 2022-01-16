package CATS::ConsoleColor;

use strict;
use warnings;

use Term::ANSIColor;

use parent qw(Exporter);
our @EXPORT_OK = qw(colored maybe_colored);

my $use_color = 0;

sub _no_color {
    ref $_[0] ? shift : pop;
    @_;
}

sub maybe_colored {
    my ($text, $color) = @_;
    $color ? colored($text, $color) : $text;
}

BEGIN {
    $use_color =
        ($ENV{CLICOLOR} // 1) && -t STDOUT && #/
        ($^O ne 'MSWin32' || eval { require Win32::Console::ANSI; 1; });
    no warnings 'redefine';
    *colored = $use_color ? *Term::ANSIColor::colored : *_no_color;
}

1;
