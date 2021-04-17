package CATS::MaybeDie;

use strict;
use warnings;

use Carp;

use CATS::ConsoleColor;

use parent qw(Exporter);
our @EXPORT_OK = qw(maybe_die);

sub overridden { print @_, " overridden by --force\n" }

my $call;

# Carp::croak skips all subs from the current package, so extract it.

sub init {
    my (%opts) = @_;
    $call = $opts{force} ? \&overridden : $opts{verbose} ? \&Carp::confess : \&Carp::croak;
}

sub maybe_die { $call->(CATS::ConsoleColor::colored([ 'red' ], @_)) }

1;
