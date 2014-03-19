package CATS::Judge::Base;

use strict;
use warnings;

sub new {
    my ($class) = shift;
    my $self = { @_ };
    bless $self, $class;
    $self;
}

sub abstract { die sprintf "%s::%s is abstract", ref $_[0], (caller 1)[3] =~ /([^:]+)$/; }

sub name { $_[0]->{name} }

sub sid { abstract @_ }

1;
