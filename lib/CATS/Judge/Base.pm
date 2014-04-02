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

my @sid_alph = ('0'..'9', 'A'..'Z', 'a'..'z');
sub make_sid { join '', map $sid_alph[rand @sid_alph], 1..30 }

sub auth { $_[0]->{sid} = $_[0]->make_sid; 1; }

sub update_state { 0 }

sub is_locked { 0 }

sub set_request_state { abstract @_ }

sub select_request { abstract @_ }

sub lock_request {}

sub save_log_dump {}

1;
